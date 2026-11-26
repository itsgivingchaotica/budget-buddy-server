# A one-line description of an exception that's safe to log: the class, the
# database constraint when there is one, and where it was raised. Never the
# message, which can carry data (PostgreSQL's "DETAIL: Failing row contains
# (…)" holds the whole row; parse errors quote the request body).
module SafeError
  module_function

  def describe(error)
    parts = [error.class.name]
    cause = error.cause
    parts << "(#{cause.class.name})" if cause && cause.class != error.class
    constraint = constraint_name(error)
    parts << "constraint=#{constraint}" if constraint
    location = app_frame(error)
    parts << "at #{location}" if location
    parts.join(" ")
  end

  # The constraint name only (letters, digits, underscores), from the
  # first line of a database error.
  def constraint_name(error)
    return nil unless error.is_a?(ActiveRecord::StatementInvalid)

    error.message.to_s.lines.first.to_s[/constraint "([a-z0-9_]+)"/, 1]
  end

  def app_frame(error)
    root = Rails.root.to_s + "/"
    frame = Array(error.backtrace).find { |line| line.start_with?(root + "app/", root + "lib/") }
    frame&.delete_prefix(root)&.sub(/:in .*/, "")
  end
end
