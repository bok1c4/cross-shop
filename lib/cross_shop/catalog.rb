require "json"
require "cross_shop/query_set"
require "cross_shop/search_api"
require "cross_shop/stores"

module CrossShop
  # Products for one query, read from the SearchApi responses on disk. Only
  # reads the cache, so it never spends a credit. Every configured engine
  # without products is reported with the reason ({engine => reason}),
  # never treated as "no results".
  class Catalog
    Result = Data.define(:query, :products, :rejects, :missing_engines)

    def initialize(cache: SearchApi.cache, engines: QuerySet.load.engines)
      @cache = cache
      @engines = engines
    end

    def search(query)
      conversions = []
      missing = {}
      @engines.each do |engine|
        raw = @cache.read(engine, q: query)
        store = Stores::BY_ENGINE[engine]
        if raw.nil?
          missing[engine] = "not cached"
        elsif store.nil?
          missing[engine] = "no converter yet"
        else
          conversions << store.convert(JSON.parse(raw))
        end
      end
      Result.new(
        query:,
        products: conversions.flat_map(&:products),
        rejects: conversions.flat_map(&:rejects),
        missing_engines: missing
      )
    end

    # How many queries each engine has a cached response for: {engine => count}.
    def coverage(queries)
      @engines.to_h { |engine| [engine, queries.count { |query| @cache.read(engine, q: query) }] }
    end
  end
end
