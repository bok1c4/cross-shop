require "cross_shop/search_api/client"

module CrossShop
  module SearchApi
    # Fetches every query × engine pair that is not cached yet. SearchApi
    # allows at most 20% of a plan's credits per hour (20 on the trial), so a
    # run makes at most `max_live_calls` requests, pausing between them, and
    # reports what is left for the next run. The first error stops the run:
    # after a 429 or a timeout, carrying on would only spend more.
    class BatchFetch
      Result = Data.define(:fetched, :remaining)

      def initialize(client:, cache:, max_live_calls:, pause_seconds:, sleeper: ->(seconds) { sleep(seconds) })
        @client = client
        @cache = cache
        @max_live_calls = max_live_calls
        @pause_seconds = pause_seconds
        @sleeper = sleeper
      end

      # Query-major order, so a partial run leaves whole queries done.
      def missing(engines:, queries:)
        queries.product(engines).reject { |query, engine| @cache.read(engine, q: query) }
      end

      def run(engines:, queries:)
        todo = missing(engines:, queries:)
        batch = todo.first(@max_live_calls)
        batch.each_with_index do |(query, engine), index|
          @sleeper.call(@pause_seconds) if index.positive?
          @client.search(engine, q: query)
          yield engine, query if block_given?
        end
        Result.new(fetched: batch.size, remaining: todo.size - batch.size)
      end
    end
  end
end
