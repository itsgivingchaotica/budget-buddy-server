# frozen_string_literal: true

# S1b: authentication requires the Kinde issuer and API audience. Fail at boot
# in development and production if either is missing, rather than on the first
# request. Tests install their own verifier (test/support/auth_test_helper.rb).
#
# Building the verifier makes no network calls; Kinde's keys are fetched on
# the first authenticated request and cached.
Rails.application.config.to_prepare do
  Authenticatable.verifier unless Rails.env.test?
end
