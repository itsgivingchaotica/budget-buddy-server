# AI1 (rules-based categorization): merchant memory, "this user's merchant X
# is category Y". Read first by Categorization::Pipeline; written by AI3
# (learning from corrections). Owned directly by the user (AD2).
class MerchantRule < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :merchant_key, presence: true, length: { maximum: 255 }, uniqueness: { scope: :user_id }
  validates :hits, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
