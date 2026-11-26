class Tag < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :category, optional: true
  has_many :entries_tags
  has_and_belongs_to_many :entries

  validates :name, presence: true

  # Global default tags plus the user's own (S3-L).
  scope :visible_to, ->(user) { where(default_tag: true).or(where(user_id: user.id)) }
end