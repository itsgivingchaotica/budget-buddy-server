module Categorization
  # AI1 (rules-based categorization): a fixed list of merchant patterns ->
  # category slugs, tried after merchant memory and before any AI. The first
  # match wins, so specific patterns come before general ones (UBER EATS
  # before UBER).
  #
  # Sign: most rules match either way (a refund from a grocer is still
  # Groceries, and nets against spending). Income rules only match money in;
  # debt-payment rules only money out (a payment received on a credit-card
  # account is not spending). Rules never assign Transfers: only confirming a
  # transfer pair does (TR1).
  module KeywordRules
    Rule = Data.define(:slug, :pattern, :sign)

    def self.rule(slug, words, sign: :any)
      Rule.new(slug:, pattern: /(?:\A|[^A-Z0-9])(?:#{words})(?:[^A-Z0-9]|\z)/, sign:)
    end

    RULES = [
      # Money in
      rule("income", "PAYROLL|DIRECT DEP(?:OSIT)?|DIR DEP|SALARY|PAYCHECK|ADP PAYROLL|GUSTO|INTEREST PAID|INTEREST EARNED", sign: :in),
      # Debt (money out only; PO-9: card payments from checking are Debt Payments unless confirmed as a transfer)
      rule("debt-payments", "CREDIT CARD PAYMENT|CARD PAYMENT|CARD AUTOPAY|AUTOPAY PAYMENT|LOAN PAYMENT|STUDENT LOAN|NAVIENT|NELNET|SALLIE MAE", sign: :out),
      # Specific before general
      rule("dining-out", "UBER EATS|UBEREATS|DOORDASH|GRUBHUB|POSTMATES"),
      rule("subscriptions", "NETFLIX|SPOTIFY|HULU|DISNEY PLUS|DISNEYPLUS|HBO MAX|MAX\\.COM|YOUTUBE PREMIUM|APPLE\\.COM/BILL|AMAZON PRIME|PRIME VIDEO|AUDIBLE|PATREON|ICLOUD"),
      rule("groceries", "WHOLE FOODS|WHOLEFDS|TRADER JOE'?S?|SAFEWAY|KROGER|ALDI|PUBLIX|WEGMANS|SPROUTS|H-E-B|HEB|FOOD LION|GIANT EAGLE|GROCERY|GROCER|SUPERMARKET"),
      rule("dining-out", "STARBUCKS|DUNKIN|MCDONALD'?S?|CHIPOTLE|CHICK-FIL-A|TACO BELL|WENDY'?S|BURGER KING|SUBWAY|PANERA|DOMINO'?S|PIZZA|RESTAURANT|CAFE|COFFEE|BAKERY|DINER"),
      rule("transportation", "UBER|LYFT|SHELL|CHEVRON|EXXON|EXXONMOBIL|MOBIL|ARCO|SUNOCO|VALERO|CITGO|MARATHON PETRO|GAS STATION|FUEL|PARKING|PARKMOBILE|TOLL|E-?ZPASS|TRANSIT|METRO CARD|MTA|BART|CLIPPER"),
      rule("utilities", "COMCAST|XFINITY|VERIZON|AT&T|ATT|T-MOBILE|TMOBILE|SPECTRUM|PG&E|CON ED|CONEDISON|DUKE ENERGY|ELECTRIC|WATER UTIL|GAS CO|INTERNET|UTILITY|UTILITIES"),
      rule("rent", "RENT|RENT PAYMENT|PROPERTY MGMT|PROPERTY MANAGEMENT|APARTMENTS|LANDLORD"),
      rule("insurance", "GEICO|STATE FARM|PROGRESSIVE|ALLSTATE|LIBERTY MUTUAL|LEMONADE|INSURANCE|INS PREM"),
      rule("healthcare", "CVS|WALGREENS|RITE AID|PHARMACY|DENTAL|DENTIST|CLINIC|HOSPITAL|MEDICAL|URGENT CARE|OPTOMETR|LABCORP|QUEST DIAG"),
      rule("personal-care", "SALON|BARBER|SEPHORA|ULTA|NAIL|SPA|GYM|PLANET FITNESS|EQUINOX"),
      rule("clothing", "ZARA|UNIQLO|H&M|OLD NAVY|GAP|NORDSTROM|MACY'?S|TJ ?MAXX|MARSHALLS|NIKE|ADIDAS"),
      rule("home-improvement", "HOME DEPOT|LOWE'?S|IKEA|ACE HARDWARE|MENARDS|HARDWARE"),
      rule("travel", "AIRLINES?|DELTA AIR|UNITED AIR|AMERICAN AIR|SOUTHWEST AIR|JETBLUE|ALASKA AIR|MARRIOTT|HILTON|HYATT|AIRBNB|EXPEDIA|BOOKING\\.COM|HOTEL|AMTRAK"),
      rule("entertainment", "AMC THEATRES?|REGAL CINEMAS?|CINEMA|TICKETMASTER|STUBHUB|STEAM ?GAMES|PLAYSTATION|XBOX|NINTENDO|BOWLING"),
      rule("education", "TUITION|UNIVERSITY|COLLEGE|COURSERA|UDEMY|SCHOOL|TEXTBOOK"),
      rule("gifts", "GIFT SHOP|FLORIST|1-800-FLOWERS|GIFT CARD")
    ].freeze

    # Returns a category slug or nil.
    def self.match(merchant_key, amount)
      direction = amount.to_d.negative? ? :out : :in
      RULES.find { |r| (r.sign == :any || r.sign == direction) && r.pattern.match?(merchant_key) }&.slug
    end
  end
end
