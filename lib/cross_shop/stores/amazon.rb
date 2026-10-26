require "cross_shop/stores/base"

module CrossShop
  module Stores
    module Amazon
      def self.convert(response)
        Stores.convert_each("amazon", response.fetch("organic_results"), "asin") do |item|
          brand, brand_source = Stores.brand(field: item["brand"], title: item["title"])
          Product.new(
            store: "amazon",
            store_id: item["asin"],
            title: item["title"],
            link: item["link"],
            price_min: item["extracted_price"],
            price_max: item["extracted_price"],
            currency: Stores.currency(item["price"]),
            # Assumed new: SearchApi's Amazon results have no condition field,
            # and a search result shows the listing's main offer.
            condition: "new",
            brand:,
            brand_source:,
            image: item["thumbnail"],
            rating: item["rating"],
            reviews_count: item["reviews"],
            # Observed only as true (64 of 448 items); absent means organic.
            sponsored: item["is_sponsored"] == true
          )
        end
      end
    end
  end
end
