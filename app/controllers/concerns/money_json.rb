# Money goes out as a string with exactly two decimals ("-12.50"), never a
# float, so clients don't lose cents.
module MoneyJson
  private

  def money(value)
    return nil if value.nil?

    rounded = value.to_d.round(2)
    rounded = BigDecimal("0") if rounded.zero? # never "-0.00" (negated zeros, tiny negatives)
    format("%.2f", rounded)
  end
end
