require "cross_shop/search_api/response"

# Stands in for NetHttpTransport. Replays scripted outcomes in order (a
# Response, or an exception to raise) and records every request, so tests
# can assert on exactly what would have gone over the wire.
class FakeTransport
  Request = Data.define(:uri, :query, :headers)

  attr_reader :requests

  def initialize(*outcomes)
    @outcomes = outcomes
    @requests = []
  end

  def get(uri, query:, headers:)
    @requests << Request.new(uri:, query:, headers:)
    outcome = @outcomes.shift
    raise "FakeTransport: unexpected request #{query.inspect}" if outcome.nil?
    raise outcome if outcome.is_a?(Exception)
    outcome
  end
end
