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

    result = CrossShop::Catalog.new(cache: @cache, engines: %w[amazon_search ebay_search]).search("samba")

    assert_equal %w[amazon ebay], result.products.map(&:store).sort
    assert_empty result.rejects
    assert_empty result.missing_engines
  end

  # Missing data is reported, never treated as "no results".
  def test_an_uncached_engine_is_reported_as_missing
    result = CrossShop::Catalog.new(cache: @cache, engines: %w[amazon_search]).search("never fetched")

    assert_empty result.products
    assert_equal({"amazon_search" => "not cached"}, result.missing_engines)
  end

  # Found by the web test: Shein has no converter, so it silently vanished
  # from the page instead of showing as missing.
  def test_a_cached_engine_without_a_converter_is_reported_too
    @cache.write("shein_search", {q: "samba"}, JSON.generate(organic_results: []))

    result = CrossShop::Catalog.new(cache: @cache, engines: %w[shein_search]).search("samba")

    assert_equal({"shein_search" => "no converter yet"}, result.missing_engines)
  end

  # SearchApi can answer 200 with an "error" field ("Shein didn't return any
  # results."). That message is the reason, not "no converter yet".
  def test_searchapis_own_message_is_the_reason_when_it_sent_one
    @cache.write("shein_search", {q: "samba"}, JSON.generate(error: "Shein didn't return any results."))

    result = CrossShop::Catalog.new(cache: @cache, engines: %w[shein_search]).search("samba")

    assert_equal({"shein_search" => "SearchApi: Shein didn't return any results."}, result.missing_engines)
  end

  def test_by_default_every_engine_in_the_query_set_is_checked
    result = CrossShop::Catalog.new(cache: @cache).search("never fetched")

    assert_equal CrossShop::QuerySet.load.engines, result.missing_engines.keys
  end
end
