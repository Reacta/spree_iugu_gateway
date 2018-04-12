require 'spec_helper'

describe Spree::Gateway::IuguGateway, type: :model do
  let(:object) { create(:iugu_cc_payment_method) }
  let(:response_code) { 'ABC19A61A78A4665914426EA752B0001' }
  let(:token) { '884629730509465AA89387529A56EE3C' }
  let!(:credit_card) { create(:iugu_credit_card) }
  let!(:payment) { create(:iugu_cc_payment) }

  let(:token_request) do
    { url: 'https://api.iugu.com/v1/payment_token', filename: 'create_token' }
  end
  
  let(:token_request_error) do
    { url: 'https://api.iugu.com/v1/payment_token', filename: 'create_token_error' }
  end

  let(:charge_request) do
    {
      url: 'https://api.iugu.com/v1/charge',
      filename: 'create_charge',
      method: :post,
      body: hash_including(token: token)
    }
  end

  let(:charge_request_error) do
    {
      url: 'https://api.iugu.com/v1/charge',
      method: :post,
      body: hash_including(token: token),
      filename: 'create_charge_error'
    }
  end

  let(:invoice_request) do
    {
      filename: 'fetch_invoice', 
      method: :get, 
      url: "https://api.iugu.com/v1/invoices/#{response_code}", 
      body: {}
    }
  end

  let(:refund_request) do
    {
      filename: 'refund_invoice', 
      method: :post, 
      body: {},
      url: "https://api.iugu.com/v1/invoices/#{response_code}/refund"
    }
  end

  before { Iugu.api_key = '' }

  it 'payment_source_class should be CreditCard' do
    expect(object.payment_source_class).to eq Spree::CreditCard
  end

  context 'authorize' do
    it 'should create token and make the payment on Iugu' do
      stub_iugu token_request
      stub_iugu charge_request

      object.update_attributes(auto_capture: false)
      response = object.authorize '1599', credit_card, payment.gateway_options

      expect(response.success?).to be_truthy
      expect(response.authorization).to eq response_code
    end

    context 'error' do
      it 'should not purchase when Iugu return an error when create the token' do
        stub_iugu token_request_error

        object.update_attributes(auto_capture: false)
        response = object.authorize '1599', credit_card, payment.gateway_options
        expect(response.success?).to be_falsey
      end

      it 'should not purchase when Iugu return error' do
        stub_iugu token_request
        stub_iugu charge_request_error

        object.update_attributes(auto_capture: false)
        response = object.authorize '1599', credit_card, payment.gateway_options
        expect(response.success?).to be_falsey
      end
    end
  end

  context 'purchase' do
    let(:invoices_request) do
      {
        method: :get,
        url: 'https://api.iugu.com/v1/invoices',
        filename: 'fetch_invoices'
      }
    end

    it 'should create token and make the payment on Iugu' do
      stub_iugu token_request
      stub_iugu charge_request
      stub_iugu invoice_request

      object.update_attributes(auto_capture: true)
      response = object.purchase '1599', credit_card, payment.gateway_options

      expect(response.success?).to be_truthy
      expect(response.authorization).to eq response_code
    end

    context 'error' do
      it 'should not purchase when Iugu return an error when create the token' do
        stub_iugu token_request_error

        object.update_attributes(auto_capture: true)
        response = object.purchase '1599', credit_card, payment.gateway_options
        expect(response.success?).to be_falsey
      end

      it 'should not purchase when Iugu return error' do
        stub_iugu token_request
        stub_iugu charge_request_error
        stub_iugu invoice_request

        object.update_attributes(auto_capture: true)
        response = object.purchase '1599', credit_card, payment.gateway_options
        expect(response.success?).to be_falsey
      end
    end
  end

  context 'capture' do
    it 'should capture successfully' do
      stub_iugu(
        filename: 'fetch_invoice_in_analysis', 
        method: :get,
        url: "https://api.iugu.com/v1/invoices/#{response_code}",
        body: {}
      )

      stub_iugu(
        filename: 'fetch_invoice', 
        method: :post,
        url: "https://api.iugu.com/v1/invoices/#{response_code}/capture",
        body: {},
        encoded: true,
        headers: {
          Authorization: 'Basic ' + Base64.encode64(object.preferred_api_key + ":")
        }
      )

      response = object.capture 10, response_code, payment.gateway_options
      expect(response.success?).to be_truthy
    end
  end

  context 'void' do
    it 'should void successfully' do
      stub_iugu invoice_request
      stub_iugu refund_request

      response = object.void response_code, payment.gateway_options
      expect(response.success?).to be_truthy
    end

    it 'should return error when Iugu does not refund' do
      stub_iugu invoice_request
      stub_iugu(
        filename: 'refund_invoice_error', 
        method: :post, 
        body: {},
        url: "https://api.iugu.com/v1/invoices/#{response_code}/refund"
      )

      response = object.void response_code, payment.gateway_options
      expect(response.success?).to be_falsey
    end
  end

  context 'cancel' do
    it 'should void successfully' do
      stub_iugu invoice_request
      stub_iugu refund_request

      response = object.cancel response_code
      expect(response.success?).to be_truthy
    end

    it 'should return error when Iugu does not refund' do
      stub_iugu invoice_request
      stub_iugu(
        filename: 'refund_invoice_error', 
        method: :post, 
        body: '{}',
        url: "https://api.iugu.com/v1/invoices/#{response_code}/refund"
      )

      response = object.cancel response_code
      expect(response.success?).to be_falsey
    end
  end

  context 'calculating installments' do
    it 'should calculate installments without tax' do
      object.preferred_installments_without_tax = 5
      object.preferred_maximum_installments = 5
      installments = object.installments_options 100

      expect(installments[0]).to eq(installment: 1, value: 100.0, total: 100.0, tax_message: :iugu_without_tax)
      expect(installments[1]).to eq(installment: 2, value: 50.0, total: 100.0, tax_message: :iugu_without_tax)
      expect(installments[2]).to eq(installment: 3, value: 33.333333333333336, total: 100.0, tax_message: :iugu_without_tax)
      expect(installments[3]).to eq(installment: 4, value: 25.0, total: 100.0, tax_message: :iugu_without_tax)
      expect(installments[4]).to eq(installment: 5, value: 20.0, total: 100.0, tax_message: :iugu_without_tax)
    end

    it 'should return the number of installments respecting the minimum value' do
      object.preferred_installments_without_tax = 10
      object.preferred_maximum_installments = 10
      object.preferred_minimum_value = 20
      installments = object.installments_options 50

      expect(installments.size).to eq 2
    end

    it 'should calculate installments with tax' do
      order = create(:order, total: 100.0)
      object.preferred_installments_without_tax = 1
      object.preferred_maximum_installments = 6
      object.preferred_minimum_value = 10
      object.preferred_tax_value_per_months = {
        '1' => 0.0,
        '2' => 1.0,
        '3' => 1.5,
        '4' => 2.0,
        '5' => 2.5,
        '6' => 3.0
      }
      installments = object.installments_options 100

      expect(installments[0]).to eq(installment: 1, value: 100.0, total: 100.0, tax_message: :iugu_without_tax)
      expect(installments[1]).to eq(installment: 2, value: 50.5, total: 101.00, tax_message: :iugu_with_tax)
      expect(installments[2]).to eq(installment: 3, value: 33.833333333333336, total: 101.5, tax_message: :iugu_with_tax)
      expect(installments[3]).to eq(installment: 4, value: 25.5, total: 102.0, tax_message: :iugu_with_tax)
      expect(installments[4]).to eq(installment: 5, value: 20.5, total: 102.5, tax_message: :iugu_with_tax)
      expect(installments[5]).to eq(installment: 6, value: 17.166666666666668, total: 103.0, tax_message: :iugu_with_tax)
    end
  end

  context 'webhook' do
    it 'should transit payment from checkout to pending' do
      stub_iugu(
        filename: 'fetch_invoice_pending', 
        method: :get,
        url: "https://api.iugu.com/v1/invoices/#{response_code}",
        body: {}
      )

      payment.response_code = response_code
      object.class.update_payment(payment)
      expect(payment.state).to eq('pending')
    end

    it 'should transit payment from pending to completed' do
      stub_iugu invoice_request

      payment.response_code = response_code
      payment.state = 'pending'
      object.class.update_payment(payment)
      expect(payment.state).to eq('completed')
    end

    it 'should transit payment to void when payment refunded' do
      stub_iugu(
        filename: 'refund_invoice', 
        method: :get,
        url: "https://api.iugu.com/v1/invoices/#{response_code}",
        body: {}
      )

      payment.response_code = response_code
      payment.state = 'completed'
      object.class.update_payment(payment)
      expect(payment.state).to eq('void')
    end
  end
end
