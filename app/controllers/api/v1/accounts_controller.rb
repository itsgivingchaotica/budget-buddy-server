# DM-2 (accounts): the caller's accounts. Every lookup goes through
# current_user.accounts (S3 ownership rules), so another user's account is a
# 404. DELETE archives; archived accounts are read-only and hidden from the
# default list.
class Api::V1::AccountsController < ApplicationController
  before_action :require_current_user!
  before_action :set_account, only: %i[ show update destroy ]

  # GET /accounts (?include_archived=true to include archived ones)
  def index
    accounts = current_user.accounts.order(:created_at, :id)
    accounts = accounts.active unless ActiveModel::Type::Boolean.new.cast(params[:include_archived])
    render json: accounts.map { |account| account_json(account) }
  end

  # GET /accounts/1
  def show
    render json: account_json(@account)
  end

  # POST /accounts
  def create
    account = current_user.accounts.new(account_params)
    if account.save
      render json: account_json(account), status: :created
    else
      render json: { errors: account.errors }, status: :unprocessable_entity
    end
  end

  # PATCH /accounts/1
  def update
    return render json: { error: "archived" }, status: :unprocessable_entity if @account.archived?

    if @account.update(account_params)
      render json: account_json(@account)
    else
      render json: { errors: @account.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /accounts/1 -> archive (keeps the account and its transactions)
  def destroy
    @account.archive!
    head :no_content
  end

  private

  def set_account
    @account = current_user.accounts.find(params[:id])
  end

  def account_params
    params.require(:account).permit(:name, :kind, :purpose, :purpose_note)
  end

  # `data_through` per account arrives with transactions (I2).
  def account_json(account)
    account.as_json(only: %i[id name kind purpose purpose_note archived_at created_at updated_at])
  end
end
