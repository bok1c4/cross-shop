require "test_helper"
require "tmpdir"
require "json"
require "rack/test"
require "cross_shop/web"

class WebTest < Minitest::Test
  include Rack::Test::Methods

  def app
    CrossShop::Web
  end

  # Sinatra's host authorization (DNS-rebinding protection) rejects rack-test's
  # default "example.org". Tests address the app the way a browser does here.
  def default_host
    "localhost"
  end

  def teardown
    app.set :catalog, CrossShop::Catalog.new
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_home_lists_the_queries_and_the_credits_spent
    get "/"

    assert last_response.ok?
    assert_includes last_response.body, "adidas samba og"
    assert_match(/\d+ of 90/, last_response.body)
  end

  # Real cached data: both stores, at least one cross-store group, and Shein
  # reported as missing rather than as "no results".
  def test_search_shows_matched_groups_from_cached_data
    get "/search", q: "adidas samba og"

    assert last_response.ok?
    assert_includes last_response.body, "Matched across stores"
    assert_includes last_response.body, "B75806"
    assert_includes last_response.body, "shein_search (not cached)"
  end

  # The site only reads the cache. It cannot spend a credit.
  def test_an_uncached_query_says_so
    get "/search", q: "a query nobody fetched"

    assert last_response.ok?
    assert_includes last_response.body, "No cached data"
  end

  # Titles come from other people's websites. They must never run as HTML.
  def test_listing_text_is_escaped
    @dir = Dir.mktmpdir
    cache = CrossShop::SearchApi::ResponseCache.new(@dir)
    cache.write("ebay_search", {q: "x"}, JSON.generate(organic_results: [
      {item_id: "E1", title: "<script>alert(1)</script> Samba", condition: "Brand New", price: "$10.00",
       extracted_price: 10.0, link: "https://www.ebay.com/itm/E1"}
    ]))
    app.set :catalog, CrossShop::Catalog.new(cache:)

    get "/search", q: "x"

    refute_includes last_response.body, "<script>alert(1)</script>"
    assert_includes last_response.body, "&lt;script&gt;"
  end

  def test_notes_render_the_learnings_file
    get "/notes"

    assert last_response.ok?
    assert_includes last_response.body, "<h2"
    assert_includes last_response.body, "Bugs and surprises"
  end
end
