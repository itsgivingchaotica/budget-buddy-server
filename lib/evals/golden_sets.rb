require "digest"
require "yaml"

module Evals
  # EV1 (categorization eval): the golden sets, as one row shape.
  #
  #   easy - Demo::Generator#golden: 300 rows labelled by the generator when
  #          it made them (the demo merchants; the keyword rules know most).
  #   hard - lib/evals/golden_hard.yml: hand-written rows, labelled when
  #          written, that the rules weren't written for.
  #
  # Labels always come from the set itself, never from the pipeline.
  module GoldenSets
    Row = Data.define(:purpose, :date, :cents, :description, :label, :kind)
    HARD_PATH = File.expand_path("golden_hard.yml", __dir__)

    module_function

    def easy(generator = Demo::Generator.new)
      generator.golden.map do |g|
        Row.new(purpose: Demo::Generator::ACCOUNTS[g.account][:purpose], date: g.date, cents: g.cents,
                description: g.description, label: g.slug, kind: "easy")
      end
    end

    def hard_meta = YAML.load_file(HARD_PATH, permitted_classes: [Date]).fetch("meta")

    def hard
      data = YAML.load_file(HARD_PATH, permitted_classes: [Date])
      first = Date.iso8601(data.dig("meta", "first_date").to_s)
      data.fetch("rows").each_with_index.map do |r, i|
        Row.new(purpose: r.fetch("purpose"), date: first + i, cents: (BigDecimal(r.fetch("amount")) * 100).to_i,
                description: r.fetch("description"), label: r.fetch("label"), kind: r.fetch("kind"))
      end
    end

    # A fingerprint of the keyword rules, so a report can say if they changed
    # after the hard set was written (the rules are frozen for EV1).
    def rules_fingerprint
      text = ::Categorization::KeywordRules::RULES.map { |r| [r.slug, r.pattern.source, r.sign].join("\t") }.join("\n")
      Digest::SHA256.hexdigest(text)[0, 16]
    end

    def rules_frozen? = rules_fingerprint == hard_meta.fetch("rules_fingerprint")
  end
end
