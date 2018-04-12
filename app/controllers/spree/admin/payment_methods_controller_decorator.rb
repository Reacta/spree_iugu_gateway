Spree::Admin::PaymentMethodsController.class_eval do
  before_action :set_tax_value, only: :update

  private

  def set_tax_value
    return if params[:tax_value].nil?

    tax_value = {}
    params[:tax_value].each_with_index do |tax, i|
      installment = i + 1
      tax.gsub! ',', '.'
      tax_value[installment.to_s] = tax
    end

    params[:payment_method_iugu_gateway][:preferred_tax_value_per_months] = tax_value
  end

  def payment_method_params
    params.require(:payment_method).permit!.to_h
  end

  def preferences_params
    key = ActiveModel::Naming.param_key(@payment_method)
    return {} unless params.key? key
    params.require(key).permit!.merge(params.require(key).permit(preferred_tax_value_per_months: {})).to_h
  end
end