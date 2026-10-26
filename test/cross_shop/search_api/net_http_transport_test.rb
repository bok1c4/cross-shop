require "test_helper"
require "socket"
require "cross_shop/search_api/net_http_transport"

class NetHttpTransportTest < Minitest::Test
  # A plain HTTP server on a random local port. It records the head of every
  # request it receives and hands the socket to `respond`.
  class RecordingServer
    attr_reader :requests

    def initialize(&respond)
      @respond = respond
      @requests = Thread::Queue.new
      @server = TCPServer.new("127.0.0.1", 0)
      @thread = Thread.new { serve }
    end

    def url(path)
      URI("http://127.0.0.1:#{@server.addr[1]}#{path}")
    end

    def stop
      @thread.kill
      @server.close
    end

    private

    def serve
      loop do
        socket = @server.accept
        head = +""
        while (line = socket.gets) && line != "\r\n"
          head << line
        end
        @requests << head
        @respond.call(socket)
      end
    end
  end

  def test_sends_an_encoded_get_with_headers_and_returns_an_integer_status
    body = %({"search_metadata": {"id": "search_1"}})
    server = RecordingServer.new do |socket|
      socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end

    # Frozen, like Client::ENDPOINT: the transport must work on a copy.
    response = CrossShop::SearchApi::NetHttpTransport.new.get(
      server.url("/api/v1/search").freeze,
      query: {engine: "ebay_search", q: "samba og"},
      headers: {"Authorization" => "Bearer k"}
    )

    head = server.requests.pop
    assert_match %r{\AGET /api/v1/search\?engine=ebay_search&q=samba\+og HTTP/1\.1\r\n}, head
    assert_match(/^Authorization: Bearer k\r$/, head)
    assert_equal 200, response.status
    assert_equal body, response.body
  ensure
    server&.stop
  end

  # Net::HTTP retries an idempotent request once by default. Against a paid
  # API, a silent retry after a read timeout can be a second billed request.
  def test_a_read_timeout_is_raised_without_retrying
    held = []
    server = RecordingServer.new { |socket| held << socket } # never answers

    transport = CrossShop::SearchApi::NetHttpTransport.new(read_timeout: 0.2)
    assert_raises(Net::ReadTimeout) do
      transport.get(server.url("/api/v1/search"), query: {engine: "ebay_search"}, headers: {})
    end

    assert_equal 1, server.requests.size
  ensure
    server&.stop
    held&.each(&:close)
  end
end
