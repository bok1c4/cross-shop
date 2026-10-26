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

  def test_live_flag_without_a_key_fails_loudly
    assert_raises(KeyError) do
      CrossShop::SearchApi.client_from_env({"SEARCHAPI_LIVE" => "1"}, data_dir: @dir)
    end
  end
end
