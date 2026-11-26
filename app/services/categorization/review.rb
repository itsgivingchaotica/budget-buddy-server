module Categorization
  # C2b (review and transfer screens), handoff #05 §B.3: what the Review
  # screen shows. Rows waiting for review, in active accounts, that aren't in
  # a suggested transfer pair (those are on the Transfers screen), grouped by
  # the merchant key AI3 uses, so one pick handles the whole group.
  module Review
    MAX_ALTERNATIVES = 2

    module_function

    # Rows that count as "to review".
    def pending(user)
      in_suggested_pairs = TransferLink.where(user:, status: "suggested")
                                       .pluck(:outflow_transaction_id, :inflow_transaction_id).flatten
      user.transactions.joins(:account).merge(Account.active).where(needs_review: true).where.not(id: in_suggested_pairs)
    end

    def remaining(user) = pending(user).count

    def groups(user)
      rows = pending(user).includes(:account).order(posted_on: :desc, id: :desc).to_a
      by_key = rows.group_by { |t| MerchantKey.for(t.normalized_description) }
      categories = Category.active_list.where.not(kind: "transfer").index_by(&:id)
      usage = category_usage(user, categories)

      by_key.map do |key, group|
        latest = group.first
        total = group.sum(&:amount)
        suggestion = most_common_suggestion(group, categories)
        {
          merchant_key: key,
          display_name: latest.description,
          count: group.size,
          total: format("%.2f", total.round(2)),
          accounts: group.map(&:account).uniq.map { |a| { id: a.id, name: a.name, purpose: a.purpose } },
          representative_transaction_id: latest.id,
          suggested_category: suggestion && category_json(suggestion),
          alternatives: alternatives(usage[total.negative? ? :out : :in], suggestion, categories).map { |c| category_json(c) },
          _sort: [-group.size, -total.abs, key]
        }
      end.sort_by { |g| g.delete(:_sort) }
    end

    # Most common suggested category in the group; ties go to the category
    # listed first (position).
    def most_common_suggestion(group, categories)
      counts = group.filter_map { |t| categories[t.suggested_category_id] }.tally
      return nil if counts.empty?

      counts.min_by { |category, n| [-n, category.position.to_i, category.id] }.first
    end

    # The user's categories, most used first, for money out and money in
    # separately. Deterministic, no AI.
    def category_usage(user, categories)
      counts = user.transactions.where.not(category_id: nil)
                   .group(:category_id, Arel.sql("amount < 0")).count
      %i[out in].to_h do |direction|
        ranked = counts.select { |(_, negative), _| negative == (direction == :out) }
                       .filter_map { |(id, _), n| categories[id] && [categories[id], n] }
                       .sort_by { |category, n| [-n, category.position.to_i, category.id] }
                       .map(&:first)
        [direction, ranked]
      end
    end

    # Up to 2 of the user's most used categories in the same direction, not
    # the suggestion; any empty slot goes to Other.
    def alternatives(ranked, suggestion, categories)
      picks = ranked.reject { |c| c == suggestion }.first(MAX_ALTERNATIVES)
      other = categories.values.find { |c| c.slug == "other" }
      picks << other if picks.size < MAX_ALTERNATIVES && other && other != suggestion && !picks.include?(other)
      picks
    end

    def category_json(category) = { id: category.id, slug: category.slug, name: category.name }
  end
end
