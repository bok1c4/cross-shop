require "cross_shop/stores/amazon"
require "cross_shop/stores/ebay"
require "cross_shop/stores/shein"
require "cross_shop/shein_page"

module CrossShop
  module Stores
    # SearchApi engine name => converter.
    BY_ENGINE = {
      "amazon_search" => Amazon,
      "ebay_search" => Ebay,
      "shein_search" => Shein
    }.freeze

    # Engines whose saved store page (html_url) we can read ourselves, for
    # when SearchApi's parser returns nothing: (html, response) => listings.
    PAGE_PARSERS = {
      "shein_search" => ->(html, response) {
        SheinPage.organic_results(html, domain: response.dig("search_parameters", "shein_domain") || "us.shein.com")
      }
    }.freeze
  end
end
