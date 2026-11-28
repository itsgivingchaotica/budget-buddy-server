# PL1 (plan drafting): a coach draft plan (SPEC_ONBOARDING_PLAN §6.4, D-032).
# Nothing in `payload` is live until PL2 (plan approval) creates the rows.
class PlanProposal < ApplicationRecord
  STATUSES = %w[draft approved superseded].freeze
  SOURCES = %w[model fallback].freeze
  STALE_AFTER = 7.days

  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }

  scope :drafts, -> { where(status: "draft") }

  # Worked out on read (D-032): older than 7 days, or created before a newer
  # import, so its figures may no longer match the data.
  def stale?(now: Time.current)
    return false unless status == "draft"

    created_at < now - STALE_AFTER || user.imports.where("imports.created_at > ?", created_at).exists?
  end
end
