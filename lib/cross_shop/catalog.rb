require "json"
require "cross_shop/search_api"
require "cross_shop/stores"

module CrossShop
  # Products for one query, read from the SearchApi responses on disk. Only
  # reads the cache, so it never spends a credit. Engines without a cached
  # response are reported as missing, never treated as "no results".
  class Catalog
    Result = Data.define(:query, :products, :rejects, :missing_engines)

    def initialize(cache: SearchApi.cache)
      @cache = cache
    end

    def search(query)
      conversions = []
      missing = []
      Stores::BY_ENGINE.each do |engine, store|
        raw = @cache.read(engine, q: query)
        if raw
          conversions << store.convert(JSON.parse(raw))
        else
          missing << engine
        end
      end
      Result.new(
        query:,
        products: conversions.flat_map(&:products),
        rejects: conversions.flat_map(&:rejects),
        missing_engines: missing
      )
    end
  end
end
