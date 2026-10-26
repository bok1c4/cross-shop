require "test_helper"
require "tmpdir"
require "support/fake_transport"
require "cross_shop/search_api/saved_pages"

class SavedPagesTest < Minitest::Test
  include CrossShop::SearchApi

  KEY = "test-key-0123456789"
  RESPONSE = {
    "search_metadata" => {
      "id" => "search_8A9g6Ov07XHo3jKz34JlbW2m",
      "html_url" => "https://www.searchapi.io/api/v1/searches/search_8A9g6Ov07XHo3jKz34JlbW2m.html"
    }
  }.freeze
  PAGE = Response.new(status: 200, body: "<html>products</html>")

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def pages(transport)
    SavedPages.new(root: @dir, transport:, api_key: KEY)
  end

  def test_a_page_is_downloaded_once_then_read_from_disk
    transport = FakeTransport.new(PAGE)

    first = pages(transport).fetch("shein_search", RESPONSE)
    second = pages(transport).fetch("shein_search", RESPONSE)

    assert_equal ["<html>products</html>"] * 2, [first, second]
    assert_equal 1, transport.requests.size
    assert_equal "Bearer #{KEY}", transport.requests.first.headers.fetch("Authorization")
  end

  # html_url comes from a response, and the key goes with the request: a
  # response pointing elsewhere must never receive it.
  def test_the_key_is_only_ever_sent_to_searchapi
    transport = FakeTransport.new
    elsewhere = RESPONSE.merge("search_metadata" => RESPONSE["search_metadata"].merge("html_url" => "https://evil.example/x.html"))

    assert_raises(ArgumentError) { pages(transport).fetch("shein_search", elsewhere) }
    assert_empty transport.requests
  end

  def test_a_failed_download_raises_and_saves_nothing
    transport = FakeTransport.new(Response.new(status: 404, body: "not found"))

    assert_raises(ApiError) { pages(transport).fetch("shein_search", RESPONSE) }
    assert_nil pages(transport).read("shein_search", RESPONSE)
  end

  # The search id becomes a file name.
  def test_an_odd_search_id_is_rejected
    odd = {"search_metadata" => {"id" => "../../etc", "html_url" => RESPONSE["search_metadata"]["html_url"]}}

    assert_raises(ArgumentError) { pages(FakeTransport.new).fetch("shein_search", odd) }
  end
end
