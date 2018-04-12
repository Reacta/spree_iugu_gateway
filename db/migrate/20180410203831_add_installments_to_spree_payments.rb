class AddInstallmentsToSpreePayments < ActiveRecord::Migration[5.1]
  def change
    add_column :spree_payments, :installments, :integer
  end
end
