require "test_helper"
require "open3"
require "rbconfig"

# Runs bin/searchapi as a real subprocess, cache-only, with no locale set:
# the environment of cron jobs, CI runners and containers.
class SearchapiCliTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # nil unsets the variable. Live mode and the key are unset too, so these
  # tests can never spend a credit, whatever the calling shell exports.
  NO_LOCALE = {
    "LANG" => nil, "LC_ALL" => nil, "LC_CTYPE" => nil,
    "SEARCHAPI_LIVE" => nil, "SEARCHAPI_API_KEY" => nil
  }

  def test_a_non_ascii_query_works_without_a_utf8_locale
    _out, err, status = run_cli("ebay_search", "q=women’s puffer jacket never cached")

    assert_equal 1, status.exitstatus
    assert_includes err, "CacheMiss"
  end

  def test_an_argument_that_is_not_valid_utf8_is_rejected_by_name
    _out, err, status = run_cli("ebay_search", "q=\xFF".b)

    assert_equal 1, status.exitstatus
    assert_includes err, "not valid UTF-8"
  end

  private

  def run_cli(*args)
    Open3.capture3(NO_LOCALE, RbConfig.ruby, File.join(ROOT, "bin/searchapi"), *args, chdir: ROOT)
  end
end
