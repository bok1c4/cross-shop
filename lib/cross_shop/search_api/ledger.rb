require "fileutils"
require "json"
require "time"

module CrossShop
  module SearchApi
    # Append-only JSON Lines record of every live request, successful or not.
    # Its line count is what the credit cap checks, and it is committed, so
    # the write-up can say exactly how many credits were spent and on what.
    class Ledger
      # Live calls in flight per ledger file, shared by every Ledger object
      # in this process: the site builds a client (and a Ledger) per request,
      # so a lock inside one object would not cover two requests at once.
      RESERVATIONS = Hash.new(0)
      LOCK = Mutex.new

      def initialize(path)
        @path = path
        @key = File.expand_path(path)
      end

      # Reserves one live call if calls recorded plus calls in flight stay
      # under the limit, in one step. Checking the count and then calling
      # let parallel callers all pass (reproduced by tests: 3 calls on 2
      # credits). Release once the call has been recorded.
      def reserve(limit)
        LOCK.synchronize do
          return false if count + RESERVATIONS[@key] >= limit

          RESERVATIONS[@key] += 1
          true
        end
      end

      def release
        LOCK.synchronize { RESERVATIONS[@key] -= 1 }
      end

      def record(**entry)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |file| file.puts(JSON.generate({at: Time.now.utc.iso8601, **entry})) }
      end

      def count
        File.exist?(@path) ? File.foreach(@path).count : 0
      end

      def entries
        return [] unless File.exist?(@path)

        File.foreach(@path, encoding: Encoding::UTF_8).map { |line| JSON.parse(line) }
      end

      # Every query ever sent live, once each, newest first: the free source
      # for autocomplete.
      def queries
        entries.reverse.filter_map { |entry| entry.dig("params", "q") }.uniq
      end
    end
  end
end
