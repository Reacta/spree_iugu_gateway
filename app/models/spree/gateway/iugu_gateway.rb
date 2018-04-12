module Spree
  class Gateway::IuguGateway < Gateway

    preference :test_mode, :boolean, default: true
    preference :account_id, :string, default: ''
    preference :api_key, :string, default: ''
    preference :maximum_installments, :integer, default: 12
    preference :minimum_value, :decimal, default: 0.0
    preference :installments_without_tax, :integer, default: 1
    preference :min_value_without_tax, :decimal, default: 0.0
    preference :tax_value_per_months, :hash, default: {}
    preference :webhook, :string, default: "#{Rails.application.routes.default_url_options[:host]}/iugu_webhook"

    def authorize(amount, source, gateway_options = {})
      Iugu.api_key = preferred_api_key
      payment, order = extract_payment_and_order(gateway_options) 

      if (errors = check_required_attributes(payment, order))
        return errors
      end

      token = create_token(source)

      if token.errors.present?
        raise SpreeIuguGateway::IuguTokenError, extract_error_message(token.errors)
      else
        installments_value = installments_options(order.total)
        selected_installment = installments_value[payment.installments - 1]

        order.transaction do
          adjustment = create_adjustment(order, selected_installment) if selected_installment[:total] > order.total
          charge = create_charge(payment, order, token, gateway_options)

          if charge.errors.present?
            raise SpreeIuguGateway::IuguChargeError, extract_error_message(charge.errors)
          else
            payment.started_processing!
            payment.update_attributes(amount: order.total) if adjustment.present?

            ActiveMerchant::Billing::Response.new(true, Spree.t("iugu_gateway_charge_success"), {}, authorization: charge.invoice_id)
          end
        end
      end

    rescue SpreeIuguGateway::IuguTokenError, SpreeIuguGateway::IuguChargeError => e
      ActiveMerchant::Billing::Response.new(false, e.message, {}, authorization: '')
    rescue => e
      ActiveMerchant::Billing::Response.new(false, Spree.t('iugu_gateway_failure'), {}, authorization: '')
    end

    def self.update_payment(payment)
      return false if payment.response_code.nil?

      invoice = Iugu::Invoice.fetch(payment.response_code)

      case(invoice.status)
      when 'pending'
        payment.pend!
      when 'paid'
        payment.complete!
      when 'refunded'
        payment.void!
      end
    end

    def purchase(amount, source, gateway_options = {})
      response = authorize(amount, source, gateway_options)
      return response unless response.success?
      capture(amount, response.authorization, gateway_options)
    end

    def capture(amount, response_code, gateway_options)
      Iugu.api_key = preferred_api_key
      invoice = Iugu::Invoice.fetch(response_code)

      if invoice.status == 'paid'
        return ActiveMerchant::Billing::Response.new(true, Spree.t('iugu_gateway_capture'), {}, authorization: response_code)
      else
        invoice = capture_invoice(response_code)

        if invoice.status == 'paid'
          return ActiveMerchant::Billing::Response.new(true, Spree.t('iugu_gateway_capture'), {}, authorization: response_code)
        else
          return ActiveMerchant::Billing::Response.new(false, invoice.errors, {}, {})
        end
      end
    end

    def void(response_code, gateway_options)
      refund_or_cancel_invoice(response_code, 'iugu_gateway_void')
    end

    def cancel(response_code)
      refund_or_cancel_invoice(response_code, 'iugu_gateway_cancel')
    end

    def installments_options(amount)
      ret = []

      (1..preferred_maximum_installments).each do |number|
        tax = preferred_tax_value_per_months[number.to_s].to_f || 0.0

        if (tax <= 0 || (number <= preferred_installments_without_tax and amount >= preferred_min_value_without_tax))
          value = amount.to_f / number
          tax_message = :iugu_without_tax
        else
          value = (amount.to_f + (amount.to_f * tax / 100)) / number
          tax_message = :iugu_with_tax
        end

        if (value >= preferred_minimum_value)
          value_total = value * number
          ret.push({installment: number, value: value, total: value_total, tax_message: tax_message})
        end
      end

      ret
    end

    protected

    def refund_or_cancel_invoice(response_code, i18n_key)
      Iugu.api_key = preferred_api_key
      invoice = Iugu::Invoice.fetch response_code

      return ActiveMerchant::Billing::Response.new(true, Spree.t(i18n_key), {}, authorization: response_code) if invoice.status == 'canceled'

      if invoice.status == 'paid'
        if invoice.refund
          ActiveMerchant::Billing::Response.new(true, Spree.t(i18n_key), {}, authorization: response_code)
        else
          ActiveMerchant::Billing::Response.new(false, invoice.errors, {}, {})
        end
      else
        if invoice.cancel
          ActiveMerchant::Billing::Response.new(true, Spree.t(i18n_key), {}, authorization: response_code)
        else
          ActiveMerchant::Billing::Response.new(false, invoice.errors, {}, {})
        end
      end
    end

    def successfull_status(status)
      if auto_capture?
        'paid'
      else
        'in_analysis'
      end
    end

    def check_required_attributes(payment, order)
      return ActiveMerchant::Billing::Response.new(false, Spree.t(:iugu_gateway_installment), {}, authorization: '') if payment.installments.nil?
      nil
    end

    def translate_error(error)
      errors = {
        'is not a valid credit card number' => Spree.t('iugu_error.credit_card_invalid')
      }

      errors[error].present? ? errors[error] : error
    end

    def extract_payment_and_order(gateway_options)
      order_number, payment_number = gateway_options[:order_id].split('-')
      payment = Spree::Payment.find_by(number: payment_number)
      order = Spree::Order.find_by(number: order_number)

      [payment, order]
    end

    def extract_error_message(errors)
      if errors.is_a? Hash
        arr_messages = errors.inject(Array.new) { |arr, i| arr += i[1] }
        message = arr_messages.map { |m| translate_error(m) }.join('. ')
      elsif errors.is_a? Array
        message = errors.map { |e| translate_error(e) }.join('. ')
      else
        message = translate_error(errors)
      end
      message
    end

    def create_token(source)
      name = source.name.split(' ')
      firstname = name.first
      lastname = name[1..-1].join(' ')
      token_params = {
        account_id: preferred_account_id,
        method: 'credit_card',
        test: preferred_test_mode,
        data: {
          number: source.number,
          verification_value: source.verification_value,
          first_name: firstname,
          last_name: lastname,
          month: source.month,
          year: source.year
        }
      }

      Iugu::PaymentToken.create(token_params)
    end

    def create_adjustment(order, selected_installment)
      Spree::Adjustment.create(
        adjustable: order,
        amount: (selected_installment[:total] - order.total),
        label: Spree.t(:iugu_cc_adjustment_tax),
        eligible: true,
        order: order
      )

      order.updater.update
    end

    def create_charge(payment, order, token, gateway_options)
      billing_address = gateway_options[:billing_address]

      # Grabbing order's DDD and phone
      if billing_address[:phone].include?('(')
        phone_prefix = billing_address[:phone][1..2]  rescue ''
        phone = billing_address[:phone][5..-1] rescue ''
      else
        phone_prefix = nil
        phone = billing_address[:phone]
      end

      # Make request
      params = {
        token: token.id,
        email: gateway_options[:email],
        months: payment.installments,
        items: [],
        notification_url: preferred_webhook,
        payer: {
          name: billing_address[:name],
          phone_prefix: phone_prefix,
          phone: phone,
          email: gateway_options[:customer],
          address: format_billing_address(billing_address)
        }
      }

      order.line_items.each do |item|
        params[:items] << {
            description: item.variant.name,
            quantity: item.quantity,
            price_cents: item.single_money.cents
        }
      end

      if order.shipment_total > 0
        params[:items] << {
            description: Spree.t(:shipment_total),
            quantity: 1,
            price_cents: order.display_ship_total.cents
        }
      end

      order.all_adjustments.eligible.each do |adj|
        params[:items] << {
            description: adj.label,
            quantity: 1,
            price_cents: adj.display_amount.cents
        }
      end

      Iugu::Charge.create(params)
    end

    def format_billing_address(address)
      country = Spree::Country.find_by(iso: address[:country])
      {
        street: address[:address1],
        city: address[:city],
        state: address[:state],
        country: country.try(:name),
        zip_code: address[:zip]
      }
    end

    def capture_invoice(invoice_id)
      response = api_request("https://api.iugu.com/v1/invoices/#{invoice_id}/capture")
      response_json = JSON.parse(response)

      Iugu::Factory.create_from_response Iugu::Invoice, response_json
    end

    def api_request(url, params = {})
      uri = URI(url)
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri)
      request['authorization'] = 'Basic ' + Base64.encode64(preferred_api_key + ":")
      request["user_agent"] = 'Iugu RubyLibrary'
      request.set_form_data(params)
      response = https.request(request).body
    end
  end
end
