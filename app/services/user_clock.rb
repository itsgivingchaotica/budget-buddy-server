# M2: "today", "this week" and "this month" for a user, in their own time
# zone (financial_profiles.time_zone, PO-12; UTC until it's set) and with
# their own first day of the week (week_starts_on, default Monday). Budgets
# (DM-3), bills (OB1), goal maths (G2) and the Home outlook (W1) all use it,
# so they agree on dates.
module UserClock
  module_function

  def zone(user)
    name = user.financial_profile&.time_zone
    (name.present? && ActiveSupport::TimeZone[name]) || ActiveSupport::TimeZone["UTC"]
  end

  def today(user, now: Time.current) = now.in_time_zone(zone(user)).to_date

  def month_start(user, now: Time.current) = today(user, now:).beginning_of_month

  # Date#wday of the user's first day of the week (0 = Sunday … 6 = Saturday).
  def week_starts_on(user) = user.financial_profile&.week_starts_on || FinancialProfile::MONDAY

  # The first day of the user's week containing `date`.
  def week_start_of(user, date) = date - ((date.wday - week_starts_on(user)) % 7)

  def week_start(user, now: Time.current) = week_start_of(user, today(user, now:))

  # A Time (e.g. created_at) as a date in the user's zone.
  def date_of(user, time) = time.in_time_zone(zone(user)).to_date
end
