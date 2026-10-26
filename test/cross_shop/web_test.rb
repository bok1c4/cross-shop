require "test_helper"
require "tmpdir"
require "json"
require "rack/test"
require "cross_shop/web"

class WebTest < Minitest::Test
  include Rack::Test::Methods

  def app
    @app || CrossShop::Web
  end

  # Sinatra's host authorization (DNS-rebinding protection) rejects rack-test's
  # default "example.org". Tests address the app the way a browser does here.
  def default_host
    "localhost"
  end

  def teardown
    app.set :data_dir, CrossShop::SearchApi::DATA_DIR
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
    # SearchApi said "no results"; the listings come from the page it saved.
    assert_includes last_response.body, "20 listings were read by cross-shop from the page SearchApi fetched"
  end

  # A server that runs for hours must serve the templates it started with.
  # Rereading them on every request (Sinatra's development default) paired
  # new views with old classes: bug 23 in LEARNINGS.md.
  def test_templates_are_read_once_not_on_every_request
    dir = @dir = Dir.mktmpdir
    File.write(File.join(dir, "probe.erb"), "first")
    @app = Class.new(CrossShop::Web) do
      set :environment, :development
      set :views, dir
      get("/probe") { erb :probe, layout: false }
    end

    get "/probe"
    File.write(File.join(dir, "probe.erb"), "second")
    get "/probe"

    assert last_response.ok?
    assert_equal "first", last_response.body
  end

  def test_an_uncached_query_says_so
    get "/search", q: "a query nobody fetched"

    assert last_response.ok?
    assert_includes last_response.body, "Nothing saved for"
  end

  # Titles come from other people's websites. They must never run as HTML.
  def test_listing_text_is_escaped
    @dir = Dir.mktmpdir
    cache = CrossShop::SearchApi::ResponseCache.new(File.join(@dir, "responses"))
    cache.write("ebay_search", {q: "x"}, JSON.generate(organic_results: [
      {item_id: "E1", title: "<script>alert(1)</script> Samba", condition: "Brand New", price: "$10.00",
       extracted_price: 10.0, link: "https://www.ebay.com/itm/E1"}
    ]))
    app.set :data_dir, @dir

    get "/search", q: "x"

    refute_includes last_response.body, "<script>alert(1)</script>"
    assert_includes last_response.body, "&lt;script&gt;"
  end

  def test_how_it_works_explains_the_pipeline
    get "/how"

    assert last_response.ok?
    assert_includes last_response.body, "Ledger"
    assert_includes last_response.body, "Matcher"
  end

  # Field health for every saved response, computed when the page loads.
  def test_health_page_shows_the_ebay_shipping_problem
    get "/health"

    assert last_response.ok?
    assert_match(/shipping.*plausible/m, last_response.body)
  end

  def test_notes_render_the_learnings_file
    get "/notes"

    assert last_response.ok?
    assert_includes last_response.body, "<h2"
    assert_includes last_response.body, "Bugs and surprises"
  end
end
