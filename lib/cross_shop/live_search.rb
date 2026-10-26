require "net/http"
require "openssl"
require "cross_shop/search_api"

module CrossShop
  # One query against several stores at once, one thread per store. The
  # waiting is network I/O, which Ruby threads overlap despite the global VM
  # lock, so the slowest store (Shein: up to about 90 s) sets the time, not
  # the sum. One store failing never fails the others.
  class LiveSearch
    # status: "fetched" (a live call was made), "saved" (already on disk,
    # nothing spent) or "failed". message: SearchApi's or the error's text.
    Outcome = Data.define(:engine, :status, :message)

    # Expected failures of one store. Anything else is a bug and propagates.
    FAILURES = [SearchApi::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError].freeze

    # observer: optional callable that receives an Event when each store finishes.
    def initialize(client:, cache:, observer: nil)
      @client = client
      @cache = cache
      @observer = observer
    end

    def run(query, engines, refresh:)
      engines.map { |engine| Thread.new { outcome(engine, query, refresh) } }.map(&:value)
    end

    private

    def outcome(engine, query, refresh)
      result = attempt(engine, query, refresh)
      @observer&.call(Event.new(at: Time.now.utc, engine:, kind: :engine_finished, data: {status: result.status, message: result.message}))
      result
    end

    def attempt(engine, query, refresh)
      return Outcome.new(engine:, status: "saved", message: nil) if !refresh && @cache.read(engine, q: query)

      response = refresh ? @client.refresh(engine, q: query) : @client.search(engine, q: query)
      Outcome.new(engine:, status: "fetched", message: response["error"])
    rescue *FAILURES => error
      Outcome.new(engine:, status: "failed", message: error.message)
    end
  end
end
