require "test_helper"
require "tmpdir"
require "json"
require "cross_shop/catalog"

class CatalogTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @cache = CrossShop::SearchApi::ResponseCache.new(@dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_products_from_every_cached_store_and_the_engines_still_missing
    @cache.write("amazon_search", {q: "samba"}, JSON.generate(organic_results: [
      {asin: "A1", title: "Samba OG JH5633", price: "$100.00", extracted_price: 100.0, link: "https://www.amazon.com/dp/A1"}
    ]))
    @cache.write("ebay_search", {q: "samba"}, JSON.generate(organic_results: [
      {item_id: "E1", title: "Adidas Samba JH5633", condition: "Pre-Owned", price: "$60.00", extracted_price: 60.0, link: "https://www.ebay.com/itm/E1"}
    ]))

    result = CrossShop::Catalog.new(cache: @cache).search("samba")

    assert_equal %w[amazon ebay], result.products.map(&:store).sort
    assert_empty result.rejects
    assert_empty result.missing_engines
  end

  # Missing data is reported, never treated as "no results".
  def test_an_uncached_engine_is_reported_as_missing
    result = CrossShop::Catalog.new(cache: @cache).search("never fetched")

    assert_empty result.products
    assert_equal CrossShop::Stores::BY_ENGINE.keys, result.missing_engines
  end
end
