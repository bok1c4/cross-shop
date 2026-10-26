require "test_helper"
require "tmpdir"
require "support/fake_transport"
require "cross_shop/search_api/batch_fetch"

class BatchFetchTest < Minitest::Test
  include CrossShop::SearchApi

  OK = Response.new(status: 200, body: %({"search_metadata": {"id": "search_1"}}))

  def setup
    @dir = Dir.mktmpdir
    @cache = ResponseCache.new(File.join(@dir, "responses"))
    @sleeps = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_only_pairs_missing_from_the_cache_are_fetched
    @cache.write("ebay_search", {q: "samba"}, "{}")
    transport = FakeTransport.new(OK, OK, OK)

    result = batch(transport).run(engines: %w[amazon_search ebay_search], queries: %w[samba dunk])

    sent = transport.requests.map { |r| [r.query[:engine], r.query[:q]] }
    assert_equal [%w[amazon_search samba], %w[amazon_search dunk], %w[ebay_search dunk]], sent
    assert_equal 3, result.fetched
    assert_equal 0, result.remaining
  end

  # SearchApi allows 20% of plan credits per hour: 20 on the trial.
  def test_one_run_stops_at_the_live_call_limit_and_reports_the_rest
    transport = FakeTransport.new(OK, OK)

    result = batch(transport, max_live_calls: 2).run(engines: %w[ebay_search], queries: %w[a b c d])

    assert_equal 2, transport.requests.size
    assert_equal 2, result.remaining
  end

  def test_pauses_between_live_calls_but_not_before_the_first
    transport = FakeTransport.new(OK, OK, OK)

    batch(transport, pause_seconds: 3).run(engines: %w[ebay_search], queries: %w[a b c])

    assert_equal [3, 3], @sleeps
  end

  # After a 429 or a timeout, carrying on would only spend more.
  def test_stops_at_the_first_error
    transport = FakeTransport.new(Response.new(status: 429, body: "{}"))

    assert_raises(ApiError) { batch(transport).run(engines: %w[ebay_search], queries: %w[a b]) }
    assert_equal 1, transport.requests.size
  end

  private

  def batch(transport, max_live_calls: 10, pause_seconds: 0)
    client = Client.new(
      cache: @cache, ledger: Ledger.new(File.join(@dir, "ledger.jsonl")), transport:,
      live: true, api_key: "test-key", credit_limit: 90
    )
    BatchFetch.new(client:, cache: @cache, max_live_calls:, pause_seconds:, sleeper: ->(seconds) { @sleeps << seconds })
  end
end
