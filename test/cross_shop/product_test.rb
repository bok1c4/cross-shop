require "test_helper"
require "cross_shop/product"

class ProductTest < Minitest::Test
  VALID = {
    store: "ebay", store_id: "206415224883", title: "Adidas Samba OG JH5633",
    link: "https://www.ebay.com/itm/206415224883", price_min: 99.99, price_max: 99.99,
    currency: "USD", condition: "new", brand: "adidas", brand_source: "title"
  }.freeze

  def test_a_complete_listing_builds_with_optional_fields_defaulting_to_nil
    product = CrossShop::Product.new(**VALID)

    assert_equal 99.99, product.price_min
    assert_nil product.sponsored
    assert_nil product.rating
  end

  # Each case is something a later step (matching, price comparison) would
  # silently get wrong if it were let through.
  INVALID = {
    "no price" => {price_min: nil},
    "zero price" => {price_min: 0, price_max: 0},
    "range upside down" => {price_min: 128.0, price_max: 84.0},
    "other currency" => {currency: "EUR"},
    "unmapped condition" => {condition: "Pre-Owned"},
    "brand without its source" => {brand_source: nil},
    "source without a brand" => {brand: nil},
    "sponsored as text" => {sponsored: "yes"},
    "empty title" => {title: "  "},
    "unknown store" => {store: "temu"}
  }.freeze

  INVALID.each do |name, overrides|
    define_method("test_rejects_#{name.tr(" ", "_")}") do
      assert_raises(CrossShop::Product::Invalid) { CrossShop::Product.new(**VALID, **overrides) }
    end
  end

  # Converters rescue Product::Invalid only. A typo in a converter must crash,
  # not quietly turn every listing into a reject.
  def test_a_misspelled_field_is_a_plain_argument_error_not_invalid
    error = assert_raises(ArgumentError) { CrossShop::Product.new(**VALID, prise: 1) }
    refute_kind_of CrossShop::Product::Invalid, error
  end
end
