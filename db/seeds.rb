# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every env'Expense'ironment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# db/seeds.rb

categories = [
  { name: 'Expense' },
  { name: 'Income' },
  { name: 'Savings & Goals' },
  { name: 'Miscellaneous' },
  { name: 'Budgeting Strategy' },
]

categories.each do |category_attributes|
  Category.find_or_create_by(category_attributes)
end

# Define default tags with their types
Category.all.each do |category|
  case category.name
  when 'Expense'
    tags = [
      'Groceries', 'Utilities', 'Rent', 'Dining Out', 'Entertainment', 'Transportation', 
      'Healthcare', 'Education', 'Clothing', 'Personal Care', 'Gifts', 'Travel', 
      'Subscriptions', 'Home Improvement', 'Debt Repayment'
    ]
  when 'Income'
    tags = ['Salary', 'Freelance', 'Gifts Received', 'Bonuses']
  when 'Savings & Goals'
    tags = ['Emergency Fund', 'Vacation Fund', 'Retirement Savings', 'New Car Fund', 
            'Home Down Payment', 'Education Fund', 'Major Purchase', 'Debt Reduction']
  when 'Miscellaneous'
    tags = ['One-time', 'Recurring', 'Essential', 'Non-Essential', 'Planned', 'Unexpected']
  when 'Budgeting Strategy'
    tags = ['Fixed Expense', 'Variable Expense', 'Needs', 'Wants', 'Discretionary']
  else
    tags = []
  end

  tags.each do |tag_name|
    Tag.find_or_create_by(name: tag_name, category_id: category.id, default_tag: true, user_id: 1)
  end
end