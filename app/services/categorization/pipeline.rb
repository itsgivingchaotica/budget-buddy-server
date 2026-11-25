module Categorization
  # AI1 (rules-based categorization): categorizes a user's uncategorized
  # transactions, cheapest first:
  #   1. merchant memory  - the user's own merchant_rules (source "memory")
  #   -  transfer check   - rows that look like money moved between the
  #                         user's own accounts go straight to review for
  #                         TR1, and never to Claude (TransferCheck)
  #   2. keyword rules    - KeywordRules (source "rule")
  #   3. AI               - only for rows 1-2 couldn't place (source "ai"):
  #                         Claude (AI2) when configured, else DisabledAi.
  # Rows nothing could place, or the AI wasn't sure about (confidence below
  # AI_MIN_CONFIDENCE), stay uncategorized with needs_review = true.
  #
  # AI2: at most AI_ROWS_PER_RUN rows go to the AI per run, in batches of
  # AI_BATCH_SIZE. A row the AI answered (even with a refusal or a cut-off
  # answer, which send it to review) gets ai_attempted_at and isn't sent
  # again. If a batch fails (API error, 429, daily cap), that batch and the
  # rest keep ai_attempted_at = nil, so the next run resumes them; nothing
  # already saved is lost. `remaining` = rows in scope still waiting for AI.
  #
  # Only rows that are still uncategorized (source "none") are touched, so a
  # user's own choice is never overwritten. Every category comes from the
  # active list; Transfers is never assigned here (only TR1 does that).
  class Pipeline
    AI_MIN_CONFIDENCE = BigDecimal("0.6")
    AI_ROWS_PER_RUN = 100
    AI_BATCH_SIZE = 50
    # The AI answered (or declined) this batch: its rows count as attempted.
    ANSWERED_ERRORS = [AnthropicClient::Refused, AnthropicClient::BadOutput].freeze
    # The AI never answered: stop, and resume these rows next run.
    UNANSWERED_ERRORS = [AiBudget::Exceeded, AnthropicClient::Unavailable, AnthropicClient::NotConfigured].freeze

    Summary = Data.define(:memory, :rule, :ai, :needs_review, :sent_to_ai, :remaining, :transfer_like) do
      def to_h = { memory:, rule:, ai:, needs_review:, sent_to_ai:, remaining:, transfer_like: }
      def processed = memory + rule + sent_to_ai
    end

    def self.call(user:, scope:, ai: nil)
      new(user:, scope:, ai: ai || ai_for(user)).call
    end

    # The AI step for a user: Claude (AI2) when an API key is configured,
    # otherwise DisabledAi. Tests stub this; real clients are refused there.
    def self.ai_for(user)
      return DisabledAi.new if Rails.env.test? || ENV["ANTHROPIC_API_KEY"].blank?

      ClaudeCategorizer.new(user:)
    end

    def initialize(user:, scope:, ai:)
      @user = user
      @scope = scope
      @ai = ai
    end

    def call
      rows = @scope.merge(@user.transactions).where(category_id: nil, categorization_source: "none")
                   .order(:id).pluck(:id, :normalized_description, :amount, :ai_attempted_at)
      row_accounts = @user.transactions.where(id: rows.map(&:first)).pluck(:id, :account_id).to_h
      account_info = @user.accounts.pluck(:id, :purpose, :name).to_h { |id, purpose, name| [id, [purpose, name]] }
      purposes = row_accounts.transform_values { |account_id| account_info[account_id]&.first }
      return Summary.new(memory: 0, rule: 0, ai: 0, needs_review: 0, sent_to_ai: 0, remaining: 0, transfer_like: 0) if rows.empty?

      categories = Category.active_list.where.not(kind: %w[transfer legacy]).to_h { |c| [c.slug, c] }
      keys = rows.to_h { |id, normalized, _, _| [id, MerchantKey.for(normalized)] }

      # 1. Merchant memory
      memory = @user.merchant_rules.where(merchant_key: keys.values.uniq).includes(:category)
                    .select { |r| categories.key?(r.category&.slug) }.index_by(&:merchant_key)
      by_memory, rest = rows.partition { |id, _, _, _| memory.key?(keys[id]) }

      # Transfer check: own-account transfers go to review, never to Claude
      transfer_like, rest = rest.partition do |id, _, _, _|
        others = account_info.except(row_accounts[id]).values.map(&:last)
        TransferCheck.transfer_like?(keys[id], others)
      end

      # 2. Keyword rules
      by_rule = {}
      rest = rest.reject do |id, _, amount, _|
        slug = KeywordRules.match(keys[id], amount)
        by_rule[id] = slug if slug && categories.key?(slug)
      end

      # 3. AI, for what's left and not already answered
      for_ai = rest.select { |_, _, _, attempted| attempted.nil? }.first(AI_ROWS_PER_RUN)
      by_ai, attempted = ai_step(for_ai, keys, categories, purposes)
      unsure = rest.map(&:first) - by_ai.keys

      ActiveRecord::Base.transaction do
        assign(by_memory.group_by { |id, _, _, _| memory[keys[id]].category_id }.transform_values { |rs| rs.map(&:first) }, "memory")
        assign(by_rule.group_by { |_, slug| categories[slug].id }.transform_values { |ps| ps.map(&:first) }, "rule")
        now = Time.current
        by_ai.each do |id, (slug, confidence)|
          pending.where(id:).update_all(category_id: categories[slug].id, categorization_source: "ai",
                                        confidence:, needs_review: false, ai_attempted_at: now, updated_at: now)
        end
        pending.where(id: attempted - by_ai.keys).update_all(ai_attempted_at: now, updated_at: now)
        pending.where(id: unsure).update_all(needs_review: true, updated_at: now)
        # ai_attempted_at marks them as not for Claude, so they aren't "remaining".
        pending.where(id: transfer_like.map(&:first)).update_all(needs_review: true, ai_attempted_at: now, updated_at: now)
        touch_memory(memory, by_memory, keys)
      end

      remaining = @scope.merge(@user.transactions).where(categorization_source: "none", ai_attempted_at: nil)
                        .where.not(id: by_memory.map(&:first) + by_rule.keys).count
      Summary.new(memory: by_memory.size, rule: by_rule.size, ai: by_ai.size,
                  needs_review: unsure.size + transfer_like.size, sent_to_ai: attempted.size, remaining:,
                  transfer_like: transfer_like.size)
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

    # Returns [{ id => [slug, confidence] }, [ids the AI answered]].
    def ai_step(rows, keys, categories, purposes)
      placed = {}
      attempted = []
      rows.each_slice(AI_BATCH_SIZE) do |batch|
        items = batch.each_with_index.map do |(id, _, amount, _), index|
          { index:, merchant: keys[id], amount: amount.to_s("F"), account_purpose: purposes[id] }
        end
        answers =
          begin
            Array(@ai.categorize(items:, allowed_slugs: categories.keys))
          rescue *ANSWERED_ERRORS => e
            Rails.logger.info("[ai] categorize batch to review: #{e.class.name}")
            []
          rescue *UNANSWERED_ERRORS => e
            Rails.logger.info("[ai] categorize stopped, will resume: #{e.class.name}")
            break
          end
        attempted.concat(batch.map(&:first))
        answers.each do |answer|
          answer = answer.to_h.transform_keys(&:to_sym)
          row = batch[answer[:index]] if answer[:index].is_a?(Integer) && answer[:index] >= 0
          next if row.nil? || placed.key?(row.first)

          confidence = BigDecimal(answer[:confidence].to_s) rescue nil
          next unless categories.key?(answer[:category_slug].to_s) && confidence&.between?(AI_MIN_CONFIDENCE, 1)

          placed[row.first] = [answer[:category_slug].to_s, confidence]
        end
      end
      [placed, attempted]
    end

    def touch_memory(memory, by_memory, keys)
      by_memory.map { |id, _, _, _| keys[id] }.tally.each do |key, count|
        MerchantRule.where(id: memory[key].id).update_all(["hits = hits + ?, last_used_at = ?", count, Time.current])
      end
    end
  end
end
