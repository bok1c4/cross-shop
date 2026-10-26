require "cross_shop/search_api/client"
require "cross_shop/search_api/net_http_transport"
require "cross_shop/search_api/saved_pages"

module CrossShop
  module SearchApi
    DATA_DIR = File.expand_path("../../fixtures/searchapi", __dir__)

    # The trial gives 100 requests. Ten stay in reserve for anything the
    # ledger can't see, such as test searches from the dashboard.
    CREDIT_LIMIT = 90

    # Live mode only when SEARCHAPI_LIVE is exactly "1". The key is read only
    # in live mode, so cached runs work without one.
    def self.cache(data_dir: DATA_DIR)
      ResponseCache.new(File.join(data_dir, "responses"))
    end

    def self.ledger(data_dir: DATA_DIR)
      Ledger.new(File.join(data_dir, "ledger.jsonl"))
    end

    # Read-only unless given a transport and key (see SavedPages#fetch).
    def self.saved_pages(data_dir: DATA_DIR, transport: nil, api_key: nil)
      SavedPages.new(root: File.join(data_dir, "pages"), transport:, api_key:)
    end

    # SEARCHAPI_READ_TIMEOUT (seconds) overrides the transport's default.
    def self.transport_from_env(env = ENV)
      return NetHttpTransport.new unless env.key?("SEARCHAPI_READ_TIMEOUT")

      NetHttpTransport.new(read_timeout: Integer(env["SEARCHAPI_READ_TIMEOUT"]))
    end

    def self.client_from_env(env = ENV, data_dir: DATA_DIR, transport: transport_from_env(env))
      live = env["SEARCHAPI_LIVE"] == "1"
      Client.new(
        cache: cache(data_dir:),
        ledger: ledger(data_dir:),
        transport:,
        live:,
        api_key: live ? env.fetch("SEARCHAPI_API_KEY") : nil,
        credit_limit: CREDIT_LIMIT
      )
    end
  end
end
