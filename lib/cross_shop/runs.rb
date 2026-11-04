require "securerandom"
require "cross_shop/event"

module CrossShop
  # A live search running in the background. It collects the events its
  # client emits, so the site can stream them to the browser as they happen.
  class Run
    attr_reader :id, :query, :engines, :started_at

    def initialize(query:, engines:)
      @id = SecureRandom.hex(8)
      @query = query
      @engines = engines
      @started_at = Time.now.utc
      @events = []
      @done = false
      @result = nil
      @lock = Mutex.new
      @changed = ConditionVariable.new
    end

    def add(event)
      @lock.synchronize do
        @events << event
        @changed.broadcast
      end
    end

    def finish(result)
      @lock.synchronize do
        @result = result
        @done = true
        @changed.broadcast
      end
    end

    def done?
      @lock.synchronize { @done }
    end

    def result
      @lock.synchronize { @result }
    end

    # Events after the first `index`, waiting up to `timeout` seconds if
    # there are none yet (no busy polling). Returns [events, done].
    def events_after(index, timeout: 0)
      @lock.synchronize do
        @changed.wait(@lock, timeout) if timeout.positive? && @events.size <= index && !@done
        [@events.drop(index), @done]
      end
    end
  end

  # Recent runs, kept in memory until the site restarts.
  class Runs
    def initialize(limit: 20, log: $stderr)
      @limit = limit
      @log = log
      @runs = {}
      @lock = Mutex.new
    end

    # Runs `work` in a thread with the new run; its return value becomes the
    # run's result. A crash is recorded as an event and ends the run, so a
    # console waiting on it never hangs, and it is logged in full.
    def start(query:, engines:, &work)
      run = Run.new(query:, engines:)
      @lock.synchronize do
        @runs[run.id] = run
        evict
      end
      Thread.new do
        run.finish(work.call(run))
      rescue => error
        run.add(Event.new(at: Time.now.utc, engine: nil, kind: :run_failed, data: {message: "#{error.class}: #{error.message}"}))
        run.finish(nil)
        @log.puts("run #{run.id} crashed: #{error.full_message(highlight: false)}")
      end
      run
    end

    def find(id)
      @lock.synchronize { @runs[id] }
    end

    private

    # Oldest first, but finished runs before running ones: dropping a run
    # that is still going would 404 the console still streaming it. The
    # limit is still a hard cap, so memory stays bounded either way.
    # Call with the lock held.
    def evict
      return if @runs.size <= @limit

      order = @runs.keys.each_with_index.sort_by { |id, index| [@runs[id].done? ? 0 : 1, index] }
      order.each do |id, _index|
        break if @runs.size <= @limit

        @runs.delete(id)
      end
    end
  end
end
