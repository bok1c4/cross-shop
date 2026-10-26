require "cross_shop/search_api/client"
require "cross_shop/search_api/net_http_transport"

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

    # SEARCHAPI_READ_TIMEOUT (seconds, default 60): Shein needs more, since
    # SearchApi itself gives up on it after about 90 s.
    def self.client_from_env(env = ENV, data_dir: DATA_DIR, read_timeout: Integer(env.fetch("SEARCHAPI_READ_TIMEOUT", "60")))
      live = env["SEARCHAPI_LIVE"] == "1"
      Client.new(
        cache: cache(data_dir:),
        ledger: ledger(data_dir:),
        transport: NetHttpTransport.new(read_timeout:),
        live:,
        api_key: live ? env.fetch("SEARCHAPI_API_KEY") : nil,
        credit_limit: CREDIT_LIMIT
      )
    end
  end
end
