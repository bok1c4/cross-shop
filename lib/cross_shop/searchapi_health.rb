require "cross_shop/field_health"
require "cross_shop/stores/ebay"

module CrossShop
  # Field-health rules for raw SearchApi responses: the checks a customer
  # could run on every response to notice silent breakage. Thresholds are a
  # starting judgement from one day of data, not tuned values.
  module SearchApiHealth
    Rule = FieldHealth::Rule
    SHIPPING_TEXT = /delivery|shipping|postage/i

    RULES = {
      "ebay_search" => [
        Rule.new(field: "title", min_filled: 1.0),
        Rule.new(field: "link", min_filled: 1.0, valid: ->(link) { link.start_with?("https://www.ebay.com/itm/") }),
        Rule.new(field: "price", min_filled: 0.95, read: ->(item) { item["extracted_price"] || item["extracted_price_range"] }),
        Rule.new(field: "condition", min_filled: 0.95, valid: ->(condition) { Stores::Ebay::CONDITIONS.key?(condition) }, min_valid: 0.95),
        Rule.new(field: "shipping", min_filled: 0.9, valid: ->(text) { text.match?(SHIPPING_TEXT) }, min_valid: 0.95)
      ],
      "amazon_search" => [
        Rule.new(field: "asin", min_filled: 1.0, valid: ->(asin) { asin.match?(/\A[A-Z0-9]{10}\z/) }),
        Rule.new(field: "title", min_filled: 1.0),
        Rule.new(field: "extracted_price", min_filled: 0.9),
        Rule.new(field: "brand", min_filled: 0.7),
        Rule.new(field: "rating", min_filled: 0.7, valid: ->(rating) { rating.between?(0, 5) })
      ]
    }.freeze

    def self.check(engine, response)
      FieldHealth.check(response.fetch("organic_results", []), RULES.fetch(engine))
    end
  end
end
