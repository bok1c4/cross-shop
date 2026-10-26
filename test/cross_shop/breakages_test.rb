require "test_helper"
require "cross_shop/breakages"

# Simulated layout changes applied to a real saved eBay page. Detection
# compares the broken page with the page's own baseline, not with fixed
# thresholds.
class BreakagesTest < Minitest::Test
  PAGE = File.read(File.expand_path("../../fixtures/ebay_html/adidas-samba-og.html", __dir__), encoding: Encoding::UTF_8).freeze
  BASELINE = CrossShop::Breakages.health(PAGE)

  def regressions_for(name)
    scenario = CrossShop::Breakages::ALL.fetch(name)
    broken = scenario.apply.call(PAGE)
    refute_equal PAGE, broken, "#{name} changed nothing"
    CrossShop::Breakages.regressions(BASELINE, CrossShop::Breakages.health(broken))
  end

  def test_the_unbroken_page_has_no_regressions
    assert_empty CrossShop::Breakages.regressions(BASELINE, CrossShop::Breakages.health(PAGE))
  end

  def test_renamed_attribute_rows_lose_price_and_shipping
    assert_equal %w[price shipping], regressions_for("row_class_renamed").map(&:field).sort
  end

  def test_renamed_title_class_loses_titles
    assert_equal %w[title], regressions_for("title_class_renamed").map(&:field)
  end

  def test_a_new_price_format_loses_prices
    assert_includes regressions_for("price_prefix_added").map(&:field), "price"
  end

  def test_renamed_cards_lose_every_listing
    assert_equal %w[listings], regressions_for("card_class_renamed").map(&:field)
  end

  # The parser reads rows by what they say, so this one should not matter.
  def test_a_renamed_price_class_changes_nothing
    assert_empty regressions_for("price_class_renamed")
  end
end
