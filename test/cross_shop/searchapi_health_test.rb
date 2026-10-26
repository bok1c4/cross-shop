require "test_helper"
require "json"
require "cross_shop/search_api"
require "cross_shop/searchapi_health"

# Simulated breakages applied to a real saved eBay response.
class SearchApiHealthTest < Minitest::Test
  def response
    raw = CrossShop::SearchApi.cache.read("ebay_search", q: "adidas samba og")
    skip "no cached ebay response" if raw.nil?
    JSON.parse(raw)
  end

  def price_report(response)
    CrossShop::SearchApiHealth.check("ebay_search", response).find { |report| report.field == "price" }
  end

  def test_prices_pass_on_the_real_response
    assert price_report(response).passed
  end

  # Like the Walmart fix in SearchApi's changelog: prices came back empty
  # after a site change.
  def test_prices_emptied_on_a_third_of_listings_are_caught
    broken = response
    broken["organic_results"].each_with_index do |item, index|
      item.delete("extracted_price") if (index % 3).zero?
    end

    report = price_report(broken)

    refute report.passed
    assert_match(/filled/, report.problem)
  end
end
