# Money (BigDecimal) as two-decimal strings, all the way down a result;
# dates, counts, percents and flags unchanged. Shared by the analytics,
# goals and budget-context responses.
module AnalyticsJson
  private

  def analytics_json(value)
    case value
    when BigDecimal then money(value)
    when Hash then value.transform_values { |v| analytics_json(v) }
    when Array then value.map { |v| analytics_json(v) }
    else value
    end
  end
end
