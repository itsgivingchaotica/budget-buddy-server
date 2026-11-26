# S4-min (rate limit and AI cost cap): one row per user, UTC day and feature.
class AiUsage < ApplicationRecord
  self.table_name = "ai_usage"
  FEATURES = %w[categorize onboarding plan assistant].freeze

  belongs_to :user

  validates :feature, inclusion: { in: FEATURES }
  validates :requests, :input_tokens, :output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
