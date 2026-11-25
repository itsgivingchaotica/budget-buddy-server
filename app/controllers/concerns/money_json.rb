# Money goes out as a string with exactly two decimals ("-12.50"), never a
# float, so clients don't lose cents.
module MoneyJson
  private

  def money(value)
    return nil if value.nil?

    format("%.2f", value.to_d.round(2))
  end
end
