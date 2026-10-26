require "test_helper"
require "cross_shop/shein_page"

# Runs on Shein pages SearchApi fetched and saved (html_url) for searches it
# answered with "Shein didn't return any results." Expected values were read
# off the pages by hand.
class SheinPageTest < Minitest::Test
  PAGES = File.expand_path("../../fixtures/searchapi/pages/shein_search", __dir__)
  SAMBA = File.read(File.join(PAGES, "search_d97LXP4moruBaXn9Mk03EOrl.html"), encoding: Encoding::UTF_8).freeze
  NIKE = File.read(File.join(PAGES, "search_8A9g6Ov07XHo3jKz34JlbW2m.html"), encoding: Encoding::UTF_8).freeze

  def test_the_products_searchapi_missed_are_on_the_page
    samba = CrossShop::SheinPage.organic_results(SAMBA)
    nike = CrossShop::SheinPage.organic_results(NIKE)

    assert_equal [20, 20], [samba.size, nike.size]
    assert_equal 19, samba.count { |item| item["title"].match?(/samba/i) }
    assert_equal (1..20).to_a, samba.map { |item| item["position"] }
  end

  # In the shape of SearchApi's shein_search organic_results.
  def test_a_listing_in_searchapis_shape
    item = CrossShop::SheinPage.organic_results(SAMBA).first

    assert_equal "563285400", item["product_id"]
    assert_equal "st251128877478188773", item["sku"]
    assert_match(/\AAdidas Originals Samba Brown Desert/, item["title"])
    assert_equal "https://us.shein.com/Adidas-Originals-Samba-Brown-Desert-Warm-Vanilla-Casual-Sneakers-Women-s-KJ7447-Retro-Heritage-Style-Timeless-Silhouette-p-563285400.html", item["link"]
    assert_equal "Adidas", item["brand"]
    assert_equal ["$90.48", 90.48, 90.48], item.values_at("price", "extracted_price", "extracted_price_usd")
    assert_equal ["$200.00", 200.0], item.values_at("original_price", "extracted_original_price")
    assert_equal [4.89, 768], item.values_at("rating", "reviews")
    assert item["thumbnail"].start_with?("https://img.ltwebstatic.com/")
  end

  # Shein shows "0" for products nobody has rated: no rating, not zero stars.
  def test_an_unrated_product_has_no_rating
    unrated = CrossShop::SheinPage.organic_results(SAMBA).find { |item| item["reviews"].to_i.zero? }

    refute_nil unrated
    refute unrated.key?("rating")
  end

  def test_the_domain_comes_from_the_request
    item = CrossShop::SheinPage.organic_results(SAMBA, domain: "www.shein.com").first

    assert item["link"].start_with?("https://www.shein.com/")
  end

  # Brackets and quotes inside strings must not end the array early.
  def test_brackets_inside_strings_do_not_confuse_the_scanner
    html = %(<script>x = {"products":[{"goods_id":"1","goods_name":"Tee [new] \\"OG\\" {x}","goods_url_name":"Tee",) +
      %("salePrice":{"usdAmount":"9.99","usdAmountWithSymbol":"$9.99"}}]};</script>)

    assert_equal ["Tee [new] \"OG\" {x}"], CrossShop::SheinPage.organic_results(html).map { |item| item["title"] }
  end

  def test_a_page_without_products_gives_none
    assert_empty CrossShop::SheinPage.organic_results("<html>Access denied</html>")
  end

  # Indexing a UTF-8 string by character is slow (Ruby scans from the start
  # each time); the first exploratory scan took minutes. Bytes keep it fast.
  def test_a_two_megabyte_page_parses_quickly
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    CrossShop::SheinPage.organic_results(SAMBA)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2.0
  end
end
