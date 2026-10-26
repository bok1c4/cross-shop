require "nokogiri"
require "cross_shop/shein_page"

module CrossShop
  # Cuts a saved store page down to what our parsers read, so the public repo
  # holds the listings but not the rest of someone else's page: no scripts,
  # no tracking data, no seller names, no address the page was fetched from.
  # An allowlist, not a list of things to remove: whatever a page adds next
  # stays out by default.
  module TrimPage
    TRACKING_ATTRIBUTE = /\A(?:data-|_sp\z)/

    # eBay: the listing cards, plus the label text their aria-labelledby
    # points to ("Sponsored", kept outside the cards). Seller names sit in a
    # block outside the cards; tracking lives in data-* and _sp attributes
    # and link queries.
    def self.ebay(html)
      document = Nokogiri::HTML(html, nil, "UTF-8")
      cards = document.css("li.s-card")
      ids = cards.css("[aria-labelledby]").flat_map { |node| node["aria-labelledby"].split }.to_set
      labels = document.xpath("//*[@id]").select { |node| ids.include?(node["id"]) && node.ancestors("li.s-card").empty? }
      (labels + cards.to_a).each { |kept| kept.traverse { |node| untrack(node) if node.element? } }
      list = %(<ul class="srp-results">\n#{cards.map { |card| html_of(card) }.join("\n")}\n</ul>)
      page("eBay search, listing cards only", [*labels.map { |label| html_of(label) }, list].join("\n"))
    end

    # Shein: the embedded product list only. The page config around it holds
    # the fetching client's IP address and session data.
    def self.shein(html)
      bytes = html.b
      start = bytes.index(SheinPage::MARKER)
      raise ArgumentError, "no product list in this page" if start.nil?

      products = SheinPage.json_array(bytes, start + SheinPage::MARKER.bytesize - 1)
      raise ArgumentError, "the product list never ends" if products.nil?

      page("Shein search, product list only", %(<script>{"products":#{products}}</script>))
    end

    def self.untrack(node)
      node.attribute_nodes.each { |attribute| attribute.remove if attribute.name.match?(TRACKING_ATTRIBUTE) }
      node["href"] = node["href"].split("?").first if node["href"]&.include?("?")
    end

    def self.html_of(node)
      node.to_html(encoding: "UTF-8")
    end

    def self.page(title, body)
      %(<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>#{title}</title></head>\n<body>#{body}</body></html>\n)
    end
  end
end
