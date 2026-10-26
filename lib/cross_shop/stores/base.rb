require "cross_shop/brands"
require "cross_shop/product"

module CrossShop
  # Converters from one store's SearchApi response to Products.
  module Stores
    Conversion = Data.define(:products, :rejects)
    Reject = Data.define(:store, :store_id, :reason)

    # "$" means USD here because every query uses US domains.
    CURRENCY_BY_SYMBOL = {"$" => "USD"}.freeze

    def self.currency(price_text)
      CURRENCY_BY_SYMBOL[price_text.to_s.strip[0]]
    end

    # The store's own brand field first, then a known brand in the text.
    # Returns [brand, source], or [nil, nil] when nothing is found.
    def self.brand(field: nil, title: nil, subtitle: nil)
      if field.is_a?(String) && !field.strip.empty?
        return [Brands.find(field) || field.strip.downcase, "field"]
      end

      {"title" => title, "subtitle" => subtitle}.each do |source, text|
        brand = Brands.find(text)
        return [brand, source] if brand
      end
      [nil, nil]
    end

    # One product per listing. A listing that fails validation becomes a
    # reject with the reason; nothing is dropped silently.
    def self.convert_each(store, items, id_field)
      products = []
      rejects = []
      items.each do |item|
        products << yield(item)
      rescue Product::Invalid => error
        rejects << Reject.new(store:, store_id: item[id_field], reason: error.message)
      end
      Conversion.new(products:, rejects:)
    end
  end
end
