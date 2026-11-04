module CrossShop
  # What a search looks like while it happens and once it is over: a state
  # per store, and the outcome of the whole run.
  #
  # Both the page and the live stream read it from here. The browser only
  # applies what this decides, so a console loaded half way through a search
  # and one that watched it from the start cannot disagree, and there is one
  # place to change when an event is added.
  module RunReport
    # A store's state, and the short line under its name.
    # took is how long the store took, once it is finished; the card shows
    # the clock running while it is not.
    Store = Data.define(:state, :detail, :took)

    # Final states, in the order the summary reports them, and how each one
    # is named in the outcome.
    FINAL = %w[ok saved empty failed].freeze
    NAMED = {"empty" => "no results", "failed" => "failed"}.freeze

    # ApiError says which engine and params it was for, which a card under a
    # store's name, on a page headed by the query, has already said twice.
    REPEATED = /\ASearchApi returned (\d+) for \S+ \{.*?\}: /

    # How long a store usually takes, for the waiting bar. SearchApi gives up
    # on Shein after about 90 s (every one of its 503s came between 90.4 and
    # 90.9 s), so a Shein search sitting at 70 s is still within budget and
    # must not look stuck. Stores not listed here get no bar.
    EXPECTED_SECONDS = {"shein_search" => 90}.freeze

    # Longest card line; SearchApi's errors repeat the whole query back.
    DETAIL_LIMIT = 90

    def self.label(engine)
      engine.to_s.delete_suffix("_search")
    end

    # The state every store starts in, before any event.
    def self.queued(engines)
      engines.to_h { |engine| [engine, Store.new(state: "queued", detail: "waiting to start", took: nil)] }
    end

    # Store states after replaying `events`: what a page loaded part way
    # through a search shows.
    def self.states(engines, events)
      events.each_with_object(queued(engines)) do |event, states|
        store = store(event)
        states[event.engine] = store if store && states.key?(event.engine)
      end
    end

    # The state this event puts its store in, or nil for run-level events
    # and events that say nothing about a store.
    def self.store(event)
      state, detail = step(event.kind, event.data)
      return unless state

      took = seconds(event.data[:duration_ms]) if event.kind == :engine_finished && event.data[:duration_ms]
      Store.new(state:, detail: clip(detail), took:)
    end

    def self.step(kind, data)
      case kind
      when :engine_started then ["fetching", data[:refresh] ? "fetching fresh results" : "starting"]
      when :cache_hit then ["fetching", "already saved, reading from disk"]
      when :credit_reserved then ["fetching", "1 credit reserved"]
      when :request_sent then ["fetching", "waiting for SearchApi"]
      when :response_received then ["fetching", received(data)]
      when :request_failed then ["fetching", data[:error]]
      when :saved then ["fetching", "saving the response"]
      when :second_opinion_started then ["fetching", "reading the page SearchApi fetched"]
      when :second_opinion then ["fetching", "we read #{data[:listings]} listings on the page"]
      when :second_opinion_failed then ["fetching", "second opinion failed"]
      when :engine_finished then finished(data)
      end
    end

    def self.received(data)
      [data[:status], data[:results] && "#{data[:results]} results"].compact.join(" · ")
    end

    # The duration is not folded in here: SearchApi's messages end in a full
    # stop, and "...try again. in 20.0 s" read like a mistake. The card puts
    # it beside the store's name, the outcome puts it before the reason.
    def self.finished(data)
      case data[:status]
      when "saved" then ["saved", "already saved, no credit spent"]
      when "fetched" then data[:message] ? ["empty", data[:message]] : ["ok", listings(data)]
      else ["failed", reason(data[:message])]
      end
    end

    def self.listings(data)
      count = data[:results] || 0
      took = data[:duration_ms] ? " in #{seconds(data[:duration_ms])}" : ""
      "#{count} #{(count == 1) ? "listing" : "listings"}#{took}"
    end

    def self.reason(message)
      message.to_s.empty? ? "no reason given" : message.sub(REPEATED, 'SearchApi returned \1: ')
    end

    # The outcome of the whole run, as the banner states it. `outcomes` are
    # LiveSearch::Outcomes; nil means the run crashed before returning any.
    Summary = Data.define(:level, :headline, :details, :answered, :total)

    def self.summary(outcomes, engines:, crash: nil)
      return crashed(crash, engines) if outcomes.nil?

      by_state = outcomes.group_by { |outcome| finished(outcome.to_h).first }
      answered = (by_state["ok"].to_a + by_state["saved"].to_a)
      Summary.new(
        level: level(answered.size, outcomes.size),
        headline: headline(answered, outcomes),
        details: FINAL.flat_map { |state| by_state[state].to_a.map { |outcome| detail(outcome) } },
        answered: answered.size, total: outcomes.size
      )
    end

    def self.crashed(crash, engines)
      Summary.new(level: "error", headline: "The search stopped before it finished",
        details: [crash || "Something unexpected went wrong."].compact, answered: 0, total: engines.size)
    end

    def self.level(answered, total)
      return "error" if answered.zero?

      (answered == total) ? "ok" : "warn"
    end

    def self.headline(answered, outcomes)
      return "No store returned results" if answered.empty?

      listings = answered.sum { |outcome| outcome.results.to_i }
      "#{stores(answered.size, outcomes.size)} · #{listings} #{(listings == 1) ? "listing" : "listings"}"
    end

    def self.stores(answered, total)
      return "#{answered} of #{total} stores answered" unless answered == total

      (total == 1) ? "The store answered" : "All #{total} stores answered"
    end

    # One line per store, naming the store and what became of it. A store
    # that did not answer says how long it spent not answering first: that
    # is the part worth knowing about a 90 second Shein failure.
    def self.detail(outcome)
      state, detail = finished(outcome.to_h)
      name = NAMED[state]
      return "#{label(outcome.engine)} — #{detail}" unless name

      took = outcome.duration_ms ? " after #{seconds(outcome.duration_ms)}" : ""
      "#{label(outcome.engine)} — #{name}#{took} · #{detail}"
    end

    def self.seconds(milliseconds)
      "#{(milliseconds.to_i / 1000.0).round(1)} s"
    end

    def self.clip(text)
      text = text.to_s
      (text.length > DETAIL_LIMIT) ? "#{text[0, DETAIL_LIMIT - 1]}…" : text
    end
  end
end
