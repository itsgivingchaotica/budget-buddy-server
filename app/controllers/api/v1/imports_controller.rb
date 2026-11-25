# I2 (import endpoint): POST /accounts/:account_id/imports, multipart with a
# `file` field. The account is looked up through current_user.accounts, so
# another user's account is a 404 before the file is even read. The file is
# parsed in memory and discarded (AD13).
class Api::V1::ImportsController < ApplicationController
  before_action :require_current_user!

  def create
    account = current_user.accounts.find(params[:account_id])
    import, result, categorized = CsvImport::Importer.call(account:, file: params[:file])
    render json: import_json(import, result).merge("categorized" => categorized.to_h), status: :created
  rescue CsvImport::Importer::Rejected => e
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  end

  private

  def import_json(import, result)
    import.as_json(only: %i[id account_id filename status row_count inserted_count duplicate_count error_count
                            row_errors data_from data_through created_at])
          .merge("skipped_count" => result.warnings.size,
                 "warnings" => result.warnings,
                 "extra_columns" => result.extra_columns)
  end
end
