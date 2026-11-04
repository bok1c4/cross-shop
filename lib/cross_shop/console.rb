require "cross_shop/event"

module CrossShop
  # One readable line per event for the site's live console: time, source,
  # what happened. Events carry only what the code really did, never the key.
  module Console
    def self.line(event)
      "#{event.at.strftime("%H:%M:%S")}  #{(event.engine || "search").ljust(14)}#{text(event.kind, event.data)}"
    end

    def self.text(kind, data)
      case kind
      when :run_started
        %(searching #{data[:engines].join(", ")} for "#{data[:query]}") + (data[:refresh] ? " (run again: every ticked store is fetched fresh)" : "")
      when :engine_started then data[:refresh] ? "started (fetching fresh)" : "started"
      when :cache_hit then "already saved, no credit spent: #{short_path(data[:path])}"
      when :credit_reserved then reserved(data)
      when :request_sent then "→ GET #{data[:url]} (API key sent in a header, not shown)"
      when :response_received then response(data)
      when :request_failed then "✗ #{data[:error]} after #{seconds(data[:duration_ms])}"
      when :saved then "saved #{short_path(data[:path])}" + (data[:archived] ? " (previous results kept as history)" : "")
      when :engine_finished then finished(data)
      when :second_opinion_started then "second opinion: downloading the page SearchApi fetched (free)"
      when :second_opinion then second_opinion(data)
      when :second_opinion_failed then "second opinion failed: #{data[:error]}"
      when :run_finished then "finished in #{seconds(data[:duration_ms])}"
      when :run_failed then "✗ the search crashed: #{data[:message]}"
      else "#{kind} #{data.inspect}"
      end
    end

    # How the line reads: a failure, something worth noticing, or a step.
    # Decided here rather than in the browser, which would have to guess
    # from the text.
    def self.level(kind, data)
      case kind
      when :request_failed, :run_failed, :second_opinion_failed then "error"
      when :engine_finished then engine_level(data)
      when :response_received then response_level(data)
      else "info"
      end
    end

    # A 503 is a failure however politely SearchApi words it; a 200 with a
    # message ("no results") is worth noticing but is not one.
    def self.response_level(data)
      return "error" unless data[:status] == 200

      data[:api_error] ? "warn" : "info"
    end

    # SearchApi answers "no results" with a 200 and a message, which is
    # worth noticing without being a failure.
    def self.engine_level(data)
      return "error" if data[:status] == "failed"

      data[:message] ? "warn" : "info"
    end

    # SearchApi's own timings show where the time went: fetching the store,
    # or parsing what came back.
    def self.response(data)
      parts = ["← #{data[:status]} in #{seconds(data[:duration_ms])}"]
      if data[:fetched_url]
        parts << "SearchApi fetched #{short_url(data[:fetched_url])} in #{data[:request_time]} s, parsed in #{data[:parsing_time]} s"
      end
      parts << "#{data[:results]} results" if data[:results]
      parts << data[:search_id] if data[:search_id]
      parts << %(SearchApi says: "#{data[:api_error]}") if data[:api_error]
      parts.join(" · ")
    end

    # Parallel calls are in flight together; without them the line would
    # show every call as the next one (bug 25).
    def self.reserved(data)
      in_flight = data[:in_flight].to_i.positive? ? ", #{data[:in_flight]} more in flight" : ""
      "reserved 1 credit (#{data[:used]} of #{data[:limit]} used before this call#{in_flight})"
    end

    def self.second_opinion(data)
      return "second opinion: the page SearchApi fetched has no listings either" if data[:listings].zero?

      %(second opinion: SearchApi said "#{data[:searchapi_said]}", but the page it fetched has #{data[:listings]} listings; ) +
        "they are shown, marked as read by cross-shop"
    end

    def self.finished(data)
      return "done: already saved, no credit spent" if data[:status] == "saved"

      parts = ["done: #{data[:status]}"]
      parts << "#{data[:results]} results" if data[:results]
      parts << seconds(data[:duration_ms]) if data[:duration_ms]
      done = parts.join(" · ")
      data[:message] ? "#{done} (#{data[:message]})" : done
    end

    def self.seconds(milliseconds)
      "#{(milliseconds.to_i / 1000.0).round(1)} s"
    end

    # Cut as a string: Shein's request_url contains backticks, which URI() rejects.
    def self.short_url(url)
      url.split("?").first.sub(%r{\Ahttps?://}, "")
    end

    def self.short_path(path)
      path.to_s[%r{fixtures/.*}] || File.basename(path.to_s)
    end
  end
end
