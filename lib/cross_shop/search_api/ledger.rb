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

      # Separate from LOCK, so recording never waits behind a reservation
      # reading the count, and so reserve (which holds LOCK) can call count.
      WRITE_LOCK = Mutex.new

      # count and queries read the whole file, and the cap reads the count
      # before every live call. The file only ever grows, so its size says
      # whether a cached answer is still good, including when another process
      # (bin/searchapi) appended to it. {path => [size, value]}.
      READS = {read: {}, queries: {}}.freeze
      READ_LOCK = Mutex.new

      def initialize(path)
        @path = path
        @key = File.expand_path(path)
      end

      # What was committed when a call was reserved, read under the lock.
      Reservation = Data.define(:recorded, :in_flight)

      # Reserves one live call if calls recorded plus calls in flight stay
      # under the limit, in one step. Checking the count and then calling
      # let parallel callers all pass (reproduced by tests: 3 calls on 2
      # credits). Returns a Reservation, or nil once the limit is reached.
      # Release once the call has been recorded.
      def reserve(limit)
        LOCK.synchronize do
          recorded = count
          in_flight = RESERVATIONS[@key]
          return if recorded + in_flight >= limit

          RESERVATIONS[@key] += 1
          Reservation.new(recorded:, in_flight:)
        end
      end

      def release
        LOCK.synchronize { RESERVATIONS[@key] -= 1 }
      end

      # One lock, one write, one line. Append mode alone is not enough:
      # POSIX makes an O_APPEND write atomic, Windows does not, so parallel
      # store threads lost whole records there (8 threads writing 200
      # records left 185 lines). A lost record undercounts the credits
      # spent, and that count is what the cap reads, so the cap could be
      # overshot.
      def record(**entry)
        line = "#{JSON.generate({at: Time.now.utc.iso8601, **entry})}\n"
        WRITE_LOCK.synchronize do
          FileUtils.mkdir_p(File.dirname(@path))
          File.open(@path, File::WRONLY | File::APPEND | File::CREAT, encoding: Encoding::UTF_8) do |file|
            file.write(line)
          end
        end
        forget
      end

      def count
        cached(:read, 0) { |file| file.count }
      end

      def entries
        open_lines { |file| file.map { |line| JSON.parse(line) } } || []
      end

      # Every query ever sent live, once each, newest first: the free source
      # for autocomplete. Read on every home page load, so it is cached too.
      def queries
        cached(:queries, []) do |file|
          file.filter_map { |line| JSON.parse(line).dig("params", "q") }.reverse.uniq
        end
      end

      private

      # Reads the file once per change; an unchanged size means one stat call.
      def cached(store, empty, &read)
        return empty unless File.exist?(@path)

        size = File.size(@path)
        hit = READ_LOCK.synchronize { READS.fetch(store)[@key] }
        return hit.last if hit && hit.first == size

        value = open_lines(&read)
        return empty if value.nil?

        READ_LOCK.synchronize { READS.fetch(store)[@key] = [size, value] }
        value
      end

      # The block form of File.open closes the handle even when reading
      # raises; the enumerator File.foreach returns without one leaves it to
      # the garbage collector.
      def open_lines
        return nil unless File.exist?(@path)

        File.open(@path, encoding: Encoding::UTF_8) { |file| yield(file) }
      end

      def forget
        READ_LOCK.synchronize { READS.each_value { |store| store.delete(@key) } }
      end
    end
  end
end
