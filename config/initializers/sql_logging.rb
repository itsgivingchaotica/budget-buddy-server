# No financial text in logs (M2 ground rule). Active Record's SQL log hides
# bound values whose column matches filter_parameters, but not values
# written into the SQL text itself: bulk inserts (CSV imports, insert_all),
# update_all, and hand-written conditions such as "lower(email) = '…'".
# So SQL statements aren't logged at all unless LOG_SQL=1 is set outside
# production (for debugging against synthetic data only).
unless ENV["LOG_SQL"] == "1" && !Rails.env.production?
  ActiveSupport.on_load(:active_record) { ActiveRecord::LogSubscriber.detach_from(:active_record) }
end
