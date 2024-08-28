class Budget < ApplicationRecord
  belongs_to :user
  has_many :entries, dependent: :destroy
  has_many :tags, through: :entries

  after_create :associate_default_tags

  private

  # establish the association between the newly created budget and the default tags
  def associate_default_tags
    default_tags = Tag.where(default_tag: true)
    self.tags = default_tags
  end
end