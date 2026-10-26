require "cross_shop/stores/base"

module CrossShop
  module Stores
    module Ebay
      CONDITIONS = {"Brand New" => "new", "New (Other)" => "new_other", "Pre-Owned" => "used"}.freeze

      def self.convert(response)
        Stores.convert_each("ebay", response.fetch("organic_results"), "item_id") do |item|
          range = item["extracted_price_range"]
          price_min, price_max = range ? [range["from"], range["to"]] : [item["extracted_price"], item["extracted_price"]]
          condition = CONDITIONS.fetch(item["condition"]) do
            raise Product::Invalid, "unmapped eBay condition #{item["condition"].inspect}"
          end
          # eBay results have no brand field; the subtitle often names it.
          brand, brand_source = Stores.brand(title: item["title"], subtitle: item["subtitle"])

          Product.new(
            store: "ebay",
            store_id: item["item_id"],
            title: item["title"],
            link: item["link"],
            price_min:,
            price_max:,
            currency: Stores.currency(item["price"]),
            condition:,
            brand:,
            brand_source:,
            image: item["thumbnail"],
            rating: item["rating"],
            reviews_count: item["reviews"],
            # SearchApi's eBay results never include is_sponsored (0 of 480 items).
            sponsored: nil
          )
        end
      end
    end
  end
end
