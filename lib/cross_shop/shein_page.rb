require "json"

module CrossShop
  # Reads the search results out of a Shein search page: the embedded
  # "products":[...] JSON array. Output has the shape of SearchApi's
  # shein_search organic_results, so one converter handles both.
  #
  # Used on pages SearchApi fetched and saved (html_url) but answered with
  # "Shein didn't return any results." although the products were there.
  module SheinPage
    MARKER = %("products":[).b

    def self.organic_results(html, domain: "us.shein.com")
      bytes = html.b
      start = bytes.index(MARKER)
      return [] if start.nil?

      json = json_array(bytes, start + MARKER.bytesize - 1)
      return [] if json.nil?

      JSON.parse(json).each_with_index.map { |product, index| listing(product, index + 1, domain) }
    end

    def self.listing(product, position, domain)
      sale = product["salePrice"] || {}
      retail = product["retailPrice"] || {}
      price = number(sale["usdAmount"])
      original = number(retail["usdAmount"])
      reviews = Integer(product["comment_num"], exception: false)
      {
        "position" => position,
        "product_id" => product["goods_id"],
        "sku" => product["goods_sn"],
        "title" => product["goods_name"],
        "link" => "https://#{domain}/#{product["goods_url_name"]}-p-#{product["goods_id"]}.html",
        "brand" => product.dig("premiumFlagNew", "brand_badge_name"),
        "price" => sale["usdAmountWithSymbol"],
        "extracted_price" => price,
        "price_usd" => sale["usdAmountWithSymbol"],
        "extracted_price_usd" => price,
        "original_price" => (retail["usdAmountWithSymbol"] if original && price && original > price),
        "extracted_original_price" => (original if original && price && original > price),
        # Shein shows "0" for products nobody has rated.
        "rating" => (number(product["comment_rank_average"]) if reviews.to_i.positive?),
        "reviews" => reviews,
        "thumbnail" => product["goods_img"]&.sub(%r{\A//}, "https://"),
        "category_id" => product["cat_id"]
      }.compact
    end

    # The JSON array starting at byte `start`, found by matching brackets
    # outside strings. Works on bytes: indexing a UTF-8 string by character
    # makes Ruby scan from the start each time, and the first try took minutes.
    def self.json_array(bytes, start)
      depth = 0
      in_string = false
      escaped = false
      (start...bytes.bytesize).each do |index|
        byte = bytes.getbyte(index)
        if in_string
          if escaped
            escaped = false
          elsif byte == 92 # backslash
            escaped = true
          elsif byte == 34 # quote
            in_string = false
          end
        elsif byte == 34
          in_string = true
        elsif byte == 91 || byte == 123 # [ {
          depth += 1
        elsif byte == 93 || byte == 125 # ] }
          depth -= 1
          return bytes.byteslice(start..index).force_encoding(Encoding::UTF_8) if depth.zero?
        end
      end
      nil
    end

    def self.number(value)
      Float(value, exception: false)
    end
  end
end
