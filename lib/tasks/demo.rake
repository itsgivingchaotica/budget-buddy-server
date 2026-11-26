# DEMO-G (demo data generator).
#
#   bin/rails demo:generate[dir]   write the synthetic CSVs + golden.csv (default tmp/demo)
#   bin/rails demo:seed            import them for the demo user through the real pipeline
#   bin/rails demo:reset [USER_EMAIL=you@example.com]
#                                  delete the demo user's (or that user's) imported data (development only)
#   bin/rails demo:seed USER_EMAIL=you@example.com
#   bin/rails "demo:home_state[normal]" [USER_EMAIL=…]   no_plan | normal | over, for Home screenshots
#   bin/rails demo:sample_plan [USER_EMAIL=…]   a stand-in plan (budgets, bills, a goal) for checking Home/Plan
#                                  ...or into an existing (signed-in) user, so the app shows them
#
# SEED and END_ON (YYYY-MM-DD) change the data; the defaults are fixed, so
# the files are byte-identical every time. Development and test only.
namespace :demo do
  def demo_generator
    Demo::Generator.new(seed: Integer(ENV.fetch("SEED", Demo::Generator::DEFAULT_SEED)),
                        end_on: ENV["END_ON"] ? Date.iso8601(ENV["END_ON"]) : Demo::Generator::DEFAULT_END_ON)
  end

  def refuse_outside_dev!
    abort "demo tasks run only in development or test" unless Rails.env.development? || Rails.env.test?
  end

  desc "Write the synthetic demo CSVs and the golden set"
  task :generate, [:dir] => :environment do |_t, args|
    refuse_outside_dev!
    dir = demo_generator.write(args[:dir] || Rails.root.join("tmp/demo").to_s)
    puts "Wrote demo files to #{dir}"
  end

  desc "Delete the demo user's (or USER_EMAIL's) imported data (development only), so it can be reloaded"
  task reset: :environment do
    email = ENV["USER_EMAIL"].presence || Demo::Reset::DEMO_EMAIL
    counts = Demo::Reset.call(email:)
    puts "Deleted for #{email}: #{counts}"
  rescue Demo::Reset::Refused => e
    abort e.message
  end

  desc "Import the demo data for the demo user (or USER_EMAIL) through the real import pipeline"
  task seed: :environment do
    refuse_outside_dev!
    user =
      if ENV["USER_EMAIL"].present?
        User.find_by_email_ci(ENV["USER_EMAIL"]) || abort("No user with that email. Sign in once in the app first.")
      else
        User.find_or_create_by!(email: "demo.user@example.com") do |u|
          u.first_name = "Demo"
          u.last_name = "User"
        end
      end
    Demo::Seeder.call(user:, generator: demo_generator, log: ->(line) { puts line })
    puts "Demo data loaded for user ##{user.id}."
  end

  desc "Put the demo user (or USER_EMAIL) into a Home state for screenshots: no_plan, normal or over (development only)"
  task :home_state, [:state] => :environment do |_t, args|
    email = ENV["USER_EMAIL"].presence || Demo::Reset::DEMO_EMAIL
    puts "Home state for #{email == Demo::Reset::DEMO_EMAIL ? 'the demo user' : 'USER_EMAIL'}: #{Demo::HomeState.call(state: args[:state].to_s, email:)}"
  rescue Demo::HomeState::Refused => e
    abort e.message
  end

  desc "Add a stand-in plan (budgets, two bills, a goal) for the demo user or USER_EMAIL, to check Home and Plan (development only)"
  task sample_plan: :environment do
    refuse_outside_dev!
    email = ENV["USER_EMAIL"].presence || Demo::Reset::DEMO_EMAIL
    user = User.find_by_email_ci(email) || abort("No user with that email. Sign in once in the app (or run demo:seed) first.")
    puts "Added for user ##{user.id}: #{Demo::SamplePlan.call(user:)}"
  rescue Demo::SamplePlan::Refused => e
    abort e.message
  end
end
