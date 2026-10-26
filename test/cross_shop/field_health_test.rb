require "test_helper"
require "cross_shop/field_health"

class FieldHealthTest < Minitest::Test
  Rule = CrossShop::FieldHealth::Rule

  def items(count, &build)
    Array.new(count) { |index| build.call(index) }
  end

  def test_a_healthy_field_passes
    listings = items(10) { |i| {"price" => 10.0 + i} }

    report = CrossShop::FieldHealth.check(listings, [Rule.new(field: "price", min_filled: 0.9)]).fetch(0)

    assert report.passed
    assert_equal [10, 10], [report.total, report.filled]
  end

  # The classic breakage: the site changes, the field comes back empty.
  def test_a_field_emptied_on_too_many_listings_fails
    listings = items(10) { |i| {"price" => (i < 3) ? nil : 10.0} }

    report = CrossShop::FieldHealth.check(listings, [Rule.new(field: "price", min_filled: 0.9)]).fetch(0)

    refute report.passed
    assert_equal 7, report.filled
    assert_match(/70% filled, needs 90%/, report.problem)
  end

  # The quieter breakage: the field is filled, but with the wrong thing.
  # Seen in SearchApi's eBay output ("Buy It Now" in the shipping field).
  def test_a_filled_field_with_implausible_values_fails_on_validity
    listings = items(10) { |i| {"shipping" => (i < 2) ? "Buy It Now" : "+$5.00 delivery"} }
    rule = Rule.new(field: "shipping", min_filled: 0.9, valid: ->(value) { value.match?(/delivery|shipping/i) }, min_valid: 0.95)

    report = CrossShop::FieldHealth.check(listings, [rule]).fetch(0)

    refute report.passed
    assert_equal [10, 8], [report.filled, report.valid]
    assert_match(/80% plausible, needs 95%/, report.problem)
  end

  def test_a_field_can_be_computed_from_several_keys
    listings = [{"extracted_price" => 10.0}, {"extracted_price_range" => {"from" => 5.0}}, {}]
    rule = Rule.new(field: "any price", read: ->(item) { item["extracted_price"] || item["extracted_price_range"] }, min_filled: 0.6)

    report = CrossShop::FieldHealth.check(listings, [rule]).fetch(0)

    assert_equal 2, report.filled
    assert report.passed
  end

  # Zero listings is its own signal ("no results" or a block page), never a pass.
  def test_an_empty_batch_fails_rather_than_passing_vacuously
    report = CrossShop::FieldHealth.check([], [Rule.new(field: "price", min_filled: 0.9)]).fetch(0)

    refute report.passed
    assert_match(/no listings/, report.problem)
  end
end
