require "test_helper"
require "cross_shop/live_search"
require "cross_shop/run_report"

# What the console page says about each store and about the whole run. The
# page and the live stream both read it from here, so a console opened half
# way through a search cannot disagree with one that watched it start.
class RunReportTest < Minitest::Test
  Report = CrossShop::RunReport

  def event(kind, engine: "shein_search", **data)
    CrossShop::Event.new(at: Time.utc(2026, 10, 26, 20, 29, 4), engine:, kind:, data:)
  end

  def outcome(engine:, status:, message: nil, results: nil, duration_ms: nil)
    CrossShop::LiveSearch::Outcome.new(engine:, status:, message:, results:, duration_ms:)
  end

  def test_every_store_starts_queued
    states = Report.states(%w[amazon_search shein_search], [])

    assert_equal %w[queued queued], states.values.map(&:state)
    assert_equal "waiting to start", states.fetch("amazon_search").detail
  end

  # A page loaded in the middle of a search replays the events it missed.
  def test_states_follow_the_events_so_far
    states = Report.states(%w[amazon_search shein_search], [
      event(:engine_started, engine: "amazon_search", refresh: false),
      event(:engine_started, refresh: false),
      event(:request_sent, url: "www.searchapi.io/api/v1/search?engine=shein_search"),
      event(:engine_finished, engine: "amazon_search", status: "fetched", results: 48, duration_ms: 1800)
    ])

    assert_equal ["ok", "48 listings in 1.8 s"], states.fetch("amazon_search").then { |s| [s.state, s.detail] }
    assert_equal ["fetching", "waiting for SearchApi"], states.fetch("shein_search").then { |s| [s.state, s.detail] }
  end

  # SearchApi answers "no results" with HTTP 200. That is not a success and
  # not a failure, and the card must not claim either.
  def test_an_answer_with_no_results_is_its_own_state
    store = Report.store(event(:engine_finished, status: "fetched", message: "Shein didn't return any results.", duration_ms: 90_400))

    assert_equal "empty", store.state
    assert_equal "Shein didn't return any results.", store.detail
  end

  def test_a_store_already_on_disk_says_nothing_was_spent
    store = Report.store(event(:engine_finished, status: "saved"))

    assert_equal ["saved", "already saved, no credit spent"], [store.state, store.detail]
  end

  def test_a_failure_keeps_the_reason_and_how_long_it_took
    store = Report.store(event(:engine_finished, status: "failed", message: "SearchApi returned 503", duration_ms: 90_876))

    assert_equal "failed", store.state
    assert_equal "SearchApi returned 503", store.detail
    assert_equal "90.9 s", store.took
  end

  # ApiError names the engine and the params it was for. On a card under the
  # store's name, on a page headed by the query, that is the third telling.
  def test_the_engine_and_query_are_not_repeated_back_on_the_card
    store = Report.store(event(:engine_finished, status: "failed", duration_ms: 90_876,
      message: %(SearchApi returned 503 for shein_search {q: "nike air 1"}: We could not retrieve results.)))

    assert_equal "SearchApi returned 503: We could not retrieve results.", store.detail
  end

  def test_a_failure_with_no_message_still_says_something
    assert_equal "no reason given", Report.store(event(:engine_finished, status: "failed")).detail
  end

  # SearchApi's errors repeat the whole query back, and the card is one line.
  def test_a_long_reason_is_cut_to_fit_the_card
    store = Report.store(event(:engine_finished, status: "failed", message: "x" * 200))

    assert_equal Report::DETAIL_LIMIT, store.detail.length
    assert store.detail.end_with?("…")
  end

  def test_run_level_events_belong_to_no_store
    assert_nil Report.store(event(:run_started, engine: nil, query: "samba", engines: [], refresh: false))
  end

  def test_all_stores_answering_reads_as_a_success
    summary = Report.summary([
      outcome(engine: "amazon_search", status: "fetched", results: 48, duration_ms: 1800),
      outcome(engine: "ebay_search", status: "fetched", results: 60, duration_ms: 2100)
    ], engines: %w[amazon_search ebay_search])

    assert_equal "ok", summary.level
    assert_equal "All 2 stores answered · 108 listings", summary.headline
    assert_equal [2, 2], [summary.answered, summary.total]
  end

  # The case this page exists for: Shein spends 90 seconds and fails while
  # the other stores answer. The outcome has to say both.
  def test_one_store_failing_is_a_warning_that_names_it
    summary = Report.summary([
      outcome(engine: "amazon_search", status: "fetched", results: 48, duration_ms: 1800),
      outcome(engine: "shein_search", status: "failed", message: "SearchApi returned 503", duration_ms: 90_876)
    ], engines: %w[amazon_search shein_search])

    assert_equal "warn", summary.level
    assert_equal "1 of 2 stores answered · 48 listings", summary.headline
    assert_equal ["amazon — 48 listings in 1.8 s", "shein — failed after 90.9 s · SearchApi returned 503"], summary.details
  end

  # SearchApi answers "no results" with a 200, which is neither of the above.
  def test_an_empty_answer_is_reported_as_its_own_thing_with_its_own_words
    summary = Report.summary([
      outcome(engine: "ebay_search", status: "fetched", message: "eBay didn't return any results.", duration_ms: 3500)
    ], engines: %w[ebay_search])

    assert_equal "error", summary.level
    assert_equal ["ebay — no results after 3.5 s · eBay didn't return any results."], summary.details
  end

  def test_no_store_answering_is_a_failure
    summary = Report.summary([outcome(engine: "shein_search", status: "failed", message: "Net::ReadTimeout")],
      engines: %w[shein_search])

    assert_equal "error", summary.level
    assert_equal "No store returned results", summary.headline
  end

  # Runs#start records a crash and finishes the run with no outcomes at all.
  def test_a_run_that_stopped_early_says_so_and_carries_the_reason
    summary = Report.summary(nil, engines: %w[shein_search], crash: "RuntimeError: boom")

    assert_equal "error", summary.level
    assert_equal "The search stopped before it finished", summary.headline
    assert_equal ["RuntimeError: boom"], summary.details
  end

  # The waiting bar is scaled to this, so a Shein search sitting at 70 s
  # reads as still within budget rather than stuck.
  def test_shein_has_a_known_deadline_to_scale_the_wait_against
    assert_equal 90, Report::EXPECTED_SECONDS.fetch("shein_search")
    assert_nil Report::EXPECTED_SECONDS["amazon_search"]
  end
end
