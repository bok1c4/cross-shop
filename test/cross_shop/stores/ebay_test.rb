require "test_helper"
require "cross_shop/stores/ebay"

# Items copied from cached ebay_search responses (2026-10-26), trimmed of
# fields the converter does not read.
class EbayStoreTest < Minitest::Test
  PLAIN = {
    "position" => 2, "item_id" => "206415224883", "title" => "Adidas Samba OG White Night Indigo Cream JH5633",
    "subtitle" => "US M 11 + more · adidas · adidas Samba", "condition" => "Brand New",
    "price" => "$99.99", "extracted_price" => 99.99, "shipping" => "+$14.95 delivery", "extracted_shipping" => 14.95,
    "link" => "https://www.ebay.com/itm/206415224883", "thumbnail" => "https://i.ebayimg.com/images/g/rp4AAeSwwrlqVqfn/s-l500.jpg"
  }.freeze

  def convert(*items)
    CrossShop::Stores::Ebay.convert({"organic_results" => items})
  end

  def test_plain_listing
    product = convert(PLAIN).products.fetch(0)

    assert_equal ["ebay", "206415224883"], [product.store, product.store_id]
    assert_equal [99.99, 99.99, "USD"], [product.price_min, product.price_max, product.currency]
    assert_equal ["adidas", "title"], [product.brand, product.brand_source]
    assert_equal "new", product.condition
  end

  # SearchApi's eBay results never carry is_sponsored (0 of 480 items), so
  # "not sponsored" cannot be told apart from "unknown".
  def test_sponsored_is_unknown
    assert_nil convert(PLAIN).products.fetch(0).sponsored
  end

  def test_price_range_keeps_both_ends
    item = PLAIN.except("extracted_price").merge(
      "price" => "$84.00 to $128.00", "is_price_range" => true, "extracted_price_range" => {"from" => 84.0, "to" => 128.0}
    )
    product = convert(item).products.fetch(0)

    assert_equal [84.0, 128.0], [product.price_min, product.price_max]
  end

  def test_conditions_are_mapped
    {"Brand New" => "new", "New (Other)" => "new_other", "Pre-Owned" => "used"}.each do |ebay, ours|
      assert_equal ours, convert(PLAIN.merge("condition" => ebay)).products.fetch(0).condition
    end
  end

  def test_an_unmapped_condition_is_rejected_by_name
    conversion = convert(PLAIN.merge("condition" => "For parts or not working"))

    assert_match(/For parts or not working/, conversion.rejects.fetch(0).reason)
  end

  def test_brand_found_only_in_the_subtitle
    product = convert(PLAIN.merge("title" => "Samba OG White Gum B75806", "subtitle" => "US M 9 · adidas")).products.fetch(0)

    assert_equal ["adidas", "subtitle"], [product.brand, product.brand_source]
  end

  def test_levis_without_apostrophe_is_recognised
    product = convert(PLAIN.merge("title" => "Levis 501 Big E Selvedge Denim Jeans Mens 34", "subtitle" => "Size 32 in x 30 in")).products.fetch(0)

    assert_equal "levi's", product.brand
  end
end
