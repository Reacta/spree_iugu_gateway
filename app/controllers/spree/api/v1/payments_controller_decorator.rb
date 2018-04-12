Spree::Api::V1::PaymentsController.class_eval do
  skip_before_action :authenticate_user, only: [:iugu_webhook]
  skip_before_action :find_order, only: [:iugu_webhook]

  def iugu_webhook
    if Spree::Gateway::IuguGateway.update_payment(find_payment_by_response_code)
      head :ok
    else
      head :forbidden
    end
  end

  private 

  def find_payment_by_response_code
    Spree::Payment.find_by(response_code: response_code)
  end

  def response_code
    params[:data][:id]
  end
end