module Categorization
  # AI1 (rules-based categorization): categorizes a user's uncategorized
  # transactions, cheapest first:
  #   1. merchant memory  - the user's own merchant_rules (source "memory")
  #   2. keyword rules    - KeywordRules (source "rule")
  #   3. AI               - only for rows 1-2 couldn't place (source "ai").
  #                         Until AI2 it's DisabledAi, which places nothing.
  # Rows nothing could place, or the AI wasn't sure about (confidence below
  # AI_MIN_CONFIDENCE), stay uncategorized with needs_review = true.
  #
  # Only rows that are still uncategorized (source "none") are touched, so a
  # user's own choice is never overwritten. Every category comes from the
  # active list; Transfers is never assigned here (only TR1 does that).
  class Pipeline
    AI_MIN_CONFIDENCE = BigDecimal("0.6")

    Summary = Data.define(:memory, :rule, :ai, :needs_review) do
      def to_h = { memory:, rule:, ai:, needs_review: }
    end

    def self.call(user:, scope:, ai: nil)
      new(user:, scope:, ai: ai || ai_for(user)).call
    end

    # The AI step for a user. DisabledAi until AI2 (Claude categorization).
    def self.ai_for(_user) = DisabledAi.new

    def initialize(user:, scope:, ai:)
      @user = user
      @scope = scope
      @ai = ai
    end

    def call
      rows = @scope.merge(@user.transactions).where(category_id: nil, categorization_source: "none")
                   .pluck(:id, :normalized_description, :amount)
      purposes = @user.transactions.where(id: rows.map(&:first)).joins(:account).pluck(:id, "accounts.purpose").to_h
      return Summary.new(memory: 0, rule: 0, ai: 0, needs_review: 0) if rows.empty?

      categories = Category.active_list.where.not(kind: %w[transfer legacy]).to_h { |c| [c.slug, c] }
      keys = rows.to_h { |id, normalized, _| [id, MerchantKey.for(normalized)] }

      # 1. Merchant memory
      memory = @user.merchant_rules.where(merchant_key: keys.values.uniq).includes(:category)
                    .select { |r| categories.key?(r.category&.slug) }.index_by(&:merchant_key)
      by_memory, rest = rows.partition { |id, _, _| memory.key?(keys[id]) }

      # 2. Keyword rules
      by_rule = {}
      rest = rest.reject do |id, _, amount|
        slug = KeywordRules.match(keys[id], amount)
        by_rule[id] = slug if slug && categories.key?(slug)
      end

      # 3. AI, for what's left (nothing, until AI2)
      by_ai, unsure = ai_step(rest, keys, categories, purposes)

      ActiveRecord::Base.transaction do
        assign(by_memory.group_by { |id, _, _| memory[keys[id]].category_id }.transform_values { |rs| rs.map(&:first) }, "memory")
        assign(by_rule.group_by { |_, slug| categories[slug].id }.transform_values { |ps| ps.map(&:first) }, "rule")
        by_ai.each do |id, (slug, confidence)|
          pending.where(id:).update_all(category_id: categories[slug].id, categorization_source: "ai",
                                        confidence:, needs_review: false, updated_at: Time.current)
        end
        pending.where(id: unsure).update_all(needs_review: true, updated_at: Time.current)
        touch_memory(memory, by_memory, keys)
      end

      Summary.new(memory: by_memory.size, rule: by_rule.size, ai: by_ai.size, needs_review: unsure.size)
    end

    private

    # Still-uncategorized rows only, re-checked at write time.
    def pending
      @user.transactions.where(category_id: nil, categorization_source: "none")
    end

    def assign(ids_by_category, source)
      ids_by_category.each do |category_id, ids|
        pending.where(id: ids).update_all(category_id:, categorization_source: source, confidence: nil,
                                          needs_review: false, updated_at: Time.current)
      end
    end

    # Returns [{ id => [slug, confidence] }, [ids for review]].
    def ai_step(rest, keys, categories, purposes)
      return [{}, []] if rest.empty?

      items = rest.each_with_index.map do |(id, _, amount), index|
        { index:, merchant: keys[id], amount: amount.to_s("F"), account_purpose: purposes[id] }
      end
      # S4-min: if the AI is unavailable or the daily cap is reached, the
      # rows go to review; memory and rule results are still saved.
      answers = begin
        Array(@ai.categorize(items:, allowed_slugs: categories.keys))
      rescue AiBudget::Exceeded, AnthropicClient::Error => e
        Rails.logger.info("[ai] categorize skipped: #{e.class.name}")
        []
      end

      placed = {}
      answers.each do |answer|
        answer = answer.to_h.transform_keys(&:to_sym)
        row = rest[answer[:index]] if answer[:index].is_a?(Integer) && answer[:index] >= 0
        next if row.nil? || placed.key?(row.first)

        confidence = BigDecimal(answer[:confidence].to_s) rescue nil
        next unless categories.key?(answer[:category_slug].to_s) && confidence && confidence.between?(AI_MIN_CONFIDENCE, 1)

        placed[row.first] = [answer[:category_slug].to_s, confidence]
      end
      [placed, rest.map(&:first) - placed.keys]
    end

    def touch_memory(memory, by_memory, keys)
      by_memory.map { |id, _, _| keys[id] }.tally.each do |key, count|
        MerchantRule.where(id: memory[key].id).update_all(["hits = hits + ?, last_used_at = ?", count, Time.current])
      end
    end
  end
end
