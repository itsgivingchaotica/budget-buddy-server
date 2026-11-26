# EV1 (categorization eval). Manual only: it makes real Claude calls (within
# the daily AI cap) and is never run by CI on push.
#
#   bin/rails eval:categorization   # writes docs/evals/categorization-<date>.md
#
# Three runs in one report: the easy set (demo generator, full pipeline), the
# hard set (hand-written, full pipeline), and the hard set with the keyword
# rules switched off (Claude only).
namespace :eval do
  desc "Run the categorization eval (easy set, hard set, hard set Claude-only) and write docs/evals/categorization-<date>.md"
  task categorization: :environment do
    abort "eval:categorization runs only in development" unless Rails.env.development?
    abort "ANTHROPIC_API_KEY is not set" if ENV["ANTHROPIC_API_KEY"].blank?

    sets = Evals::GoldenSets
    runs = [
      Evals::CategorizationReport::Run.new(
        name: "Easy set (demo generator)", about: "300 rows from the demo generator; full pipeline.",
        result: Evals::Categorization.run(golden: sets.easy)
      ),
      Evals::CategorizationReport::Run.new(
        name: "Hard set", about: "Hand-written rows (`lib/evals/golden_hard.yml`); full pipeline.",
        result: Evals::Categorization.run(golden: sets.hard)
      ),
      Evals::CategorizationReport::Run.new(
        name: "Hard set, Claude only", about: "The same hand-written rows with the keyword rules switched off.",
        result: Evals::Categorization.run(golden: sets.hard, keyword_rules: false)
      )
    ]
    report = Evals::CategorizationReport.markdown(runs, meta: sets.hard_meta, fingerprint: sets.rules_fingerprint)
    dir = Rails.root.join("docs/evals")
    FileUtils.mkdir_p(dir)
    path = dir.join("categorization-#{runs.first.result.ran_at.to_date.iso8601}.md")
    File.write(path, report)
    puts "Wrote #{path.relative_path_from(Rails.root)}"
    runs.each do |run|
      m = Evals::CategorizationReport.metrics(run.result)
      puts "#{run.name}: auto-categorized accuracy #{Evals::CategorizationReport.pct(m[:auto_correct], m[:auto])}, " \
           "review rate #{Evals::CategorizationReport.pct(m[:review], m[:total])}, transfer critical errors #{m[:transfer_critical]}"
    end
  end
end
