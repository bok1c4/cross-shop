require "erubi"
require "kramdown"
require "securerandom"
require "time"
require "sinatra/base"
require "cross_shop/catalog"
require "cross_shop/console"
require "cross_shop/live_search"
require "cross_shop/runs"
require "cross_shop/run_report"
require "cross_shop/second_opinion"
require "cross_shop/matcher"
require "cross_shop/search_api"
require "cross_shop/searchapi_health"

module CrossShop
  # The demo site. Viewing saved results is free. Live search spends
  # credits, so it is on only when the site is started with SEARCHAPI_LIVE=1,
  # it is a POST with a CSRF token, and it redirects afterwards so reloading
  # the page cannot spend again.
  class Web < Sinatra::Base
    PROJECT_ROOT = File.expand_path("../..", __dir__)

    set :root, File.join(__dir__, "web")
    # Every <%= %> is escaped: listing text comes from other people's
    # websites. Raw HTML must be asked for with <%== %>.
    set :erb, escape_html: true
    # Templates are read once, like the Ruby code. Sinatra's development
    # default rereads them on every request, so a long-running server paired
    # new views with old classes (bug 23 in LEARNINGS.md). A change to either
    # now needs a restart.
    set :reload_templates, false

    set :data_dir, SearchApi::DATA_DIR
    live = ENV["SEARCHAPI_LIVE"] == "1"
    set :live, live
    # Read only in live mode, so a missing key fails loudly at start.
    set :api_key, live ? ENV.fetch("SEARCHAPI_API_KEY") : nil
    # Its default read timeout outlasts SearchApi's 90 s Shein deadline.
    set :transport, SearchApi::NetHttpTransport.new

    enable :sessions
    set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) }
    # The search button spends credits: every POST needs the form's token.
    use Rack::Protection::AuthenticityToken

    # Live searches run in the background so their console can stream.
    set :runs, Runs.new

    MAX_QUERY_LENGTH = 100

    # How long one event stream is held open before the browser is asked to
    # reconnect, and how long a quiet stream waits before saying it is still
    # working. A stream that is never let go holds a web server thread for as
    # long as the run does, and a wedged run would hold one for ever.
    STREAM_LIMIT_SECONDS = 300
    HEARTBEAT_SECONDS = 15
    RECONNECT_MS = 2000

    helpers do
      # One per request: the home page asks for these inside a loop over
      # every engine and every query.
      def cache
        @cache ||= SearchApi::ResponseCache.new(File.join(settings.data_dir, "responses"))
      end

      def ledger
        @ledger ||= SearchApi::Ledger.new(File.join(settings.data_dir, "ledger.jsonl"))
      end

      def catalog
        @catalog ||= Catalog.new(cache:, pages: SearchApi.saved_pages(data_dir: settings.data_dir))
      end

      # One client per request is safe: the credit cap is reserved in the
      # ledger file, shared by every client in the process.
      def client
        SearchApi::Client.new(cache:, ledger:, transport: settings.transport, live: settings.live,
          api_key: settings.api_key, credit_limit: SearchApi::CREDIT_LIMIT)
      end

      def price(product)
        if product.price_min == product.price_max
          format("$%.2f", product.price_min)
        else
          format("$%.2f–$%.2f", product.price_min, product.price_max)
        end
      end

      # Templates cannot see CrossShop constants by their short names: a bare
      # `Console` in run.erb raised NameError.
      def console_line(event)
        Console.line(event)
      end

      def console_level(event)
        Console.level(event.kind, event.data)
      end

      def store_label(engine)
        RunReport.label(engine)
      end

      def expected_seconds(engine)
        RunReport::EXPECTED_SECONDS[engine]
      end

      def condition_label(product)
        {"new" => "New", "new_other" => "New (other)", "used" => "Used"}.fetch(product.condition)
      end

      # What the whole run came to. The outcomes LiveSearch returns are the
      # run's result; a nil result means it stopped before returning any.
      def run_summary(run, events)
        crash = events.reverse_each.find { |event| event.kind == :run_failed }&.data&.fetch(:message, nil)
        RunReport.summary(run.result, engines: run.engines, crash:)
      end

      def engine_started_at(events)
        events.select { |event| event.kind == :engine_started }.to_h { |event| [event.engine, event.at] }
      end

      # How long the whole run took, for a page opened after it finished:
      # there is no stream left to tell it, and the browser cannot work it
      # out from a clock it was not watching.
      def run_duration(events)
        finished = events.reverse_each.find { |event| event.kind == :run_finished }
        RunReport.seconds(finished.data[:duration_ms]) if finished&.data&.fetch(:duration_ms, nil)
      end
    end

    get "/" do
      query_set = QuerySet.load
      # Autocomplete is local and free: configured queries plus every query
      # searched before. Never SearchApi's autocomplete, which costs credits.
      @queries = (query_set.queries + ledger.queries).uniq
      @saved = @queries.select { |query| query_set.engines.any? { |engine| cache.read(engine, q: query) } }
      @coverage = catalog.coverage(query_set.queries)
      @starter_queries = query_set.queries.size
      @live_calls = ledger.count
      @credit_limit = SearchApi::CREDIT_LIMIT
      @live = settings.live
      erb :home
    end

    get "/search" do
      @query = params[:q].to_s.strip
      redirect to("/") if @query.empty?

      @result = catalog.search(@query)
      candidates = Matcher.candidates(@result.products)
      @best = Matcher.best_matches(candidates)
      groups = Matcher.groups(@result.products, candidates)
      @matched, singles = groups.partition { |group| group.map(&:store).uniq.size > 1 }
      @matched.sort_by! { |group| -group.size }
      @unmatched = singles.flatten.group_by(&:store)

      @engines = QuerySet.load.engines
      @saved_engines = @engines.select { |engine| cache.read(engine, q: @query) }
      @saved_at = @saved_engines.map { |engine| File.mtime(cache.path_for(engine, q: @query)) }.max
      @history = @engines.sum { |engine| cache.history(engine, q: @query).size }
      @live = settings.live
      @credits_used = ledger.count
      @credit_limit = SearchApi::CREDIT_LIMIT
      erb :search
    end

    # Spends credits: one live call per ticked store.
    post "/search" do
      halt 403, "Live search is off. Start the site with SEARCHAPI_LIVE=1 to search the stores." unless settings.live

      query = params[:q].to_s.strip
      halt 400, "Type something to search for (at most #{MAX_QUERY_LENGTH} characters)." if query.empty? || query.length > MAX_QUERY_LENGTH
      engines = Array(params[:engines])
      halt 400, "Tick at least one store." if engines.empty?
      halt 400, "Unknown store." unless (engines - QuerySet.load.engines).empty?

      refresh = params[:refresh] == "1"
      cache = self.cache
      ledger = self.ledger
      data_dir = settings.data_dir
      transport, live, api_key = settings.transport, settings.live, settings.api_key
      run = settings.runs.start(query:, engines:) do |current|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        current.add(Event.new(at: Time.now.utc, engine: nil, kind: :run_started, data: {query:, engines:, refresh:}))
        observer = current.method(:add)
        client = SearchApi::Client.new(cache:, ledger:, transport:, live:, api_key:,
          credit_limit: SearchApi::CREDIT_LIMIT, observer:)
        # Free: downloads the page SearchApi fetched when it says "no results".
        second_opinion = SecondOpinion.new(pages: SearchApi.saved_pages(data_dir:, transport:, api_key:), observer:)
        outcomes = LiveSearch.new(client:, cache:, observer:, second_opinion:).run(query, engines, refresh:)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        current.add(Event.new(at: Time.now.utc, engine: nil, kind: :run_finished, data: {duration_ms:}))
        outcomes
      end
      redirect to("/runs/#{run.id}"), 303
    end

    # The console: each step of a run, as it happened, and what each store
    # came to. Rendered from the events so far, so a page opened half way
    # through a search shows what one that watched it start shows.
    get "/runs/:id" do
      @run = settings.runs.find(params[:id]) || halt(404, "No such search. Runs are kept in memory until the site restarts.")
      @events, @done = @run.events_after(0)
      @states = RunReport.states(@run.engines, @events)
      @started_at = engine_started_at(@events)
      @duration = run_duration(@events)
      @summary = run_summary(@run, @events) if @done
      erb :run
    end

    # Server-Sent Events: one message per console line, then "done" with the
    # outcome. A reconnecting browser sends Last-Event-ID, so no line is sent
    # twice. Each message carries the line to print and the state it puts its
    # store in, both decided here: the browser only applies them.
    get "/runs/:id/events" do
      run = settings.runs.find(params[:id]) || halt(404)
      index = (request.env["HTTP_LAST_EVENT_ID"] || params[:from]).to_i
      content_type "text/event-stream"
      cache_control :no_cache
      # A proxy that buffered would hold every line back until the run ended.
      headers "X-Accel-Buffering" => "no"
      stream do |out|
        out << "retry: #{RECONNECT_MS}\n\n"
        give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STREAM_LIMIT_SECONDS
        loop do
          events, done = run.events_after(index, timeout: HEARTBEAT_SECONDS)
          events.each do |event|
            index += 1
            out << "id: #{index}\ndata: #{JSON.generate(message_for(event))}\n\n"
          end
          if done
            out << "event: done\ndata: #{JSON.generate(run_summary(run, run.events_after(0).first).to_h)}\n\n"
            break
          end
          # Let the stream go rather than hold a thread for ever: the browser
          # reconnects with the last id it saw and misses nothing. Writing is
          # also how a browser that has gone away is noticed.
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= give_up_at

          out << ": still working\n\n" if events.empty?
        end
      end
    end

    get "/how" do
      @live_calls = ledger.count
      @bugs = count_lines(File.join(PROJECT_ROOT, "LEARNINGS.md")) { |line| line.match?(/\A\d+\. \*\*/) }
      erb :how
    end

    # Field health of every saved SearchApi response, computed on each load,
    # and the agent fix log when there is one.
    get "/health" do
      queries = QuerySet.load.queries
      @tables = SearchApiHealth::RULES.keys.to_h do |engine|
        rows = queries.filter_map do |query|
          raw = cache.read(engine, q: query)
          [query, SearchApiHealth.check(engine, JSON.parse(raw))] if raw
        end
        [engine, rows]
      end
      @attempts = read_lines(File.join(PROJECT_ROOT, "data/agent_fix_log.jsonl")).map { |line| JSON.parse(line) }
      erb :health
    end

    get "/notes" do
      markdown = File.read(File.join(PROJECT_ROOT, "LEARNINGS.md"), encoding: Encoding::UTF_8)
      @html = Kramdown::Document.new(markdown).to_html
      erb :notes
    end

    private

    # line first: the browser prints it without looking at anything else.
    def message_for(event)
      store = RunReport.store(event)
      {
        line: Console.line(event),
        level: Console.level(event.kind, event.data),
        engine: event.engine,
        kind: event.kind,
        at: event.at.iso8601,
        store: store&.to_h
      }
    end

    # The block form of File.open closes the handle even when reading raises
    # part way; the enumerator File.foreach returns without one leaves it to
    # the garbage collector.
    def count_lines(path, &matching)
      return 0 unless File.exist?(path)

      File.open(path, encoding: Encoding::UTF_8) { |file| file.count(&matching) }
    end

    def read_lines(path)
      return [] unless File.exist?(path)

      File.open(path, encoding: Encoding::UTF_8, &:readlines)
    end
  end
end
