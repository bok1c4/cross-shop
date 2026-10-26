require "test_helper"
require "tmpdir"
require "cross_shop/search_api/response_cache"

class ResponseCacheTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @cache = CrossShop::SearchApi::ResponseCache.new(@root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_returns_nil_for_a_request_never_written
    assert_nil @cache.read("ebay_search", q: "nike dunk low")
  end

  def test_reads_back_the_exact_bytes_that_were_written
    body = %({"organic_results": [{"extracted_price": 110.0}]}\n)
    @cache.write("ebay_search", {q: "nike dunk low"}, body)

    assert_equal body, @cache.read("ebay_search", q: "nike dunk low")
  end

  # The same request spelled differently must not cost a second credit.
  def test_param_order_key_type_and_value_type_do_not_change_the_entry
    @cache.write("ebay_search", {q: "nike dunk low", page: 2}, "{}")

    assert_equal "{}", @cache.read("ebay_search", "page" => "2", "q" => "nike dunk low")
  end

  # Keying on engine + q alone would serve a US response for a German request.
  def test_any_differing_param_is_a_different_entry
    @cache.write("ebay_search", {q: "nike dunk low", ebay_domain: "ebay.com"}, "{}")

    assert_nil @cache.read("ebay_search", q: "nike dunk low", ebay_domain: "ebay.de")
    assert_nil @cache.read("ebay_search", q: "nike dunk low")
  end

  def test_same_params_on_a_different_engine_is_a_different_entry
    @cache.write("ebay_search", {q: "nike dunk low"}, "{}")

    assert_nil @cache.read("amazon_search", q: "nike dunk low")
  end

  # Re-running a search from the site must not destroy results already paid for.
  def test_writing_again_keeps_the_previous_response_as_history
    @cache.write("ebay_search", {q: "samba"}, "first")
    @cache.write("ebay_search", {q: "samba"}, "second")
    @cache.write("ebay_search", {q: "samba"}, "third")

    assert_equal "third", @cache.read("ebay_search", q: "samba")
    assert_equal %w[second first], @cache.history("ebay_search", q: "samba").map { |entry| File.read(entry.path) }
    assert_empty @cache.history("ebay_search", q: "never written")
  end

  # The engine name becomes a directory, and the CLI takes it from the command
  # line. The newline case is Ruby-specific: ^ and $ match at any line break.
  def test_an_engine_name_that_could_leave_the_cache_folder_is_rejected
    cache = CrossShop::SearchApi::ResponseCache.new(File.join(@root, "responses"))

    ["../escaped", "ebay_search/../../escaped", "ebay_search\n../escaped", "Ebay Search", ""].each do |engine|
      assert_raises(ArgumentError, engine.inspect) { cache.read(engine, q: "x") }
      assert_raises(ArgumentError, engine.inspect) { cache.write(engine, {q: "x"}, "{}") }
    end
    assert_empty Dir.children(@root)
  end

  # Found on the first live call: with no locale set (cron, CI, containers),
  # Ruby reads files as US-ASCII and JSON.parse fails on the first "’" or "·".
  def test_reads_utf8_even_when_the_process_locale_is_not_utf8
    body = %({"title": "adidas Samba OG Women’s · US 6"})
    @cache.write("ebay_search", {q: "samba"}, body)

    read = with_default_external(Encoding::US_ASCII) { @cache.read("ebay_search", q: "samba") }

    assert_equal body, read
  end

  private

  def with_default_external(encoding)
    original = Encoding.default_external
    without_warnings { Encoding.default_external = encoding }
    yield
  ensure
    without_warnings { Encoding.default_external = original }
  end

  def without_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
