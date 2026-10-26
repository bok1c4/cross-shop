require "test_helper"
require "cross_shop/stores/amazon"

# Items copied from cached amazon_search responses (2026-10-26), trimmed of
# fields the converter does not read.
class AmazonStoreTest < Minitest::Test
  BRANDED = {
    "position" => 1, "asin" => "B0F9NVFF6G", "title" => "Women's Samba OG W Shoes", "brand" => "adidas",
    "rating" => 4.6, "reviews" => 830, "price" => "$89.95", "extracted_price" => 89.95,
    "link" => "https://www.amazon.com/dp/B0F9NVFF6G", "thumbnail" => "https://m.media-amazon.com/images/I/51HX8zYi3JL.jpg"
  }.freeze

  def convert(*items)
    CrossShop::Stores::Amazon.convert({"organic_results" => items})
  end

  def test_branded_listing
    product = convert(BRANDED).products.fetch(0)

    assert_equal ["amazon", "B0F9NVFF6G"], [product.store, product.store_id]
    assert_equal [89.95, 89.95, "USD"], [product.price_min, product.price_max, product.currency]
    assert_equal ["adidas", "field"], [product.brand, product.brand_source]
    assert_equal "new", product.condition
    assert_equal [4.6, 830], [product.rating, product.reviews_count]
    assert_equal false, product.sponsored
  end

  # Observed in 448 items: is_sponsored only ever appears as true.
  def test_sponsored_flag
    assert_equal true, convert(BRANDED.merge("is_sponsored" => true)).products.fetch(0).sponsored
  end

  def test_brand_field_is_normalised_to_the_known_brand
    product = convert(BRANDED.merge("brand" => "adidas Originals")).products.fetch(0)

    assert_equal "adidas", product.brand
  end

  def test_unknown_brand_field_is_kept_lowercased
    product = convert(BRANDED.merge("brand" => "Project Cloud")).products.fetch(0)

    assert_equal ["project cloud", "field"], [product.brand, product.brand_source]
  end

  def test_missing_brand_field_falls_back_to_the_title
    product = convert(BRANDED.except("brand").merge("title" => "Nike Dunk Low Retro")).products.fetch(0)

    assert_equal ["nike", "title"], [product.brand, product.brand_source]
  end

  # 7 of 448 cached items have no price (only "more_offers").
  def test_listing_without_a_price_is_rejected_with_a_reason
    conversion = convert(BRANDED.except("price", "extracted_price"))

    assert_empty conversion.products
    assert_equal "B0F9NVFF6G", conversion.rejects.fetch(0).store_id
    assert_match(/price/, conversion.rejects.fetch(0).reason)
  end
end
