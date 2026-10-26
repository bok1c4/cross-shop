require "test_helper"
require "cross_shop/shein_page"
require "cross_shop/stores/shein"

class SheinStoreTest < Minitest::Test
  # Field names from SearchApi's shein_search docs, values from a saved page.
  ITEM = {
    "position" => 1, "product_id" => "563285400", "sku" => "st251128877478188773",
    "title" => "Adidas Originals Samba Brown Desert/Warm Vanilla Casual Sneakers Women's KJ7447",
    "link" => "https://us.shein.com/Adidas-Originals-Samba-p-563285400.html", "brand" => "Adidas Originals",
    "price" => "$90.48", "extracted_price" => 90.48, "price_usd" => "$90.48", "extracted_price_usd" => 90.48,
    "rating" => 4.89, "reviews" => 768, "thumbnail" => "https://img.ltwebstatic.com/x.jpg"
  }.freeze

  def convert(*items)
    CrossShop::Stores::Shein.convert({"organic_results" => items})
  end

  def test_listing
    product = convert(ITEM).products.fetch(0)

    assert_equal ["shein", "563285400"], [product.store, product.store_id]
    assert_equal [90.48, 90.48, "USD"], [product.price_min, product.price_max, product.currency]
    assert_equal ["adidas", "field"], [product.brand, product.brand_source]
    assert_equal ["new", nil], [product.condition, product.sponsored]
    assert_equal [4.89, 768], [product.rating, product.reviews_count]
  end

  # SearchApi returns local and USD prices; the USD one is used whatever the domain.
  def test_the_usd_price_wins_over_the_local_one
    item = ITEM.merge("price" => "€84,10", "extracted_price" => 84.1)

    product = convert(item).products.fetch(0)

    assert_equal [90.48, "USD"], [product.price_min, product.currency]
  end

  def test_a_listing_without_any_price_is_rejected_with_a_reason
    conversion = convert(ITEM.except("price", "extracted_price", "price_usd", "extracted_price_usd"))

    assert_match(/price/, conversion.rejects.fetch(0).reason)
  end

  def test_every_listing_parsed_from_a_saved_page_converts
    html = File.read(File.expand_path("../../../fixtures/searchapi/pages/shein_search/search_d97LXP4moruBaXn9Mk03EOrl.html", __dir__), encoding: Encoding::UTF_8)

    conversion = convert(*CrossShop::SheinPage.organic_results(html))

    assert_equal [20, 0], [conversion.products.size, conversion.rejects.size]
    assert_equal 20, conversion.products.count { |product| product.brand == "adidas" }
  end
end
