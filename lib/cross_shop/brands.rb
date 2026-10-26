module CrossShop
  # The brands this experiment knows: the ones in config/queries.yml. A real
  # aggregator needs a large brand dictionary; this one is small on purpose,
  # and its limits show up in the match results.
  module Brands
    PATTERNS = {
      "adidas" => /\badidas\b/i,
      "nike" => /\bnike\b/i,
      "new balance" => /\bnew balance\b/i,
      "converse" => /\bconverse\b/i,
      "patagonia" => /\bpatagonia\b/i,
      "levi's" => /\blevi['’]?s\b/i
    }.freeze

    # The first known brand mentioned in the text, or nil.
    def self.find(text)
      return nil if text.nil?

      PATTERNS.find { |_brand, pattern| pattern.match?(text) }&.first
    end
  end
end
