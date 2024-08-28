# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# db/seeds.rb

# Define default tags with their types
default_tags = [
  # Expense Tags
  { name: 'Groceries', tag_type: 'Expense', default_tag: true },
  { name: 'Utilities', tag_type: 'Expense', default_tag: true },
  { name: 'Rent', tag_type: 'Expense', default_tag: true },
  { name: 'Dining Out', tag_type: 'Expense', default_tag: true },
  { name: 'Entertainment', tag_type: 'Expense', default_tag: true },
  { name: 'Transportation', tag_type: 'Expense', default_tag: true },
  { name: 'Healthcare', tag_type: 'Expense', default_tag: true },
  { name: 'Education', tag_type: 'Expense', default_tag: true },
  { name: 'Clothing', tag_type: 'Expense', default_tag: true },
  { name: 'Personal Care', tag_type: 'Expense', default_tag: true },
  { name: 'Gifts', tag_type: 'Expense', default_tag: true },
  { name: 'Travel', tag_type: 'Expense', default_tag: true },
  { name: 'Subscriptions', tag_type: 'Expense', default_tag: true },
  { name: 'Home Improvement', tag_type: 'Expense', default_tag: true },
  { name: 'Debt Repayment', tag_type: 'Expense', default_tag: true },

  # Income Tags
  { name: 'Salary', tag_type: 'Income', default_tag: true },
  { name: 'Freelance', tag_type: 'Income', default_tag: true },
  { name: 'Gifts Received', tag_type: 'Income', default_tag: true },
  { name: 'Bonuses', tag_type: 'Income', default_tag: true },

  # Savings & Goals Tags
  { name: 'Emergency Fund', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'Vacation Fund', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'Retirement Savings', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'New Car Fund', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'Home Down Payment', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'Education Fund', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'Major Purchase', tag_type: 'Savings & Goals', default_tag: true },
  { name: 'Debt Reduction', tag_type: 'Savings & Goals', default_tag: true },

  # Miscellaneous Tags
  { name: 'One-time', tag_type: 'Miscellaneous', default_tag: true },
  { name: 'Recurring', tag_type: 'Miscellaneous', default_tag: true },
  { name: 'Essential', tag_type: 'Miscellaneous', default_tag: true },
  { name: 'Non-Essential', tag_type: 'Miscellaneous', default_tag: true },
  { name: 'Planned', tag_type: 'Miscellaneous', default_tag: true },
  { name: 'Unexpected', tag_type: 'Miscellaneous', default_tag: true },

  # Tags for Budgeting Strategies
  { name: 'Fixed Expense', tag_type: 'Budgeting Strategy', default_tag: true },
  { name: 'Variable Expense', tag_type: 'Budgeting Strategy', default_tag: true },
  { name: 'Needs', tag_type: 'Budgeting Strategy', default_tag: true },
  { name: 'Wants', tag_type: 'Budgeting Strategy', default_tag: true },
  { name: 'Discretionary', tag_type: 'Budgeting Strategy', default_tag: true },
]

# Create or find the tags
default_tags.each do |tag_attributes|
  Tag.find_or_create_by(tag_attributes.merge(user_id: 1))
end


