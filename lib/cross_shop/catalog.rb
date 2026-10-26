require "json"
require "cross_shop/query_set"
require "cross_shop/search_api"
require "cross_shop/search_api/saved_pages"
require "cross_shop/stores"

module CrossShop
  # Products for one query, read from the SearchApi responses on disk. Only
  # reads files, so it never spends a credit or downloads anything.
  # missing_engines: {engine => reason} for every configured engine without
  # products, never treated as "no results". notes: {engine => message} when
  # listings came from somewhere other than SearchApi's own parsing.
  class Catalog
    Result = Data.define(:query, :products, :rejects, :missing_engines, :notes)

    def initialize(cache: SearchApi.cache, engines: QuerySet.load.engines, pages: SearchApi.saved_pages)
      @cache = cache
      @engines = engines
      @pages = pages
    end

    def search(query)
      conversions = []
      missing = {}
      notes = {}
      @engines.each do |engine|
        raw = @cache.read(engine, q: query)
        store = Stores::BY_ENGINE[engine]
        if raw.nil?
          missing[engine] = "not cached"
          next
        end

        response = JSON.parse(raw)
        if response["error"]
          recovered = recover(engine, response)
          if recovered.any? && store
            conversions << store.convert({"organic_results" => recovered})
            notes[engine] = %(SearchApi said "#{response["error"]}"; #{recovered.size} listings were read by cross-shop from the page SearchApi fetched)
          else
            missing[engine] = "SearchApi: #{response["error"]}"
          end
        elsif store.nil?
          missing[engine] = "no converter yet"
        else
          conversions << store.convert(response)
        end
      end
      Result.new(
        query:,
        products: conversions.flat_map(&:products),
        rejects: conversions.flat_map(&:rejects),
        missing_engines: missing,
        notes:
      )
    end

    # How many queries each engine has a cached response for: {engine => count}.
    def coverage(queries)
      @engines.to_h { |engine| [engine, queries.count { |query| @cache.read(engine, q: query) }] }
    end

    private

    # Listings from the saved page, if one is on disk and a parser exists.
    def recover(engine, response)
      parser = Stores::PAGE_PARSERS[engine]
      html = parser && response.dig("search_metadata", "id") && @pages.read(engine, response)
      html ? parser.call(html, response) : []
    end
  end
end
