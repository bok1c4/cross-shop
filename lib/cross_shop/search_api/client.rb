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

    # A refresh was asked for, but live mode is off.
    class LiveModeOff < Error; end

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
        check_params(params)
        cached = @cache.read(engine, params)
        return JSON.parse(cached) if cached

        raise CacheMiss, "#{engine} #{params} is not cached; set SEARCHAPI_LIVE=1 to spend a credit" unless @live

        fetch_and_store(engine, params)
      end

      # Fetches live even when a response is cached (a re-run from the site).
      # The cached response is kept as history, not overwritten.
      def refresh(engine, **params)
        check_params(params)
        raise LiveModeOff, "live mode is off; set SEARCHAPI_LIVE=1 to spend a credit" unless @live

        fetch_and_store(engine, params)
      end

      private

      def check_params(params)
        return unless params.key?(:api_key) || params.key?("api_key")

        raise ArgumentError, "pass the API key to Client.new, never as a search param"
      end

      # The credit is reserved in the ledger before the call and released
      # once the call is recorded, so parallel calls cannot overshoot the cap.
      def fetch_and_store(engine, params)
        unless @ledger.reserve(@credit_limit)
          raise BudgetExceeded, "the ledger has reached the credit limit of #{@credit_limit}, counting calls in flight"
        end

        begin
          body = fetch(engine, params)
        ensure
          @ledger.release
        end
        raise SecretInResponse, "#{engine} response contains the API key; not caching it" if body.include?(@api_key)

        @cache.write(engine, params, body)
        JSON.parse(body)
      end

      def fetch(engine, params)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        entry = {engine:, params:}

        begin
          response = @transport.get(ENDPOINT, query: {engine:, **params}, headers: {"Authorization" => "Bearer #{@api_key}"})
        rescue => error
          @ledger.record(**entry, status: nil, search_id: nil, error: error.class.name, duration_ms: elapsed_ms(started))
          raise
        end

        id, api_error = metadata(response.body)
        @ledger.record(**entry, status: response.status, search_id: id, error: nil, api_error:, duration_ms: elapsed_ms(started))
        unless response.status == 200
          raise ApiError, "SearchApi returned #{response.status} for #{engine} #{params}: #{redact(response.body)[0, 300]}"
        end

        response.body
      end

      # [search id, SearchApi's "error" message]. SearchApi can answer 200
      # with status "Success" and an error such as "Shein didn't return any
      # results.", so the message is worth keeping even on success.
      def metadata(body)
        parsed = JSON.parse(body)
        parsed.is_a?(Hash) ? [parsed.dig("search_metadata", "id"), parsed["error"]] : [nil, nil]
      rescue JSON::ParserError
        [nil, nil]
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
