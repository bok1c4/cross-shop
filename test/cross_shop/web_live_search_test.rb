require "test_helper"
require "tmpdir"
require "timeout"
require "json"
require "rack/test"
require "cross_shop/web"

# Live search from the site: the one place a browser can spend credits.
# Runs against a temporary data folder and a fake transport.
class WebLiveSearchTest < Minitest::Test
  include Rack::Test::Methods

  OK = CrossShop::SearchApi::Response.new(status: 200, body: JSON.generate(search_metadata: {id: "search_1"}, organic_results: []))

  # Answers every request with OK and records which engines were asked.
  class Transport
    attr_reader :engines

    def initialize
      @engines = Thread::Queue.new
    end

    def get(uri, query:, headers:)
      @engines << query[:engine]
      OK
    end
  end

  def app
    CrossShop::Web
  end

  def default_host
    "localhost"
  end

  def setup
    @dir = Dir.mktmpdir
    @transport = Transport.new
    app.set :data_dir, @dir
    app.set :transport, @transport
    app.set :api_key, "test-key"
    app.set :live, true
  end

  def teardown
    app.set :data_dir, CrossShop::SearchApi::DATA_DIR
    app.set :transport, CrossShop::SearchApi::NetHttpTransport.new(read_timeout: 120)
    app.set :api_key, nil
    app.set :live, false
    FileUtils.remove_entry(@dir)
  end

  def cache
    CrossShop::SearchApi::ResponseCache.new(File.join(@dir, "responses"))
  end

  def asked_engines
    Array.new(@transport.engines.size) { @transport.engines.pop }.sort
  end

  def token_for(query)
    get "/search", q: query
    last_response.body[/name="authenticity_token" value="([^"]+)"/, 1] || flunk("no token on the page")
  end

  # POST starts a background run and redirects to its console page.
  def run_from_redirect
    assert_equal 303, last_response.status
    id = URI(last_response.location).path[%r{\A/runs/(\h+)\z}, 1] || flunk("not a run page: #{last_response.location}")
    run = app.settings.runs.find(id)
    Timeout.timeout(5) { sleep 0.01 until run.done? }
    run
  end

  def test_a_new_query_offers_the_stores_and_says_what_it_costs
    get "/search", q: "samba"

    assert_includes last_response.body, "Nothing saved for"
    assert_match(/name="engines\[\]" value="amazon_search" checked/, last_response.body)
    assert_includes last_response.body, "1 credit per store"
  end

  def test_with_live_search_off_the_page_says_how_to_turn_it_on
    app.set :live, false

    get "/search", q: "samba"

    assert_includes last_response.body, "Live search is off"
    refute_includes last_response.body, %(method="post")
  end

  # The search button spends credits, so a forged request must not.
  def test_a_post_without_the_csrf_token_is_refused_and_spends_nothing
    post "/search", q: "samba", engines: ["ebay_search"]

    assert_equal 403, last_response.status
    assert_empty asked_engines
  end

  # Post/Redirect/Get: reloading the console page cannot submit again.
  def test_searching_fetches_only_the_ticked_stores_and_opens_the_console
    token = token_for("samba")

    post "/search", q: "samba", engines: %w[amazon_search ebay_search], authenticity_token: token
    run_from_redirect

    assert_equal %w[amazon_search ebay_search], asked_engines
    refute_nil cache.read("ebay_search", q: "samba")
    follow_redirect!
    assert_includes last_response.body, "→ GET www.searchapi.io/api/v1/search?engine=ebay_search&amp;q=samba"
    assert_includes last_response.body, "done: fetched"
    assert_includes last_response.body, "See the results"
  end

  # The browser receives each line as it happens, as Server-Sent Events.
  def test_the_console_streams_events_and_says_when_it_is_done
    token = token_for("samba")
    post "/search", q: "samba", engines: %w[ebay_search], authenticity_token: token
    run = run_from_redirect

    get "/runs/#{run.id}/events"

    assert_equal "text/event-stream", last_response.media_type
    assert_includes last_response.body, %(data: {"line":)
    assert_includes last_response.body, "← 200"
    assert last_response.body.end_with?("event: done\ndata: {}\n\n")
  end

  # A reconnecting browser sends the last id it saw; nothing is repeated.
  def test_the_stream_resumes_after_the_last_line_the_browser_saw
    token = token_for("samba")
    post "/search", q: "samba", engines: %w[ebay_search], authenticity_token: token
    run = run_from_redirect
    total = run.events_after(0).first.size

    get "/runs/#{run.id}/events", {}, {"HTTP_LAST_EVENT_ID" => (total - 1).to_s}

    assert_equal 1, last_response.body.scan("data: {\"line\"").size
  end

  def test_an_unknown_run_is_not_found
    get "/runs/0123456789abcdef"

    assert_equal 404, last_response.status
  end

  def test_a_saved_query_asks_before_running_again
    cache.write("ebay_search", {q: "samba"}, OK.body)

    get "/search", q: "samba"

    assert_includes last_response.body, "Run this search again?"
  end

  def test_running_again_refetches_and_keeps_the_old_results
    cache.write("ebay_search", {q: "samba"}, OK.body)
    token = token_for("samba")

    post "/search", q: "samba", engines: ["ebay_search"], refresh: "1", authenticity_token: token
    run_from_redirect

    assert_equal %w[ebay_search], asked_engines
    assert_equal 1, cache.history("ebay_search", q: "samba").size
  end

  def test_a_post_while_live_search_is_off_spends_nothing
    token = token_for("samba")
    app.set :live, false

    post "/search", q: "samba", engines: ["ebay_search"], authenticity_token: token

    assert_equal 403, last_response.status
    assert_empty asked_engines
  end

  def test_unknown_stores_and_empty_queries_are_rejected
    token = token_for("samba")

    post "/search", q: "samba", engines: ["temu_search"], authenticity_token: token
    assert_equal 400, last_response.status
    post "/search", q: "   ", engines: ["ebay_search"], authenticity_token: token
    assert_equal 400, last_response.status
    post "/search", q: "samba", authenticity_token: token
    assert_equal 400, last_response.status
    assert_empty asked_engines
  end

  # Autocomplete is local and free: configured queries plus past searches.
  def test_autocomplete_offers_queries_from_past_searches
    CrossShop::SearchApi::Ledger.new(File.join(@dir, "ledger.jsonl")).record(engine: "ebay_search", params: {q: "vintage levis jacket"})

    get "/"

    assert_includes last_response.body, %(<option value="vintage levis jacket">)
  end
end
