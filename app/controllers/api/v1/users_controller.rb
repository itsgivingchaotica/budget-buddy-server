# Legacy user endpoints, kept for the current client until C0/C1 (plan S2).
# Every action acts on the caller's own record only; nothing lists or
# changes other users. Another user's id or email -> 404.
class Api::V1::UsersController < ApplicationController
  before_action :require_current_user!, except: :create
  before_action :set_own_user, only: %i[ show update destroy ]

  # GET /users -> only the caller's own record (array kept for compatibility)
  def index
    render json: [current_user]
  end

  # GET /users/1
  def show
    render json: @user
  end

  # GET /users/show_by_email?email=
  def show_by_email
    if current_user.email.present? && current_user.email.casecmp?(params[:email].to_s.strip)
      render json: current_user
    else
      render json: { error: 'User not found' }, status: :not_found
    end
  end

  # POST /users -> provisions the caller like GET /me. The request body is
  # ignored: the user's identity and email come from Kinde (SR-1).
  def create
    result = Users::KindeProvisioner.new.call(sub: current_kinde_sub, access_token: current_access_token)
    status = result.status == :created ? :created : :ok
    render json: result.user, status: status, location: api_v1_user_url(result.user)
  rescue Users::KindeProvisioner::Conflict
    render json: { error: "account_link_required" }, status: :conflict
  rescue Kinde::UserProfileFetcher::Unavailable
    render json: { error: "profile_unavailable" }, status: :service_unavailable
  end

  # PATCH/PUT /users/1 (names only; the email comes from Kinde)
  def update
    if @user.update(user_params)
      render json: @user
    else
      render json: @user.errors, status: :unprocessable_entity
    end
  end

  # DELETE /users/1
  # Known debt: a user whose accounts hold imports or transactions can't be
  # deleted (accounts keep their history; foreign keys don't cascade). Until
  # a delete-account flow is designed, that's a 409 and nothing is deleted
  # (destroy! runs in one database transaction, so earlier steps roll back).
  def destroy
    @user.destroy!
    head :no_content
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
    render json: { error: "user_has_data",
                   message: "This account still has imported transactions, so it can't be deleted yet." },
           status: :conflict
  end

  private
    def set_own_user
      @user = current_user if params[:id].to_s == current_user.id.to_s
      render json: { error: 'User not found' }, status: :not_found unless @user
    end

    def user_params
      params.require(:user).permit(:first_name, :last_name)
    end
end
