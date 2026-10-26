require "test_helper"
require "net/http"
require "tmpdir"
require "support/fake_transport"
require "cross_shop/second_opinion"

class SecondOpinionTest < Minitest::Test
  include CrossShop::SearchApi

  PAGE_HTML = File.read(File.expand_path("../../fixtures/searchapi/pages/shein_search/search_8A9g6Ov07XHo3jKz34JlbW2m.html", __dir__), encoding: Encoding::UTF_8).freeze
  NO_RESULTS = {
    "search_metadata" => {"id" => "search_8A9g6Ov07XHo3jKz34JlbW2m",
                          "html_url" => "https://www.searchapi.io/api/v1/searches/search_8A9g6Ov07XHo3jKz34JlbW2m.html"},
    "search_parameters" => {"shein_domain" => "us.shein.com"},
    "error" => "Shein didn't return any results."
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    @events = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def opinion(transport)
    pages = SavedPages.new(root: @dir, transport:, api_key: "test-key")
    CrossShop::SecondOpinion.new(pages:, observer: ->(event) { @events << event })
  end

  def test_no_results_from_searchapi_but_listings_on_the_page_it_fetched
    transport = FakeTransport.new(Response.new(status: 200, body: PAGE_HTML))

    listings = opinion(transport).call("shein_search", NO_RESULTS)

    assert_equal 20, listings.size
    assert_equal %i[second_opinion_started second_opinion], @events.map(&:kind)
    assert_equal [20, "Shein didn't return any results."], @events.last.data.values_at(:listings, :searchapi_said)
  end

  def test_nothing_is_downloaded_when_searchapi_found_listings
    transport = FakeTransport.new

    assert_nil opinion(transport).call("shein_search", {"organic_results" => [{"product_id" => "1"}]})
    assert_empty transport.requests
    assert_empty @events
  end

  def test_stores_without_a_page_parser_are_left_alone
    transport = FakeTransport.new

    assert_nil opinion(transport).call("ebay_search", NO_RESULTS)
    assert_empty transport.requests
  end

  # A failed second opinion is reported, never fatal to the search.
  def test_a_failed_download_is_reported_not_raised
    transport = FakeTransport.new(Net::ReadTimeout.new)

    assert_nil opinion(transport).call("shein_search", NO_RESULTS)
    assert_equal :second_opinion_failed, @events.last.kind
  end
end
