require "json"
require "uri"
require "cross_shop/search_api/ledger"
require "cross_shop/search_api/response"
require "cross_shop/search_api/response_cache"

module CrossShop
  module SearchApi
    class Error < StandardError; end

    # Not cached, and live mode is off.
    class CacheMiss < Error; end

    # The ledger has reached the credit limit.
    class BudgetExceeded < Error; end

    # SearchApi answered with something other than 200.
    class ApiError < Error; end

    # The response contains the API key, so it must not be written to disk.
    class SecretInResponse < Error; end

    # Cache-first SearchApi client. Every way to spend a credit by accident
    # is a raised error rather than a rule to remember:
    # - a request already on disk is never sent again;
    # - nothing is sent unless live mode is on;
    # - nothing is sent once the ledger reaches the credit limit;
    # - only 200 responses are cached, and never one containing the key.
    class Client
      # Frozen: a constant can still be changed in place, and every request
      # starts from this object.
      ENDPOINT = URI("https://www.searchapi.io/api/v1/search").freeze

      def initialize(cache:, ledger:, transport:, live:, api_key:, credit_limit:)
        raise ArgumentError, "live mode needs an api_key" if live && api_key.to_s.empty?

        @cache = cache
        @ledger = ledger
        @transport = transport
        @live = live
        @api_key = api_key
        @credit_limit = credit_limit
      end

      def search(engine, **params)
        if params.key?(:api_key) || params.key?("api_key")
          raise ArgumentError, "pass the API key to Client.new, never as a search param"
        end

        cached = @cache.read(engine, params)
        return JSON.parse(cached) if cached

        raise CacheMiss, "#{engine} #{params} is not cached; set SEARCHAPI_LIVE=1 to spend a credit" unless @live
        if @ledger.count >= @credit_limit
          raise BudgetExceeded, "ledger has #{@ledger.count} live calls; credit limit is #{@credit_limit}"
        end

        body = fetch(engine, params)
        raise SecretInResponse, "#{engine} response contains the API key; not caching it" if body.include?(@api_key)

        @cache.write(engine, params, body)
        JSON.parse(body)
      end

      private

      def fetch(engine, params)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        entry = {engine:, params:}

        begin
          response = @transport.get(ENDPOINT, query: {engine:, **params}, headers: {"Authorization" => "Bearer #{@api_key}"})
        rescue => error
          @ledger.record(**entry, status: nil, search_id: nil, error: error.class.name, duration_ms: elapsed_ms(started))
          raise
        end

        @ledger.record(**entry, status: response.status, search_id: search_id(response.body), error: nil, duration_ms: elapsed_ms(started))
        unless response.status == 200
          raise ApiError, "SearchApi returned #{response.status} for #{engine} #{params}: #{redact(response.body)[0, 300]}"
        end

        response.body
      end

      def search_id(body)
        parsed = JSON.parse(body)
        parsed.dig("search_metadata", "id") if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def elapsed_ms(started)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      end

      def redact(text)
        text.gsub(@api_key, "[REDACTED]")
      end
    end
  end
end
