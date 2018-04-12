require 'spec_helper'

describe Spree::Api::V1::PaymentsController, type: :controller do
  let(:payment) { create(:iugu_cc_payment) }
  let(:response_code) { 'ABC19A61A78A4665914426EA752B0001' }

  before do
    Iugu.api_key = ''
    payment.response_code = response_code
    payment.save!
  end

  context 'when webhook receives invoice change' do
    it 'should update payment to pending' do
      stub_iugu(
        filename: 'fetch_invoice_pending', 
        method: :get,
        url: "https://api.iugu.com/v1/invoices/#{response_code}",
        body: {}
      )

      post :iugu_webhook, params: { event: 'invoice.status_changed', data: { id: response_code, status: 'pending' }}
      expect(response.status).to eq 200
      expect(Spree::Payment.find_by(response_code: response_code).state).to eq 'pending'
    end
  end
end