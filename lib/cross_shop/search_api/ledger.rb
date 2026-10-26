require "fileutils"
require "json"
require "time"

module CrossShop
  module SearchApi
    # Append-only JSON Lines record of every live request, successful or not.
    # Its line count is what the credit cap checks, and it is committed, so
    # the write-up can say exactly how many credits were spent and on what.
    class Ledger
      def initialize(path)
        @path = path
      end

      def record(**entry)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |file| file.puts(JSON.generate({at: Time.now.utc.iso8601, **entry})) }
      end

      def count
        File.exist?(@path) ? File.foreach(@path).count : 0
      end
    end
  end
end
