require "test_helper"
require "cross_shop/matcher"

class MatcherTest < Minitest::Test
  def product(store, id, title, price, brand: "adidas")
    CrossShop::Product.new(
      store:, store_id: id, title:, link: "https://example.com/#{id}", price_min: price, price_max: price,
      currency: "USD", condition: "new", brand:, brand_source: brand && "title"
    )
  end

  # Titles from the cached responses.
  def test_style_codes_are_mixed_letter_and_digit_tokens_of_six_or_more
    {
      "Adidas Samba OG White Night Indigo Cream JH5633" => ["JH5633"],
      "Nike Dunk Low Retro White Black Panda DD1391-100 Men's Size 10" => ["DD1391-100"],
      "New Balance 550 White Green BB550WT1" => ["BB550WT1"],
      "Converse Chuck 70 Hi Black 162050C" => ["162050C"],
      "Women's Size 10.5 US AF1 4XL 2024 BB550" => []
    }.each do |title, codes|
      assert_equal codes, CrossShop::Matcher.style_codes(title), title
    end
  end

  def test_shared_style_code_matches_across_stores_even_with_different_titles_and_prices
    amazon = product("amazon", "A1", "Samba OG Shoes JH5633", 100)
    ebay = product("ebay", "E1", "adidas Originals Samba OG Night Indigo Size 9 JH5633", 180)

    candidate = CrossShop::Matcher.candidates([amazon, ebay]).fetch(0)

    assert_equal ["style_code", "JH5633"], [candidate.tier, candidate.evidence]
  end

  def test_listings_from_the_same_store_are_never_paired
    a = product("ebay", "E1", "Samba OG JH5633", 100)
    b = product("ebay", "E2", "Samba OG JH5633", 100)

    assert_empty CrossShop::Matcher.candidates([a, b])
  end

  def test_same_brand_similar_title_close_price_is_a_title_match
    amazon = product("amazon", "A1", "adidas Samba OG Cloud White Core Black Gum", 100)
    ebay = product("ebay", "E1", "Adidas Samba OG Cloud White Core Black Gum Mens", 120)

    candidate = CrossShop::Matcher.candidates([amazon, ebay]).fetch(0)

    assert_equal "title", candidate.tier
    assert_operator candidate.score, :>=, 0.5
  end

  def test_title_match_needs_the_same_brand_close_prices_and_similar_words
    amazon = product("amazon", "A1", "adidas Samba OG Cloud White Core Black Gum", 100)
    [
      product("ebay", "E1", "adidas Samba OG Cloud White Core Black Gum", 100, brand: "nike"),
      product("ebay", "E2", "adidas Samba OG Cloud White Core Black Gum", 151),
      product("ebay", "E3", "adidas Gazelle Indoor Blue Fusion Gum", 100),
      product("ebay", "E4", "adidas Samba OG Cloud White Core Black Gum", 100, brand: nil)
    ].each do |ebay|
      assert_empty CrossShop::Matcher.candidates([amazon, ebay]), ebay.store_id
    end
  end

  # Found on real data: following every chain of candidates merged 33 adidas
  # listings into one group. A listing now joins only its best Amazon match.
  def test_a_listing_joins_only_its_best_match_so_groups_do_not_chain
    a1 = product("amazon", "A1", "Samba OG JH5633", 100)
    a2 = product("amazon", "A2", "adidas Samba OG Cloud White Core Black Gum", 100)
    e1 = product("ebay", "E1", "adidas Samba OG Cloud White Core Black Gum JH5633", 100)

    groups = CrossShop::Matcher.groups([a1, a2, e1])

    assert_equal [%w[A1 E1], %w[A2]], groups.map { |group| group.map(&:store_id).sort }.sort
  end

  def test_groups_join_matched_listings_and_leave_the_rest_alone
    a = product("amazon", "A1", "Samba OG JH5633", 100)
    b = product("ebay", "E1", "Samba OG JH5633 Size 9", 110)
    c = product("ebay", "E2", "Gazelle Indoor Blue", 90)

    groups = CrossShop::Matcher.groups([a, b, c])

    assert_equal [%w[A1 E1], %w[E2]], groups.map { |group| group.map(&:store_id).sort }.sort
  end
end
