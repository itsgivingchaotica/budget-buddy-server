ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/auth_test_helper"
require_relative "support/spending_scenario"

AuthTestHelper.install_verifier!
AuthTestHelper.install_profile_fetcher!

module ActiveSupport
  class TestCase
    include AuthTestHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
