require "test_helper"
require "json"
require "net/http"
require "tmpdir"
require "support/fake_transport"
require "cross_shop/live_search"
require "cross_shop/second_opinion"

class LiveSearchTest < Minitest::Test
  include CrossShop::SearchApi

  # Answers by engine: a Response, or an exception to raise. Optionally slow.
  class EngineTransport
    attr_reader :engines

    def initialize(answers, delay: 0)
      @answers = answers
      @delay = delay
      @engines = Thread::Queue.new
    end

    def get(uri, query:, headers:)
      @engines << query[:engine]
      sleep @delay
      answer = @answers.fetch(query[:engine])
      raise answer if answer.is_a?(Exception)

      answer
    end
  end

  OK = Response.new(status: 200, body: %({"search_metadata": {"id": "search_1"}, "organic_results": []}))

  def setup
    @dir = Dir.mktmpdir
    @cache = ResponseCache.new(File.join(@dir, "responses"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def live_search(transport)
    client = Client.new(cache: @cache, ledger: Ledger.new(File.join(@dir, "ledger.jsonl")), transport:,
      live: true, api_key: "test-key", credit_limit: 10)
    CrossShop::LiveSearch.new(client:, cache: @cache)
  end

  def by_engine(outcomes)
    outcomes.to_h { |outcome| [outcome.engine, [outcome.status, outcome.message]] }
  end

  def test_each_selected_store_is_fetched_once
    transport = EngineTransport.new({"amazon_search" => OK, "ebay_search" => OK})

    outcomes = live_search(transport).run("samba", %w[amazon_search ebay_search], refresh: false)

    assert_equal({"amazon_search" => ["fetched", nil], "ebay_search" => ["fetched", nil]}, by_engine(outcomes))
    assert_equal 2, transport.engines.size
  end

  # Shein failing (503 after 90 s, or a timeout) must not cost the other stores.
  def test_one_store_failing_does_not_fail_the_others
    transport = EngineTransport.new({
      "amazon_search" => OK,
      "shein_search" => Response.new(status: 503, body: %({"error": "We could not retrieve results for this search."})),
      "ebay_search" => Net::ReadTimeout.new
    })

    result = by_engine(live_search(transport).run("samba", %w[amazon_search shein_search ebay_search], refresh: false))

    assert_equal "fetched", result.fetch("amazon_search")[0]
    assert_equal "failed", result.fetch("shein_search")[0]
    assert_match(/503/, result.fetch("shein_search")[1])
    assert_equal "failed", result.fetch("ebay_search")[0]
  end

  def test_a_saved_store_is_not_fetched_again_unless_refreshing
    @cache.write("ebay_search", {q: "samba"}, OK.body)
    transport = EngineTransport.new({"ebay_search" => OK})

    assert_equal({"ebay_search" => ["saved", nil]}, by_engine(live_search(transport).run("samba", %w[ebay_search], refresh: false)))
    assert_equal 0, transport.engines.size

    assert_equal({"ebay_search" => ["fetched", nil]}, by_engine(live_search(transport).run("samba", %w[ebay_search], refresh: true)))
    assert_equal 1, transport.engines.size
  end

  # SearchApi's 200 "no results" answer carries its own message.
  def test_searchapis_message_comes_through_on_success
    no_results = Response.new(status: 200, body: %({"search_metadata": {"id": "s"}, "error": "Shein didn't return any results."}))

    outcomes = live_search(EngineTransport.new({"shein_search" => no_results})).run("samba", %w[shein_search], refresh: false)

    assert_equal({"shein_search" => ["fetched", "Shein didn't return any results."]}, by_engine(outcomes))
  end

  def test_each_store_reports_when_it_finishes
    @cache.write("ebay_search", {q: "samba"}, OK.body)
    events = Thread::Queue.new
    client = Client.new(cache: @cache, ledger: Ledger.new(File.join(@dir, "ledger.jsonl")), live: true, api_key: "test-key",
      credit_limit: 10, transport: EngineTransport.new({"amazon_search" => OK}))
    search = CrossShop::LiveSearch.new(client:, cache: @cache, observer: ->(event) { events << event })

    search.run("samba", %w[amazon_search ebay_search], refresh: false)

    finished = Array.new(events.size) { events.pop }.select { |event| event.kind == :engine_finished }
    assert_equal({"amazon_search" => "fetched", "ebay_search" => "saved"}, finished.to_h { |event| [event.engine, event.data[:status]] })
  end

  def test_a_no_results_answer_gets_a_second_opinion_from_the_saved_page
    page = File.read(File.expand_path("../../fixtures/searchapi/pages/shein_search/search_8A9g6Ov07XHo3jKz34JlbW2m.html", __dir__), encoding: Encoding::UTF_8)
    no_results = Response.new(status: 200, body: JSON.generate(
      search_metadata: {id: "search_8A9g6Ov07XHo3jKz34JlbW2m", html_url: "https://www.searchapi.io/api/v1/searches/search_8A9g6Ov07XHo3jKz34JlbW2m.html"},
      search_parameters: {shein_domain: "us.shein.com"}, error: "Shein didn't return any results."
    ))
    transport = FakeTransport.new(no_results, Response.new(status: 200, body: page))
    events = []
    observer = ->(event) { events << event }
    client = Client.new(cache: @cache, ledger: Ledger.new(File.join(@dir, "ledger.jsonl")), transport:, live: true,
      api_key: "test-key", credit_limit: 10, observer:)
    pages = SavedPages.new(root: File.join(@dir, "pages"), transport:, api_key: "test-key")
    search = CrossShop::LiveSearch.new(client:, cache: @cache, observer:, second_opinion: CrossShop::SecondOpinion.new(pages:, observer:))

    outcome = search.run("nike air 1", %w[shein_search], refresh: false).first

    assert_equal "fetched", outcome.status
    assert_equal 20, events.find { |event| event.kind == :second_opinion }.data[:listings]
    assert_equal :engine_finished, events.last.kind
  end

  # Three stores at 0.3 s each finish in about 0.3 s, not 0.9 s.
  def test_stores_are_fetched_in_parallel
    transport = EngineTransport.new({"amazon_search" => OK, "ebay_search" => OK, "shein_search" => OK}, delay: 0.3)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    live_search(transport).run("samba", %w[amazon_search ebay_search shein_search], refresh: false)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 0.75
  end
end
