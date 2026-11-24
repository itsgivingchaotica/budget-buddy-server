# One shared, read-only category list (DM-1, plan §2.5):
#   kind 'spending' - the 17 spending categories, each labelled fixed/variable
#   kind 'income'   - one Income category
#   kind 'transfer' - Transfers, assigned only by confirming a transfer (TR1)
#   kind 'legacy'   - the 5 pre-MVP rows, kept inactive for the legacy client
#
# Stable references use `slug` (ids differ between databases). New categories
# leave `category_type` NULL, so the legacy `categories#default` endpoint
# still returns only the 5 legacy rows.
class Category < ApplicationRecord
  KINDS = %w[spending income transfer legacy].freeze
  NEED_WANT = %w[need want].freeze
  FIXED_VARIABLE = %w[fixed variable].freeze
  RECURRENCE_LABELS = %w[one_time recurring].freeze

  has_many :tags
  has_many :entries

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :slug, presence: true, unless: :legacy?
  validates :slug, uniqueness: true, allow_nil: true
  validates :need_want, inclusion: { in: NEED_WANT }, allow_nil: true
  validates :fixed_variable, inclusion: { in: FIXED_VARIABLE }, allow_nil: true
  validates :fixed_variable, presence: true, if: :spending?
  validates :recurrence_label, inclusion: { in: RECURRENCE_LABELS }, allow_nil: true

  # The list the app shows and the AI may choose from (never legacy rows).
  scope :active_list, -> { where(active: true).where.not(kind: "legacy").order(:position, :id) }
  scope :spending, -> { where(kind: "spending") }
  # "Flexible" for Left to spend (spec §7): active spending categories labelled variable.
  scope :flexible, -> { spending.where(active: true, fixed_variable: "variable") }

  KINDS.each do |k|
    define_method(:"#{k}?") { kind == k }
  end
end
