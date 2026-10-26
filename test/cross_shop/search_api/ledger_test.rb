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
end
