module Categorization
  # C2b (review and transfer screens), handoff #05 §B.2, with AI3 (learning
  # from corrections): a user's category pick on one row.
  #
  # apply: in one database transaction, sets the row's category (source
  # "user"), saves merchant memory, gives the same category to the user's
  # other rows from that merchant still waiting for review (source
  # "memory"), and records a CategoryCorrection with the previous state of
  # every changed row and of the merchant rule.
  #
  # undo: in one database transaction, restores each changed row whose
  # category is still the corrected one (rows changed since are left alone),
  # restores the merchant rule (or deletes it if the correction created it),
  # and marks the correction undone. A second undo raises AlreadyUndone.
  module Correction
    class AlreadyUndone < StandardError; end

    ROW_FIELDS = %w[category_id categorization_source confidence needs_review suggested_category_id].freeze

    module_function

    # Returns [correction, also_updated_count].
    def apply(user:, transaction:, category:)
      key = MerchantKey.for(transaction.normalized_description)
      ActiveRecord::Base.transaction do
        rule_before = user.merchant_rules.find_by(merchant_key: key)&.then do |r|
          { "category_id" => r.category_id, "hits" => r.hits, "last_used_at" => r.last_used_at&.iso8601(6) }
        end
        waiting = waiting_rows(user, transaction, key)
        previous = ([transaction] + waiting).map { |t| snapshot(t) }

        transaction.update!(category:, categorization_source: "user", confidence: nil, needs_review: false)
        remember!(user, key, category)
        also_updated =
          if waiting.empty?
            0
          else
            Transaction.where(id: waiting.map(&:id)).update_all(
              category_id: category.id, categorization_source: "memory", confidence: nil, needs_review: false,
              suggested_category_id: nil, updated_at: Time.current
            )
          end

        correction = user.category_corrections.create!(
          picked_transaction: transaction, new_category: category, merchant_key: key,
          previous:, merchant_rule_before: rule_before
        )
        [correction, also_updated]
      end
    end

    # Returns the ids of the rows put back.
    def undo(correction)
      user = correction.user
      correction.with_lock do
        raise AlreadyUndone if correction.undone?

        restored = correction.previous.filter_map do |before|
          row = user.transactions.find_by(id: before["id"])
          next if row.nil? || row.category_id != correction.new_category_id

          row.update!(before.slice(*ROW_FIELDS))
          row.id
        end
        restore_rule!(user, correction)
        correction.update!(undone_at: Time.current)
        restored
      end
    end

    # AI3: other rows from this merchant still waiting for review, not
    # chosen by the user, in active accounts and not in a transfer pair.
    def waiting_rows(user, transaction, key)
      in_pairs = TransferLink.where(user:).active.pluck(:outflow_transaction_id, :inflow_transaction_id).flatten
      user.transactions.joins(:account).merge(Account.active)
          .where(needs_review: true).where.not(categorization_source: "user")
          .where.not(id: [transaction.id, *in_pairs])
          .select { |t| MerchantKey.for(t.normalized_description) == key }
    end

    def snapshot(t)
      { "id" => t.id }.merge(ROW_FIELDS.to_h { |f| [f, f == "confidence" ? t.confidence&.to_s : t.public_send(f)] })
    end

    # One atomic INSERT ... ON CONFLICT; hits restart when the category changes.
    def remember!(user, key, category)
      now = Time.current
      MerchantRule.upsert(
        { user_id: user.id, merchant_key: key, category_id: category.id, hits: 0, created_at: now, updated_at: now },
        unique_by: %i[user_id merchant_key],
        on_duplicate: Arel.sql(<<~SQL.squish)
          hits = CASE WHEN merchant_rules.category_id = EXCLUDED.category_id THEN merchant_rules.hits ELSE 0 END,
          category_id = EXCLUDED.category_id, updated_at = EXCLUDED.updated_at
        SQL
      )
    end

    def restore_rule!(user, correction)
      rule = user.merchant_rules.find_by(merchant_key: correction.merchant_key)
      before = correction.merchant_rule_before
      if before.nil?
        # The correction created the rule: forget the merchant (unless the
        # user has taught it something else since).
        rule.destroy! if rule && rule.category_id == correction.new_category_id
      elsif rule
        rule.update!(category_id: before["category_id"], hits: before["hits"], last_used_at: before["last_used_at"])
      else
        user.merchant_rules.create!(merchant_key: correction.merchant_key, category_id: before["category_id"],
                                    hits: before["hits"], last_used_at: before["last_used_at"])
      end
    end
  end
end
