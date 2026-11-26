# Idempotent seeds: running `bin/rails db:seed` again changes nothing.
#
# 1. Legacy categories and default tags (pre-MVP, frozen; kept for the legacy
#    client until its screens are hidden).
# 2. The MVP flat category list (DM-1, plan §2.5; labels from
#    SPEC_LEFT_TO_SPEND.md §7), keyed by slug.

# --- 1. Legacy categories and their default tags ---------------------------------

legacy_categories = {
  'Expense' => [
    'Groceries', 'Utilities', 'Rent', 'Dining Out', 'Entertainment', 'Transportation',
    'Healthcare', 'Education', 'Clothing', 'Personal Care', 'Gifts', 'Travel',
    'Subscriptions', 'Home Improvement', 'Debt Repayment'
  ],
  'Income' => ['Salary', 'Freelance', 'Gifts Received', 'Bonuses'],
  'Savings & Goals' => ['Emergency Fund', 'Vacation Fund', 'Retirement Savings', 'New Car Fund',
                        'Home Down Payment', 'Education Fund', 'Major Purchase', 'Debt Reduction'],
  'Miscellaneous' => ['One-time', 'Recurring', 'Essential', 'Non-Essential', 'Planned', 'Unexpected'],
  'Budgeting Strategy' => ['Fixed Expense', 'Variable Expense', 'Needs', 'Wants', 'Discretionary']
}

legacy_categories.each do |name, tag_names|
  # Legacy rows are identified by category_type = 'default'; new MVP rows leave
  # it NULL, so the new "Income" category never matches here (plan K8).
  category = Category.find_or_create_by!(name: name, category_type: 'default') do |c|
    c.kind = 'legacy'
    c.active = false
  end
  # Only fills the new slug column, and only where it's still empty.
  category.update_columns(slug: "legacy-#{name.parameterize}") if category.slug.nil?

  tag_names.each do |tag_name|
    Tag.find_or_create_by!(name: tag_name, category_id: category.id, default_tag: true, user_id: nil)
  end
end

# --- 2. MVP flat category list ------------------------------------------------------
# [slug, name, kind, fixed_variable, need_want, recurrence_label]
mvp_categories = [
  ['groceries',        'Groceries',        'spending', 'variable', 'need', nil],
  ['dining-out',       'Dining Out',       'spending', 'variable', 'want', nil],
  ['entertainment',    'Entertainment',    'spending', 'variable', 'want', nil],
  ['transportation',   'Transportation',   'spending', 'variable', 'need', nil],
  ['healthcare',       'Healthcare',       'spending', 'variable', 'need', nil],
  ['clothing',         'Clothing',         'spending', 'variable', 'want', nil],
  ['personal-care',    'Personal Care',    'spending', 'variable', 'want', nil],
  ['gifts',            'Gifts',            'spending', 'variable', 'want', nil],
  ['travel',           'Travel',           'spending', 'variable', 'want', nil],
  ['home-improvement', 'Home Improvement', 'spending', 'variable', 'want', nil],
  ['other',            'Other',            'spending', 'variable', nil,    nil],
  ['rent',             'Rent',             'spending', 'fixed',    'need', 'recurring'],
  ['utilities',        'Utilities',        'spending', 'fixed',    'need', 'recurring'],
  ['subscriptions',    'Subscriptions',    'spending', 'fixed',    'want', 'recurring'],
  ['insurance',        'Insurance',        'spending', 'fixed',    'need', 'recurring'],
  ['debt-payments',    'Debt Payments',    'spending', 'fixed',    'need', 'recurring'],
  ['education',        'Education',        'spending', 'fixed',    'need', nil],
  ['income',           'Income',           'income',   nil,        nil,    nil],
  ['transfers',        'Transfers',        'transfer', nil,        nil,    nil]
]

mvp_categories.each_with_index do |(slug, name, kind, fixed_variable, need_want, recurrence_label), index|
  category = Category.find_or_initialize_by(slug: slug)
  category.assign_attributes(
    name: name, kind: kind, active: true, position: index + 1,
    fixed_variable: fixed_variable, need_want: need_want, recurrence_label: recurrence_label
  )
  category.save! if category.new_record? || category.changed?
end
