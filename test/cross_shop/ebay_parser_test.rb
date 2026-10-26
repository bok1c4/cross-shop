require "test_helper"
require "cross_shop/ebay_parser"
require "cross_shop/stores/ebay"
require "cross_shop/searchapi_health"

# Runs against a real saved page: eBay's search for "adidas samba og",
# captured 2026-10-26 (fixtures/ebay_html). Expected values were read off
# the page by hand.
class EbayParserTest < Minitest::Test
  PAGE = File.expand_path("../../fixtures/ebay_html/adidas-samba-og.html", __dir__)
  LISTINGS = CrossShop::EbayParser.parse(File.read(PAGE, encoding: Encoding::UTF_8)).freeze

  def listing(id)
    LISTINGS.find { |item| item["item_id"] == id } || flunk("no listing #{id}")
  end

  # The page has 62 cards; two are "Shop on eBay" placeholders linking to /itm/123456.
  def test_one_listing_per_real_item
    assert_equal 60, LISTINGS.size
    assert_equal 60, LISTINGS.map { |item| item["item_id"] }.uniq.size
    assert LISTINGS.all? { |item| item["item_id"].match?(/\A\d{12}\z/) }
    assert_equal (1..60).to_a, LISTINGS.map { |item| item["position"] }
  end

  def test_plain_buy_it_now_listing
    item = listing("206415224883")

    assert_equal "Adidas Samba OG White Night Indigo Cream JH5633", item["title"]
    assert_equal "US M 11 + more · adidas · adidas Samba", item["subtitle"]
    assert_equal "Brand New", item["condition"]
    assert_equal ["$99.99", 99.99], [item["price"], item["extracted_price"]]
    assert_equal "Buy It Now", item["buying_format"]
    assert_equal "Shipping not specified", item["shipping"]
    refute item.key?("extracted_shipping")
    assert_equal "https://www.ebay.com/itm/206415224883", item["link"]
    assert_includes item["extensions"], "Located in United States"
  end

  # The case SearchApi gets wrong: an auction with a Buy It Now option has
  # extra rows, and position-based parsing puts "Buy It Now" in shipping.
  def test_auction_rows_are_read_by_meaning_not_position
    item = listing("860067068492")

    assert_equal 50.0, item["extracted_price"]
    assert_equal "0 bids · Time left 1d 4h", item["buying_format"]
    assert_equal "Shipping not specified", item["shipping"]
    assert_includes item["extensions"], "Buy It Now"
  end

  def test_price_range
    item = listing("860076023635")

    assert_equal "$83.00 to $128.00", item["price"]
    assert_equal({"from" => 83.0, "to" => 128.0}, item["extracted_price_range"])
    assert_equal true, item["is_price_range"]
    refute item.key?("extracted_price")
  end

  def test_discounted_price_keeps_the_original
    item = listing("158299410295")

    assert_equal [55.0, 110.0], [item["extracted_price"], item["extracted_original_price"]]
  end

  # Free delivery is 0.0 here; SearchApi leaves extracted_shipping out.
  def test_shipping_costs
    assert_equal ["+$4.99 delivery", 4.99], listing("366518449313").values_at("shipping", "extracted_shipping")
    assert_equal ["Free delivery", 0.0], listing("158299410295").values_at("shipping", "extracted_shipping")
  end

  def test_rating_reviews_and_items_sold
    assert_equal [4.5, 4], listing("366518449313").values_at("rating", "reviews")
    assert_equal ["123 sold", 123], listing("227116035586").values_at("items_sold", "extracted_items_sold")
  end

  # Every card in the raw HTML carries an obfuscated "Sponsored" label, so
  # sponsored status is unknown, and absent rather than guessed.
  def test_sponsored_is_never_guessed
    assert LISTINGS.none? { |item| item.key?("is_sponsored") }
  end

  # The point of matching SearchApi's shape: the same converter and health
  # rules apply to our output unchanged.
  def test_output_converts_cleanly
    conversion = CrossShop::Stores::Ebay.convert({"organic_results" => LISTINGS})

    assert_equal [60, 0], [conversion.products.size, conversion.rejects.size]
  end

  # Every shipping value we extract is about shipping (SearchApi: 88% on this
  # query). Shipping is filled on 49 of 60 only because 11 listings show no
  # shipping row at all to a visitor outside the US: the health check flagged
  # it, and the page confirmed it. Everything else passes.
  def test_health_rules_shipping_always_plausible_and_only_location_limits_fill
    reports = CrossShop::SearchApiHealth.check("ebay_search", {"organic_results" => LISTINGS}).to_h { |r| [r.field, r] }
    shipping = reports.fetch("shipping")

    assert reports.except("shipping").values.all?(&:passed)
    assert_equal [49, 49], [shipping.filled, shipping.valid]
  end
end
