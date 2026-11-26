# M2: "today" and "this month" for a user, in their own time zone
# (financial_profiles.time_zone, PO-12); UTC until it's set. Budgets (DM-3),
# bills (OB1) and the Home outlook (W1) all use it, so they agree on dates.
module UserClock
  module_function

  def zone(user)
    name = user.financial_profile&.time_zone
    (name.present? && ActiveSupport::TimeZone[name]) || ActiveSupport::TimeZone["UTC"]
  end

  def today(user, now: Time.current) = now.in_time_zone(zone(user)).to_date

  def month_start(user, now: Time.current) = today(user, now:).beginning_of_month
end
