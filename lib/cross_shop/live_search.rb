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
    # results: listings SearchApi returned, when it answered. duration_ms:
    # how long this store took, so the page can say "failed after 90.4 s".
    Outcome = Data.define(:engine, :status, :message, :results, :duration_ms)

    # Expected failures of one store; anything else is a bug and propagates.
    # JSON::ParserError is here because a saved response is read back as
    # JSON: a truncated cache file is one store that cannot be read, not a
    # reason to fail the whole run.
    FAILURES = [SearchApi::Error, JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError,
      SystemCallError, OpenSSL::SSL::SSLError, IOError].freeze

    # Last resort, above the transport's own read timeout (120 s) so that a
    # store that is merely slow is reported by the transport, with its real
    # error, rather than by this.
    DEADLINE = 180

    # observer: optional callable that receives an Event when each store
    # starts and finishes.
    # second_opinion: optional callable (engine, response) run when SearchApi
    # answers with an error such as "no results" (see SecondOpinion).
    # log: where an unexpected error is written in full, with its backtrace.
    def initialize(client:, cache:, observer: nil, second_opinion: nil, deadline: DEADLINE, log: $stderr)
      @client = client
      @cache = cache
      @observer = observer
      @second_opinion = second_opinion
      @deadline = deadline
      @log = log
    end

    def run(query, engines, refresh:)
      threads = engines.map { |engine| [engine, store_thread(engine, query, refresh)] }
      threads.map { |engine, thread| settle(engine, thread) }
    end

    private

    # Every store thread is waited for, whatever the others did. Reading the
    # threads' values straight through (map(&:value)) abandoned the siblings
    # of any thread that raised something unexpected: they kept fetching,
    # and kept writing to the ledger, after the run had already ended.
    #
    # A thread past the deadline is reported, not killed: killing it in the
    # middle of writing the ledger would leave a half-written record, which
    # is worse than a thread that outlives its run.
    # report_on_exception off because settle below reports it instead: Ruby
    # writes a bare backtrace the moment the thread dies, which arrives
    # without the store or the query it belongs to.
    def store_thread(engine, query, refresh)
      thread = Thread.new { outcome(engine, query, refresh) }
      thread.report_on_exception = false
      thread
    end

    def settle(engine, thread)
      return thread.value if thread.join(@deadline)

      failed(engine, "gave up waiting after #{@deadline} s")
    rescue => error
      # The console gets the one-line reason; the full backtrace goes to the
      # log, where an unexpected error is a bug worth the whole trace.
      @log.puts("#{engine} raised: #{error.full_message(highlight: false)}")
      failed(engine, "#{error.class}: #{error.message}")
    end

    def failed(engine, message)
      notify(engine, :engine_finished, status: "failed", message:, results: nil, duration_ms: nil)
      Outcome.new(engine:, status: "failed", message:, results: nil, duration_ms: nil)
    end

    def outcome(engine, query, refresh)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      notify(engine, :engine_started, refresh:)
      result = attempt(engine, query, refresh, started)
      notify(engine, :engine_finished, status: result.status, message: result.message,
        results: result.results, duration_ms: result.duration_ms)
      result
    end

    def attempt(engine, query, refresh, started)
      unless refresh
        saved = @cache.read(engine, q: query)
        return outcome_for(engine, "saved", nil, JSON.parse(saved), started) if saved
      end

      response = refresh ? @client.refresh(engine, q: query) : @client.search(engine, q: query)
      @second_opinion&.call(engine, response) if response["error"]
      outcome_for(engine, "fetched", response["error"], response, started)
    rescue *FAILURES => error
      Outcome.new(engine:, status: "failed", message: error.message, results: nil, duration_ms: elapsed_ms(started))
    end

    def outcome_for(engine, status, message, response, started)
      Outcome.new(engine:, status:, message:, results: response["organic_results"]&.size,
        duration_ms: elapsed_ms(started))
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end

    def notify(engine, kind, **data)
      @observer&.call(Event.new(at: Time.now.utc, engine:, kind:, data:))
    end
  end
end
