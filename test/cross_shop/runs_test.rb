require "test_helper"
require "stringio"
require "timeout"
require "cross_shop/runs"

class RunsTest < Minitest::Test
  def event(kind)
    CrossShop::Event.new(at: Time.now.utc, engine: "ebay_search", kind:, data: {})
  end

  def wait_until_done(run)
    Timeout.timeout(2) { sleep 0.01 until run.done? }
  end

  def test_a_run_collects_events_and_its_result
    runs = CrossShop::Runs.new
    run = runs.start(query: "samba", engines: %w[ebay_search]) do |current|
      current.add(event(:request_sent))
      :the_result
    end
    wait_until_done(run)

    assert_equal run, runs.find(run.id)
    assert_equal :the_result, run.result
    assert_equal [[:request_sent], true], run.events_after(0).then { |events, done| [events.map(&:kind), done] }
  end

  # The console stream waits for new lines instead of polling in a loop.
  def test_reading_waits_for_new_events_until_the_timeout
    release = Thread::Queue.new
    run = CrossShop::Runs.new.start(query: "samba", engines: %w[ebay_search]) do |current|
      release.pop
      current.add(event(:request_sent))
    end

    assert_equal [[], false], run.events_after(0, timeout: 0.1)

    release << :go
    events, = run.events_after(0, timeout: 2)
    assert_equal [:request_sent], events.map(&:kind)
  end

  # A crash must end the run visibly, or the console would wait forever.
  def test_a_crash_ends_the_run_with_a_failure_event_and_a_log_line
    log = StringIO.new
    run = CrossShop::Runs.new(log:).start(query: "samba", engines: %w[ebay_search]) { raise "boom" }
    wait_until_done(run)

    last = run.events_after(0).first.last
    assert_equal :run_failed, last.kind
    assert_match(/boom/, last.data[:message])
    assert_match(/boom/, log.string)
  end

  def test_only_recent_runs_are_kept
    runs = CrossShop::Runs.new(limit: 2)
    ids = Array.new(3) { runs.start(query: "q", engines: []) { nil }.id }

    assert_nil runs.find(ids[0])
    refute_nil runs.find(ids[2])
  end
end
