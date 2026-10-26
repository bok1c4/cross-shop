require "net/http"
require "openssl"
require "cross_shop/event"
require "cross_shop/search_api"
require "cross_shop/stores"

module CrossShop
  # When SearchApi answers "no results", downloads the page it fetched
  # (free) and reads the listings on it ourselves, so the console shows both
  # answers. Found necessary on Shein: two "no results" answers for pages
  # with 20 products each.
  class SecondOpinion
    FAILURES = [SearchApi::Error, ArgumentError, JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout,
      SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError].freeze

    def initialize(pages:, observer: nil)
      @pages = pages
      @observer = observer
    end

    # The listings on the page, or nil when there is nothing to check or the
    # check failed (reported, never raised: it must not break the search).
    def call(engine, response)
      parser = Stores::PAGE_PARSERS[engine]
      return nil unless parser && response["error"] && response.dig("search_metadata", "html_url")

      notify(:second_opinion_started, engine)
      listings = parser.call(@pages.fetch(engine, response), response)
      notify(:second_opinion, engine, listings: listings.size, searchapi_said: response["error"])
      listings
    rescue *FAILURES => error
      notify(:second_opinion_failed, engine, error: "#{error.class}: #{error.message}")
      nil
    end

    private

    def notify(kind, engine, **data)
      @observer&.call(Event.new(at: Time.now.utc, engine:, kind:, data:))
    end
  end
end
