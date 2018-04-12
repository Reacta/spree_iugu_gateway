FactoryBot.define do
  factory :iugu_cc_payment_method, class: Spree::Gateway::IuguGateway do
    name 'Iugu Credit Card'
    created_at Date.today
  end

  factory :iugu_credit_card, class: Spree::CreditCard do
    verification_value 123
    month 12
    year { 1.year.from_now.year }
    number '4111111111111111'
    name 'Spree Commerce'
    cc_type 'visa'
    association(:payment_method, factory: :iugu_cc_payment_method)
  end

  factory :iugu_cc_payment, class: Spree::Payment do
    amount 15.00
    order
    state 'checkout'
    installments 1
    association(:payment_method, factory: :iugu_cc_payment_method)
    association(:source, factory: :iugu_credit_card)
  end
end
