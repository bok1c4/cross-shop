require "test_helper"
require "cross_shop/parser_comparison"

class ParserComparisonTest < Minitest::Test
  def compare(ours, theirs)
    CrossShop::ParserComparison.compare(ours:, theirs:)
  end

  def test_listings_are_paired_by_item_id_and_the_rest_reported
    ours = [{"item_id" => "1"}, {"item_id" => "2"}]
    theirs = [{"item_id" => "2"}, {"item_id" => "3"}]

    result = compare(ours, theirs)

    assert_equal %w[2], result.paired_ids
    assert_equal %w[1], result.only_ours
    assert_equal %w[3], result.only_theirs
  end

  def test_each_field_counts_agreements_disagreements_and_one_sided_values
    ours = [
      {"item_id" => "1", "title" => "Samba  OG", "extracted_price" => 99.99, "shipping" => "+$5.00 delivery"},
      {"item_id" => "2", "title" => "Dunk Low", "extracted_price" => 70.0, "shipping" => "Free delivery"}
    ]
    theirs = [
      {"item_id" => "1", "title" => "Samba OG", "extracted_price" => 99.99, "shipping" => "Buy It Now"},
      {"item_id" => "2", "title" => "Dunk Low", "extracted_price" => 75.0}
    ]

    fields = compare(ours, theirs).fields

    assert_equal({agree: 2, differ: 0, only_ours: 0, only_theirs: 0}, fields.fetch("title").counts)
    assert_equal({agree: 1, differ: 1, only_ours: 0, only_theirs: 0}, fields.fetch("extracted_price").counts)
    assert_equal({agree: 0, differ: 1, only_ours: 1, only_theirs: 0}, fields.fetch("shipping").counts)
    assert_equal [["1", "+$5.00 delivery", "Buy It Now"]], fields.fetch("shipping").examples
  end

  # Prices compare as numbers: 70 and 70.0 agree, a cent apart does not.
  def test_numbers_are_compared_as_numbers
    fields = compare([{"item_id" => "1", "extracted_price" => 70}], [{"item_id" => "1", "extracted_price" => 70.0}]).fields

    assert_equal 1, fields.fetch("extracted_price").counts[:agree]
  end
end
