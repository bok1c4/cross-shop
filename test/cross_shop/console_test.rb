require "test_helper"
require "cross_shop/console"

class ConsoleTest < Minitest::Test
  AT = Time.utc(2026, 10, 26, 20, 29, 4)

  def line(kind, engine: "shein_search", **data)
    CrossShop::Console.line(CrossShop::Event.new(at: AT, engine:, kind:, data:))
  end

  def test_a_request_shows_the_url_without_the_key
    assert_equal %(20:29:04  shein_search  → GET www.searchapi.io/api/v1/search?engine=shein_search&q=nike+air+1 (API key sent in a header, not shown)),
      line(:request_sent, url: "www.searchapi.io/api/v1/search?engine=shein_search&q=nike+air+1")
  end

  # SearchApi's own timings say where the time went: fetching the store or
  # parsing it. Shein's request_url has backticks, so it is cut as a string.
  def test_a_response_shows_searchapis_timings_results_and_message
    text = line(:response_received, status: 200, duration_ms: 75_271, results: 0, search_id: "search_8A9g",
      fetched_url: "https://us.shein.com/pdsearch/nike%20air%201/?ici=s1`EditSearch`nike", request_time: 74.47, parsing_time: 0.03,
      api_error: "Shein didn't return any results.")

    assert_equal %(20:29:04  shein_search  ← 200 in 75.3 s · SearchApi fetched us.shein.com/pdsearch/nike%20air%201/ in 74.47 s, parsed in 0.03 s) +
      %( · 0 results · search_8A9g · SearchApi says: "Shein didn't return any results."), text
  end

  def test_run_level_lines_have_no_engine
    assert_equal %(20:29:04  search        searching shein_search, ebay_search for "nike air 1"),
      line(:run_started, engine: nil, query: "nike air 1", engines: %w[shein_search ebay_search], refresh: false)
  end

  # A re-run fetches every ticked store, saved or not ("fetching saved stores
  # again" was wrong when the store had nothing saved).
  def test_a_re_run_says_what_it_does
    assert_equal %(20:29:04  search        searching shein_search for "new balance 550" (run again: every ticked store is fetched fresh)),
      line(:run_started, engine: nil, query: "new balance 550", engines: %w[shein_search], refresh: true)
  end

  def test_the_second_opinion_puts_both_answers_side_by_side
    assert_equal %(20:29:04  shein_search  second opinion: SearchApi said "Shein didn't return any results.", but the page it fetched has 20 listings; they are shown, marked as read by cross-shop),
      line(:second_opinion, listings: 20, searchapi_said: "Shein didn't return any results.")
    assert_equal %(20:29:04  shein_search  second opinion: the page SearchApi fetched has no listings either),
      line(:second_opinion, listings: 0, searchapi_said: "Shein didn't return any results.")
  end

  # Bug 25: parallel calls each said "27 of 90 used before this call".
  def test_a_reservation_mentions_calls_still_in_flight
    assert_equal "20:29:04  shein_search  reserved 1 credit (27 of 90 used before this call)",
      line(:credit_reserved, used: 27, in_flight: 0, limit: 90)
    assert_equal "20:29:04  shein_search  reserved 1 credit (27 of 90 used before this call, 2 more in flight)",
      line(:credit_reserved, used: 27, in_flight: 2, limit: 90)
  end

  # The browser colours each line by what the server calls it, rather than
  # guessing from the text. A 503 is a failure however politely SearchApi
  # words it; its 200 "no results" is worth noticing but is not one.
  def test_each_line_says_whether_it_is_a_failure
    level = ->(kind, **data) { CrossShop::Console.level(kind, data) }

    assert_equal "error", level.call(:response_received, status: 503, api_error: "We could not retrieve results.")
    assert_equal "warn", level.call(:response_received, status: 200, api_error: "Shein didn't return any results.")
    assert_equal "info", level.call(:response_received, status: 200, api_error: nil)
    assert_equal "error", level.call(:engine_finished, status: "failed", message: "Net::ReadTimeout")
    assert_equal "warn", level.call(:engine_finished, status: "fetched", message: "Shein didn't return any results.")
    assert_equal "info", level.call(:engine_finished, status: "fetched", message: nil)
    assert_equal "error", level.call(:request_failed, error: "SocketError")
    assert_equal "info", level.call(:request_sent, url: "www.searchapi.io/api/v1/search")
  end

  def test_a_store_that_finished_says_what_it_cost_and_how_long_it_took
    assert_equal "20:29:04  shein_search  done: fetched · 20 results · 1.8 s",
      line(:engine_finished, status: "fetched", results: 20, duration_ms: 1800)
    assert_equal "20:29:04  shein_search  done: already saved, no credit spent",
      line(:engine_finished, status: "saved")
  end

  def test_failures_and_saves_read_plainly
    assert_equal "20:29:04  shein_search  ✗ CrossShop::SearchApi::ApiError: SearchApi returned 503 after 90.9 s",
      line(:request_failed, error: "CrossShop::SearchApi::ApiError: SearchApi returned 503", duration_ms: 90_876)
    assert_equal "20:29:04  shein_search  saved fixtures/searchapi/responses/shein_search/nike-air-1-c0.json (previous results kept as history)",
      line(:saved, path: "/Users/x/search-api/fixtures/searchapi/responses/shein_search/nike-air-1-c0.json", archived: true)
  end
end
