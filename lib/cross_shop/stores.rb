require "cross_shop/stores/amazon"
require "cross_shop/stores/ebay"

module CrossShop
  module Stores
    # SearchApi engine name => converter. Shein joins once its responses exist.
    BY_ENGINE = {
      "amazon_search" => Amazon,
      "ebay_search" => Ebay
    }.freeze
  end
end
