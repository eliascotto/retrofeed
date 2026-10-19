class RemovePlainTokenColumnsFromUsers < ActiveRecord::Migration[8.1]
  def change
    # Tokens are now signed, self-expiring values generated via
    # generates_token_for and are never persisted. The email_confirmation_sent_at
    # column is kept because it still drives the resend rate-limiting.
    remove_index :users, :email_confirmation_token, unique: true
    remove_column :users, :email_confirmation_token, :string
    remove_column :users, :password_reset_token, :string
    remove_column :users, :password_reset_token_expires_at, :datetime
  end
end
