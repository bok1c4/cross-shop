require "test_helper"
require "tmpdir"
require "cross_shop/search_api"

class SearchApiFromEnvTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Spending credits must be an explicit choice, and reading the cache must
  # work without a key (offline tests, CI).
  def test_without_the_live_flag_no_key_is_needed_and_a_miss_raises
    client = CrossShop::SearchApi.client_from_env({}, data_dir: @dir)

    assert_raises(CrossShop::SearchApi::CacheMiss) { client.search("ebay_search", q: "samba og") }
  end

  # SearchApi answers a failing Shein search after about 90 s: all eight of
  # its 503s came between 90.4 and 90.9 s. A 60 s default made the
  # command-line tools give up first and hide SearchApi's own message.
  SHEIN_DEADLINE = 90.9

  def test_the_default_read_timeout_outlasts_searchapis_shein_deadline
    assert_operator CrossShop::SearchApi.transport_from_env({}).read_timeout, :>, SHEIN_DEADLINE
  end

  def test_the_read_timeout_can_still_be_set_from_the_environment
    assert_equal 30, CrossShop::SearchApi.transport_from_env({"SEARCHAPI_READ_TIMEOUT" => "30"}).read_timeout
  end

  def test_live_flag_without_a_key_fails_loudly
    assert_raises(KeyError) do
      CrossShop::SearchApi.client_from_env({"SEARCHAPI_LIVE" => "1"}, data_dir: @dir)
    end
  end
end
