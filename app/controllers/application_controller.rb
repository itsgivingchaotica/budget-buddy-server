class ApplicationController < ActionController::API
  include Authenticatable

  # No financial text in logs: an unexpected error is logged as a safe one-line
  # description (SafeError), never its message, and the client gets a bare
  # status. Declared first so the specific handlers below win. Tests re-raise
  # so failures show their message; the logging test turns that off.
  class_attribute :reraise_unexpected_errors, default: Rails.env.test?
  rescue_from StandardError, with: :render_unexpected_error

  # Ownership rule (plan AD2/S3): every lookup goes through the caller's
  # scope, so another user's record is indistinguishable from a missing one.
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  private

  def render_unexpected_error(error)
    raise error if reraise_unexpected_errors

    status = ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name)
    Rails.logger.error("[error] #{SafeError.describe(error)}")
    code = status == 500 ? "server_error" : (Rack::Utils::SYMBOL_TO_STATUS_CODE.key(status) || "error").to_s
    render json: { error: code }, status:
  end

  def render_forbidden
    render json: { error: "forbidden" }, status: :forbidden
  end

  # A reference to shared data (category, tag) that doesn't exist or isn't
  # visible to the caller (plan AD2: 422 for reference data).
  def render_invalid_reference(field)
    render json: { error: "invalid_reference", field: field }, status: :unprocessable_entity
  end
end
