require "test_helper"
require "cross_shop/trim_page"
require "cross_shop/ebay_parser"
require "cross_shop/shein_page"

class TrimPageTest < Minitest::Test
  # The parts of a real eBay search page that matter here: a script, a seller
  # block outside the cards, and cards with tracking attributes and links.
  EBAY = <<~HTML
    <!DOCTYPE html><html><head><script>var visitor = "abc";</script></head><body>
    <div class="s-card__attribute-row"><span class="su-styled-text">shoe_seller_42 (6,167) 100%</span></div>
    <div id="s-4odr728" data-track="x">Sponsored</div>
    <ul class="srp-results">
    <li class="s-card s-card--horizontal" data-viewport='{"trackableId":"01GD"}' _sp="p2351460.m1686">
      <span aria-labelledby="s-4odr728 s-missing">derosnopS</span>
      <div class="s-card__title"><span class="su-styled-text primary">Adidas Samba OG JH5633</span></div>
      <a href="https://www.ebay.com/itm/206415224883?_skw=samba&amp;hash=item30&amp;amdata=enc%3A1">link</a>
      <img class="s-card__image" src="https://i.ebayimg.com/images/g/x/s-l500.webp" data-defer-load="1">
      <span class="s-card__price">$99.99</span>
      <div class="s-card__attribute-row"><span>Brand New</span></div>
      <div class="s-card__attribute-row"><span>Located in United States</span></div>
    </li>
    </ul></body></html>
  HTML

  def test_an_ebay_page_keeps_the_cards_and_what_the_parser_reads
    trimmed = CrossShop::TrimPage.ebay(EBAY)

    assert_equal CrossShop::EbayParser.parse(EBAY), CrossShop::EbayParser.parse(trimmed)
    assert_includes trimmed, "Adidas Samba OG JH5633"
  end

  # eBay disguises "Sponsored": the cards point at label text kept elsewhere
  # on the page. The README's surprise needs both ends of that link.
  def test_an_ebay_page_keeps_the_labels_its_cards_point_to
    trimmed = CrossShop::TrimPage.ebay(EBAY)

    assert_includes trimmed, %(<div id="s-4odr728">Sponsored</div>)
    assert_includes trimmed, %(aria-labelledby="s-4odr728 s-missing")
  end

  def test_an_ebay_page_loses_sellers_scripts_and_tracking
    trimmed = CrossShop::TrimPage.ebay(EBAY)

    refute_includes trimmed, "shoe_seller_42"
    refute_includes trimmed, "<script"
    refute_match(/data-|_sp=|trackableId/, trimmed)
    refute_includes trimmed, "?_skw"
    assert_includes trimmed, %(href="https://www.ebay.com/itm/206415224883")
  end

  # Shein's page config holds the address the page was fetched from.
  SHEIN = <<~HTML
    <html><script>var gbCommonInfo = {"ip":"203.0.113.56","memberId":""};</script>
    <script>var gbRawData = {"results":{"products":[{"goods_id":"563285400","goods_name":"Samba \\"OG\\" [x]","salePrice":{"usdAmount":"90.48","usdAmountWithSymbol":"$90.48"}}],"total":1}};</script></html>
  HTML

  def test_a_shein_page_keeps_only_the_product_list
    trimmed = CrossShop::TrimPage.shein(SHEIN)

    assert_equal CrossShop::SheinPage.organic_results(SHEIN), CrossShop::SheinPage.organic_results(trimmed)
    refute_includes trimmed, "203.0.113.56"
    refute_includes trimmed, "memberId"
  end

  def test_a_shein_page_without_a_product_list_fails_loudly
    assert_raises(ArgumentError) { CrossShop::TrimPage.shein("<html>Access denied</html>") }
  end
end
