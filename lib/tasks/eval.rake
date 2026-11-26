# EV1 (categorization eval). Manual only: it makes real Claude calls (within
# the daily AI cap) and is never run by CI on push.
#
#   bin/rails eval:categorization     # writes docs/evals/categorization-<date>.md
namespace :eval do
  desc "Run the categorization eval on the golden set and write docs/evals/categorization-<date>.md"
  task categorization: :environment do
    abort "eval:categorization runs only in development" unless Rails.env.development?
    abort "ANTHROPIC_API_KEY is not set" if ENV["ANTHROPIC_API_KEY"].blank?

    result = Evals::Categorization.run
    report = Evals::CategorizationReport.markdown(result)
    dir = Rails.root.join("docs/evals")
    FileUtils.mkdir_p(dir)
    path = dir.join("categorization-#{result.ran_at.to_date.iso8601}.md")
    File.write(path, report)
    m = Evals::CategorizationReport.metrics(result)
    puts "Wrote #{path.relative_path_from(Rails.root)}"
    puts "auto-categorized accuracy: #{Evals::CategorizationReport.pct(m[:auto_correct], m[:auto])}; " \
         "review rate: #{Evals::CategorizationReport.pct(m[:review], m[:total])}; transfer critical errors: #{m[:transfer_critical]}"
  end
end
