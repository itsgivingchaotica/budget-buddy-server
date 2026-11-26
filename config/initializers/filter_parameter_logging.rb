# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :authorization,
  # No financial or personal text in logs (M2 ground rule). Partial matches:
  # :amount also covers target_amount, :balance covers starting_balance and
  # balance_after, :name covers first_name/last_name, :payment covers
  # monthly_payment.
  :amount, :balance, :payment, :apr, :name, :note, :description, :merchant, :email, :budgets
]
