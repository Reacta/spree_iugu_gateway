Spree::Core::Engine.routes.draw do
  namespace :api do
    namespace :v1 do
      post :iugu_webhook, to: "payments#iugu_webhook", as: :iugu_webhook
    end
  end
end
