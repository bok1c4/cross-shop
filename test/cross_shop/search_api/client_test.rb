require "test_helper"
require "net/http"
require "tmpdir"
require "support/fake_transport"
require "cross_shop/search_api/client"

class ClientTest < Minitest::Test
  include CrossShop::SearchApi

  API_KEY = "test-key-0123456789"
  ENDPOINT = "https://www.searchapi.io/api/v1/search"

  def setup
    @dir = Dir.mktmpdir
    @cache = ResponseCache.new(File.join(@dir, "responses"))
    @ledger_path = File.join(@dir, "ledger.jsonl")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # --- cache first --------------------------------------------------------

  def test_cache_hit_returns_parsed_json_without_a_request
    @cache.write("ebay_search", {q: "samba og"}, body(id: "search_cached"))
    transport = FakeTransport.new

    result = client(transport, live: true).search("ebay_search", q: "samba og")

    assert_equal "search_cached", result.dig("search_metadata", "id")
    assert_empty transport.requests
  end

  def test_cache_miss_without_live_mode_raises_and_sends_nothing
    transport = FakeTransport.new

    assert_raises(CacheMiss) { client(transport, live: false).search("ebay_search", q: "samba og") }
    assert_empty transport.requests
  end

  # --- what goes over the wire --------------------------------------------

  def test_live_request_sends_engine_and_params_with_the_key_only_in_the_header
    transport = FakeTransport.new(Response.new(status: 200, body: body))

    client(transport).search("ebay_search", q: "samba og", page: 2)

    request = transport.requests.fetch(0)
    assert_equal ENDPOINT, request.uri.to_s
    assert_equal({engine: "ebay_search", q: "samba og", page: 2}, request.query)
    assert_equal "Bearer #{API_KEY}", request.headers.fetch("Authorization")
  end

  def test_api_key_as_a_search_param_is_rejected_before_anything_happens
    transport = FakeTransport.new

    assert_raises(ArgumentError) { client(transport).search("ebay_search", q: "x", api_key: API_KEY) }
    assert_empty transport.requests
  end

  # A transport that forgets to copy the URI before setting the query.
  class MutatingTransport
    def get(uri, query:, headers:)
      uri.query = URI.encode_www_form(query)
      CrossShop::SearchApi::Response.new(status: 200, body: "{}")
    end
  end

  # Ruby constants can still be changed in place. Without a frozen endpoint,
  # such a transport would silently change where every later request goes.
  def test_a_transport_that_mutates_the_endpoint_fails_loudly
    assert_raises(FrozenError) { client(MutatingTransport.new).search("ebay_search", q: "samba og") }
    assert_equal ENDPOINT, Client::ENDPOINT.to_s
  ensure
    Client::ENDPOINT.query = nil unless Client::ENDPOINT.frozen?
  end

  def test_live_mode_without_an_api_key_fails_at_construction
    assert_raises(ArgumentError) do
      Client.new(cache: @cache, ledger: ledger, transport: FakeTransport.new, live: true, api_key: nil, credit_limit: 10)
    end
  end

  # --- after a successful request -----------------------------------------

  def test_successful_response_is_cached_so_the_same_search_is_paid_once
    transport = FakeTransport.new(Response.new(status: 200, body: body))
    client = client(transport)

    client.search("ebay_search", q: "samba og")
    client.search("ebay_search", q: "samba og")

    assert_equal 1, transport.requests.size
  end

  def test_live_call_is_ledgered_with_search_id_and_without_the_key
    transport = FakeTransport.new(Response.new(status: 200, body: body(id: "search_abc")))

    client(transport).search("ebay_search", q: "samba og")

    entry = JSON.parse(File.read(@ledger_path))
    assert_equal "ebay_search", entry.fetch("engine")
    assert_equal({"q" => "samba og"}, entry.fetch("params"))
    assert_equal 200, entry.fetch("status")
    assert_equal "search_abc", entry.fetch("search_id")
    assert_kind_of Integer, entry.fetch("duration_ms")
    refute_includes File.read(@ledger_path), API_KEY
  end

  # Seen on Shein: HTTP 200, status "Success", and an "error" field saying
  # there were no results. A definitive answer, so it is cached, but the
  # ledger records the message so a paid-for empty answer is visible.
  def test_a_200_with_an_error_field_is_cached_and_its_message_ledgered
    body = JSON.generate(search_metadata: {id: "search_s", status: "Success"}, error: "Shein didn't return any results.")
    transport = FakeTransport.new(Response.new(status: 200, body:))

    client(transport).search("shein_search", q: "samba og")

    assert_equal "Shein didn't return any results.", JSON.parse(File.read(@ledger_path)).fetch("api_error")
    refute_nil @cache.read("shein_search", q: "samba og")
  end

  # Cached files are committed to git, so a key echoed back must never land on disk.
  def test_response_echoing_the_api_key_is_refused_and_not_cached
    leaky = %({"search_parameters": {"api_key": "#{API_KEY}"}})
    transport = FakeTransport.new(Response.new(status: 200, body: leaky))

    assert_raises(SecretInResponse) { client(transport).search("ebay_search", q: "samba og") }
    assert_nil @cache.read("ebay_search", q: "samba og")
  end

  # --- failures -----------------------------------------------------------

  # An error body cached as if it were a result would poison every later run.
  def test_non_200_raises_is_not_cached_and_is_still_ledgered
    transport = FakeTransport.new(Response.new(status: 429, body: %({"error": "rate limited"})))

    error = assert_raises(ApiError) { client(transport).search("ebay_search", q: "samba og") }

    assert_includes error.message, "429"
    assert_nil @cache.read("ebay_search", q: "samba og")
    assert_equal 429, JSON.parse(File.read(@ledger_path)).fetch("status")
  end

  # A timed-out request may still have been billed, so it counts.
  def test_transport_error_is_ledgered_and_reraised
    transport = FakeTransport.new(Net::ReadTimeout.new)

    assert_raises(Net::ReadTimeout) { client(transport).search("ebay_search", q: "samba og") }

    entry = JSON.parse(File.read(@ledger_path))
    assert_nil entry.fetch("status")
    assert_equal "Net::ReadTimeout", entry.fetch("error")
  end

  # --- credit cap ---------------------------------------------------------

  def test_live_call_is_refused_once_the_ledger_reaches_the_credit_limit
    2.times { ledger.record(engine: "ebay_search", status: 200) }
    transport = FakeTransport.new

    assert_raises(BudgetExceeded) { client(transport, credit_limit: 2).search("ebay_search", q: "samba og") }
    assert_empty transport.requests
  end

  def test_cache_hits_still_work_after_the_credit_limit_is_reached
    2.times { ledger.record(engine: "ebay_search", status: 200) }
    @cache.write("ebay_search", {q: "samba og"}, body(id: "search_cached"))

    result = client(FakeTransport.new, credit_limit: 2).search("ebay_search", q: "samba og")

    assert_equal "search_cached", result.dig("search_metadata", "id")
  end

  private

  def client(transport, live: true, credit_limit: 10)
    Client.new(cache: @cache, ledger: ledger, transport:, live:, api_key: API_KEY, credit_limit:)
  end

  def ledger
    Ledger.new(@ledger_path)
  end

  # Top-level shape of a SearchApi response, per the engine docs.
  def body(id: "search_123")
    JSON.generate(
      search_metadata: {id: id, status: "Success"},
      search_parameters: {engine: "ebay_search", q: "samba og"},
      organic_results: []
    )
  end
end
