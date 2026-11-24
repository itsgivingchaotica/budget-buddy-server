class ApplicationController < ActionController::API
  include Authenticatable

  # Ownership rule (plan AD2/S3): every lookup goes through the caller's
  # scope, so another user's record is indistinguishable from a missing one.
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  private

  def render_forbidden
    render json: { error: "forbidden" }, status: :forbidden
  end

  # A reference to shared data (category, tag) that doesn't exist or isn't
  # visible to the caller (plan AD2: 422 for reference data).
  def render_invalid_reference(field)
    render json: { error: "invalid_reference", field: field }, status: :unprocessable_entity
  end
end
