require "digest"

# T1 (transactions tables): one bank movement in one of the user's accounts
# (plan §2.2). Owned through the account: reach it with
# `current_user.transactions`, never by a bare id.
#
# Sign convention (§2.4, PO-17): negative = money out of the account,
# positive = money in. Zero is never stored.
#
# Duplicate detection (§2.3): `base_key` = SHA-256 of
# "posted_on | amount in cents | normalized description", unique per account
# with `occurrence` (the Nth identical row in one file). When the bank gives
# a transaction id, the row is keyed on it instead (`external_id`, unique per
# account): its base_key is derived from the id, with occurrence 1, so two
# different bank ids with identical content never block each other.
class Transaction < ApplicationRecord
  SOURCES = %w[user memory rule ai transfer none].freeze

  # Trailing noise stripped from descriptions before keys and rules
  # (§2.4: "trailing store numbers / card fragments, by a fixed rule list").
  # Applied repeatedly from the end, so "SHOP #12 XXXX1234" -> "SHOP".
  TRAILING_NOISE = [
    /\s+#\s*\d+\z/,               # store number: "TARGET #1234"
    /\s+(?:X{2,}|\*{2,})\d{2,4}\z/, # card fragment: "XXXX1234", "****1234"
    /\s+CARD\s+\d{4}\z/,          # "CARD 1234"
    /\s+\d{3,}\z/                 # bare store/terminal number: "STARBUCKS 08812"
  ].freeze

  belongs_to :account
  belongs_to :import, optional: true
  belongs_to :category, optional: true

  normalizes :description, with: ->(text) { text.strip }
  normalizes :external_id, with: ->(id) { id.strip.presence }

  before_validation :derive_keys

  validates :posted_on, presence: true
  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :description, presence: true, length: { maximum: 255 }
  validates :normalized_description, presence: true, length: { maximum: 255 }
  validates :external_id, length: { maximum: 255 }, allow_nil: true
  validates :occurrence, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :categorization_source, inclusion: { in: SOURCES }
  validates :confidence, numericality: { in: 0..1 }, allow_nil: true
  validates :base_key, uniqueness: { scope: %i[account_id occurrence] }
  validates :external_id, uniqueness: { scope: :account_id }, allow_nil: true
  validate :category_matches_source
  validate :category_is_on_the_active_list
  validate :import_is_for_the_same_account

  scope :uncategorized, -> { where(category_id: nil) }

  def self.normalize_description(text)
    normalized = text.to_s.upcase.gsub(/\s+/, " ").strip
    loop do
      stripped = TRAILING_NOISE.reduce(normalized) { |s, pattern| s.sub(pattern, "") }
      break if stripped == normalized

      normalized = stripped
    end
    # Upper-casing can lengthen some characters (e.g. "ß" -> "SS").
    normalized[0, 255]
  end

  # The duplicate key for a row: from the bank id when there is one,
  # otherwise from the row's content. Shared with the importer (I2).
  def self.duplicate_key_for(posted_on:, amount:, normalized_description:, external_id: nil)
    return Digest::SHA256.hexdigest("external_id|#{external_id}") if external_id.present?

    base_key_for(posted_on:, amount:, normalized_description:)
  end

  def self.base_key_for(posted_on:, amount:, normalized_description:)
    cents = (BigDecimal(amount.to_s) * 100).to_i
    Digest::SHA256.hexdigest("#{posted_on.iso8601}|#{cents}|#{normalized_description}")
  end

  def outflow?
    amount.to_d.negative?
  end

  def inflow?
    amount.to_d.positive?
  end

  private

  def derive_keys
    return if description.blank?

    self.normalized_description = self.class.normalize_description(description)
    return if posted_on.nil? || amount.nil?

    self.base_key = self.class.duplicate_key_for(posted_on:, amount:, normalized_description:, external_id:)
  end

  def category_matches_source
    if categorization_source == "none" && category_id.present?
      errors.add(:categorization_source, "can't be none when a category is set")
    elsif categorization_source != "none" && category_id.nil?
      errors.add(:category, "is required when categorization_source is #{categorization_source}")
    end
  end

  def category_is_on_the_active_list
    return if category.nil? || Category.active_list.exists?(category.id)

    errors.add(:category, "must be an active category")
  end

  def import_is_for_the_same_account
    return if import.nil? || import.account_id == account_id

    errors.add(:import, "must belong to the same account")
  end
end
