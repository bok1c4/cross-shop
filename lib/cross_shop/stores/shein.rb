require "cross_shop/stores/base"

module CrossShop
  module Stores
    # SearchApi's shein_search organic_results, or the same shape read by
    # SheinPage from a page SearchApi saved.
    module Shein
      def self.convert(response)
        Stores.convert_each("shein", response.fetch("organic_results"), "product_id") do |item|
          brand, brand_source = Stores.brand(field: item["brand"], title: item["title"])
          # SearchApi sends a USD price beside the local one; use it whatever the domain.
          usd = item["extracted_price_usd"]
          price = usd || item["extracted_price"]
          Product.new(
            store: "shein",
            store_id: item["product_id"],
            title: item["title"],
            link: item["link"],
            price_min: price,
            price_max: price,
            currency: usd ? "USD" : Stores.currency(item["price"]),
            # Shein lists new items only.
            condition: "new",
            brand:,
            brand_source:,
            image: item["thumbnail"],
            rating: item["rating"],
            reviews_count: item["reviews"],
            # Neither SearchApi's docs nor the page data mark sponsored listings.
            sponsored: nil
          )
        end
      end
    end
  end
end
