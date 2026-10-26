require "test_helper"
require "tmpdir"
require "cross_shop/search_api/ledger"

class LedgerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "ledger.jsonl")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_count_is_zero_before_the_first_live_call
    assert_equal 0, CrossShop::SearchApi::Ledger.new(@path).count
  end

  # The credit cap reads this count. If it lived in memory, every new
  # process would start from zero and the cap would never trigger.
  def test_count_survives_a_new_process
    CrossShop::SearchApi::Ledger.new(@path).record(engine: "ebay_search", status: 200)
    CrossShop::SearchApi::Ledger.new(@path).record(engine: "ebay_search", status: 429)

    assert_equal 2, CrossShop::SearchApi::Ledger.new(@path).count
  end

  # Live searches fetch stores in parallel threads. Every record must stay a
  # whole line, or the count and the JSON both break.
  def test_records_from_parallel_threads_stay_whole_lines
    ledger = CrossShop::SearchApi::Ledger.new(@path)
    Array.new(8) { |i| Thread.new { 25.times { ledger.record(engine: "ebay_search", params: {q: "query #{i} " * 20}) } } }.each(&:join)

    lines = File.readlines(@path, encoding: Encoding::UTF_8)
    assert_equal 200, lines.size
    lines.each { |line| JSON.parse(line) }
  end

  # Autocomplete suggests queries people already ran (free, local).
  def test_queries_lists_each_searched_query_once_newest_first
    ledger = CrossShop::SearchApi::Ledger.new(@path)
    ledger.record(engine: "ebay_search", params: {q: "samba"})
    ledger.record(engine: "amazon_search", params: {q: "women’s puffer jacket"})
    ledger.record(engine: "ebay_search", params: {q: "samba"})

    assert_equal ["samba", "women’s puffer jacket"], ledger.queries
  end
end
