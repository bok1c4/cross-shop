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

  def test_failures_and_saves_read_plainly
    assert_equal "20:29:04  shein_search  ✗ CrossShop::SearchApi::ApiError: SearchApi returned 503 after 90.9 s",
      line(:request_failed, error: "CrossShop::SearchApi::ApiError: SearchApi returned 503", duration_ms: 90_876)
    assert_equal "20:29:04  shein_search  saved fixtures/searchapi/responses/shein_search/nike-air-1-c0.json (previous results kept as history)",
      line(:saved, path: "/Users/x/search-api/fixtures/searchapi/responses/shein_search/nike-air-1-c0.json", archived: true)
  end
end
