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
    def self.client_from_env(env = ENV, data_dir: DATA_DIR)
      live = env["SEARCHAPI_LIVE"] == "1"
      Client.new(
        cache: ResponseCache.new(File.join(data_dir, "responses")),
        ledger: Ledger.new(File.join(data_dir, "ledger.jsonl")),
        transport: NetHttpTransport.new,
        live:,
        api_key: live ? env.fetch("SEARCHAPI_API_KEY") : nil,
        credit_limit: CREDIT_LIMIT
      )
    end
  end
end
