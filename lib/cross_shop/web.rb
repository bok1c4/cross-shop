require "erubi"
require "kramdown"
require "sinatra/base"
require "cross_shop/catalog"
require "cross_shop/matcher"
require "cross_shop/search_api"
require "cross_shop/searchapi_health"

module CrossShop
  # The demo site. It reads only cached SearchApi responses (through
  # Catalog), so nothing a visitor does can spend a credit.
  class Web < Sinatra::Base
    PROJECT_ROOT = File.expand_path("../..", __dir__)

    set :root, File.join(__dir__, "web")
    # Every <%= %> is escaped: listing text comes from other people's
    # websites. Raw HTML must be asked for with <%== %>.
    set :erb, escape_html: true
    set :catalog, Catalog.new

    helpers do
      def price(product)
        if product.price_min == product.price_max
          format("$%.2f", product.price_min)
        else
          format("$%.2f–$%.2f", product.price_min, product.price_max)
        end
      end

      def condition_label(product)
        {"new" => "New", "new_other" => "New (other)", "used" => "Used"}.fetch(product.condition)
      end
    end

    get "/" do
      @queries = QuerySet.load.queries
      @coverage = settings.catalog.coverage(@queries)
      @live_calls = SearchApi.ledger.count
      @credit_limit = SearchApi::CREDIT_LIMIT
      erb :home
    end

    get "/search" do
      @query = params[:q].to_s.strip
      @result = settings.catalog.search(@query)
      candidates = Matcher.candidates(@result.products)
      @best = Matcher.best_matches(candidates)
      groups = Matcher.groups(@result.products, candidates)
      @matched, singles = groups.partition { |group| group.map(&:store).uniq.size > 1 }
      @matched.sort_by! { |group| -group.size }
      @unmatched = singles.flatten.group_by(&:store)
      erb :search
    end

    get "/how" do
      @live_calls = SearchApi.ledger.count
      @bugs = File.foreach(File.join(PROJECT_ROOT, "LEARNINGS.md"), encoding: Encoding::UTF_8).count { |line| line.match?(/\A\d+\. \*\*/) }
      erb :how
    end

    # Field health of every saved SearchApi response, computed on each load,
    # and the agent fix log when there is one.
    get "/health" do
      cache = SearchApi.cache
      queries = QuerySet.load.queries
      @tables = SearchApiHealth::RULES.keys.to_h do |engine|
        rows = queries.filter_map do |query|
          raw = cache.read(engine, q: query)
          [query, SearchApiHealth.check(engine, JSON.parse(raw))] if raw
        end
        [engine, rows]
      end
      log = File.join(PROJECT_ROOT, "data/agent_fix_log.jsonl")
      @attempts = File.exist?(log) ? File.foreach(log, encoding: Encoding::UTF_8).map { |line| JSON.parse(line) } : []
      erb :health
    end

    get "/notes" do
      markdown = File.read(File.join(PROJECT_ROOT, "LEARNINGS.md"), encoding: Encoding::UTF_8)
      @html = Kramdown::Document.new(markdown).to_html
      erb :notes
    end
  end
end
