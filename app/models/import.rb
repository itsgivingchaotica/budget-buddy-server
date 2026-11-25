# T1 (transactions tables): one CSV upload into one account (plan §2.2, §2.4).
# Owned through the account. The file itself is never stored (AD13, Q-27):
# row errors are line number + error code only, so no row text is kept here.
class Import < ApplicationRecord
  STATUSES = %w[processing completed failed].freeze
  ERROR_CODE = /\A[a-z][a-z0-9_]{0,49}\z/

  belongs_to :account
  has_many :transactions, dependent: :restrict_with_exception

  normalizes :filename, with: ->(name) { name.strip }

  validates :filename, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: STATUSES }
  validates :row_count, :inserted_count, :duplicate_count, :error_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :row_errors_are_line_and_code_only
  validate :data_range_in_order

  private

  def row_errors_are_line_and_code_only
    valid = row_errors.is_a?(Array) && row_errors.all? do |e|
      e.is_a?(Hash) && e.keys.map(&:to_s).sort == %w[code line] &&
        e.transform_keys(&:to_s).then { |h| h["line"].is_a?(Integer) && h["line"].positive? && h["code"].to_s.match?(ERROR_CODE) }
    end
    errors.add(:row_errors, "must be a list of { line, code } only") unless valid
  end

  def data_range_in_order
    return if data_from.nil? || data_through.nil? || data_from <= data_through

    errors.add(:data_through, "must be on or after data_from")
  end
end
