require "fileutils"
require "securerandom"

module CrossShop
  module SearchApi
    # Writing a file either completely or not at all.
    #
    # Responses and saved pages are read back as the record of a call that
    # was paid for. A plain write that stopped part way through (the process
    # killed, the disk full) left a short file that still looked like a
    # complete answer, and nothing would fetch it again. Writing beside the
    # file and renaming into place cannot: a rename within one directory
    # either happens or does not.
    module AtomicWrite
      def write_atomically(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        temp = "#{path}.#{Process.pid}-#{SecureRandom.hex(4)}.tmp"
        begin
          File.write(temp, content)
          File.rename(temp, path)
        ensure
          FileUtils.rm_f(temp)
        end
        path
      end
    end
  end
end
