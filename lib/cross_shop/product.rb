module CrossShop
  # One listing from any store, in one shape. Building it raises
  # Product::Invalid on anything a later step could not trust; the store
  # converters turn that into a reject with a reason.
  class Product < Data.define(
    :store, :store_id, :title, :link, :price_min, :price_max, :currency, :condition,
    :brand, :brand_source, :image, :rating, :reviews_count, :sponsored
  )
    # A subclass, so converters can rescue bad data without also swallowing
    # programming errors such as a misspelled keyword (plain ArgumentError).
    class Invalid < ArgumentError; end

    STORES = %w[amazon ebay shein].freeze
    CURRENCIES = %w[USD].freeze
    CONDITIONS = %w[new new_other used].freeze
    BRAND_SOURCES = %w[field title subtitle].freeze

    def initialize(store:, store_id:, title:, link:, price_min:, price_max:, currency:, condition:,
      brand: nil, brand_source: nil, image: nil, rating: nil, reviews_count: nil, sponsored: nil)
      check STORES.include?(store), "unknown store #{store.inspect}"
      check present?(store_id), "missing store_id"
      check present?(title), "missing title"
      check link.is_a?(String) && link.start_with?("https://"), "link must be an https URL, got #{link.inspect}"
      check positive?(price_min) && positive?(price_max), "price must be positive, got #{price_min.inspect}..#{price_max.inspect}"
      check price_min <= price_max, "price range is upside down: #{price_min}..#{price_max}"
      check CURRENCIES.include?(currency), "unsupported currency #{currency.inspect}"
      check CONDITIONS.include?(condition), "unmapped condition #{condition.inspect}"
      check brand.nil? == brand_source.nil?, "brand and brand_source go together, got #{brand.inspect}/#{brand_source.inspect}"
      check brand_source.nil? || BRAND_SOURCES.include?(brand_source), "unknown brand_source #{brand_source.inspect}"
      check [true, false, nil].include?(sponsored), "sponsored must be true, false or nil, got #{sponsored.inspect}"
      check rating.nil? || (rating.is_a?(Numeric) && rating.between?(0, 5)), "rating out of range: #{rating.inspect}"
      check reviews_count.nil? || (reviews_count.is_a?(Integer) && reviews_count >= 0), "bad reviews_count: #{reviews_count.inspect}"

      super(
        store:, store_id:, title:, link:, price_min: price_min.to_f, price_max: price_max.to_f, currency:, condition:,
        brand:, brand_source:, image:, rating:, reviews_count:, sponsored:
      )
    end

    private

    def check(ok, message)
      raise Invalid, message unless ok
    end

    def present?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def positive?(value)
      value.is_a?(Numeric) && value.positive?
    end
  end
end
