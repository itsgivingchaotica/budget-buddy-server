# DM-3 (category budgets), plan §2.2: a monthly budget for one flexible
# category. A row applies from its month (effective_from, always the 1st)
# until a later row replaces it; the amount a month uses is the row in effect
# on that month's 1st. Only flexible categories (active spending, labelled
# variable) have budgets: fixed categories are bills (PO, 2026-11-26).
class CategoryBudget < ApplicationRecord
  SOURCES = %w[user coach].freeze
  MAX_AMOUNT = BigDecimal("9999999999.99")

  belongs_to :user
  belongs_to :category

  validates :period, inclusion: { in: %w[month] }
  validates :amount, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_AMOUNT }
  validates :source, inclusion: { in: SOURCES }
  validates :category_id, uniqueness: { scope: %i[user_id effective_from] }
  validate :starts_on_the_first
  validate :category_is_flexible

  # The row in effect on `date` for each of the user's budgeted categories
  # (latest effective_from on or before it).
  def self.in_effect_on(user, date)
    where(user:).where("effective_from <= ?", date)
                .select("DISTINCT ON (category_budgets.category_id) category_budgets.*")
                .order(:category_id, effective_from: :desc)
  end

  private

  def starts_on_the_first
    errors.add(:effective_from, "must be the 1st of a month") if effective_from && effective_from.day != 1
  end

  def category_is_flexible
    return if category.nil? || Category.flexible.exists?(category.id)

    errors.add(:category, "must be a flexible spending category (fixed costs are bills)")
  end
end
