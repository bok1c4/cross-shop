require "nokogiri"

module CrossShop
  # Parses an eBay search-results page (the "s-card" layout seen in October
  # 2026) into listings shaped like SearchApi's ebay_search organic_results,
  # so the same converter, health rules and comparison work on both.
  #
  # eBay's markup has no meaningful class names for price, shipping or
  # buying format: every row is a generic styled span. Rows are therefore
  # recognised by what they say, not by where they sit, because auction
  # cards have extra rows and position-based parsing shifts by one.
  module EbayParser
    PRICE = /\$([\d,]+\.\d{2})/
    ITEM_ID = %r{/itm/(\d{12})(?:[/?#]|\z)}
    AUCTION = /\A\d+ bids?\b/
    BUYING = /\A(?:Buy It Now|or Best Offer|Best Offer accepted)\z/
    SHIPPING = /delivery|shipping|postage/i
    CONDITION = /\A(?:Brand New|New|Pre-Owned|Used|Open Box|Refurbished|Certified|Seller refurbished|For parts|Parts Only|Excellent|Very Good|Good)\b/

    def self.parse(html)
      document = Nokogiri::HTML(html)
      listings = document.css("li.s-card").filter_map { |card| listing(card) }
      listings.uniq { |item| item["item_id"] }.each_with_index.map { |item, index| {"position" => index + 1, **item} }
    end

    # nil for cards that are not listings ("Shop on eBay" links to /itm/123456).
    def self.listing(card)
      link = card.css("a[href*='/itm/']").map { |anchor| anchor["href"] }.find { |href| href.match?(ITEM_ID) }
      return nil if link.nil?

      item_id = link[ITEM_ID, 1]
      subtitles = card.css(".s-card__subtitle").map { |node| words(node) }.reject(&:empty?)
      condition = subtitles.find { |text| text.match?(CONDITION) }
      item = {
        "item_id" => item_id,
        "title" => words(card.at_css(".s-card__title .su-styled-text.primary")),
        "link" => "https://www.ebay.com/itm/#{item_id}",
        "subtitle" => (subtitles - [condition]).join(" · ").gsub(/\s*·\s*·\s*/, " · ").then { |text| text.empty? ? nil : text },
        "condition" => condition,
        "thumbnail" => card.at_css("img.s-card__image")&.[]("src")
      }
      item.merge!(rows(card), rating(card)).compact
    end

    def self.rows(card)
      result = {"extensions" => []}
      card.css(".s-card__attribute-row").map { |row| words(row) }.reject(&:empty?).each do |text|
        if text.start_with?("$") && !result.key?("price")
          result.merge!(price(text))
        elsif (text.match?(AUCTION) || text.match?(BUYING)) && !result.key?("buying_format")
          result["buying_format"] = text
        elsif text.match?(SHIPPING) && !result.key?("shipping")
          result["shipping"] = text
          result["extracted_shipping"] = shipping_cost(text)
        else
          result["extensions"] << text
        end
      end
      sold = result["extensions"].find { |text| text.match?(/\A[\d,]+\+? sold\z/) }
      result["items_sold"] = sold
      result["extracted_items_sold"] = sold&.delete(",")&.to_i
      result.delete("extensions") if result["extensions"].empty?
      result
    end

    def self.price(text)
      amounts = text.scan(PRICE).flatten.map { |amount| amount.delete(",").to_f }
      if text.include?(" to ") && amounts.size >= 2
        {"price" => text, "is_price_range" => true, "extracted_price_range" => {"from" => amounts[0], "to" => amounts[1]}}
      else
        {"price" => format("$%.2f", amounts[0]), "extracted_price" => amounts[0], "extracted_original_price" => amounts[1]}
      end
    end

    def self.shipping_cost(text)
      return 0.0 if text.start_with?("Free")

      text[/\$([\d,]+\.\d{2})/, 1]&.delete(",")&.to_f
    end

    def self.rating(card)
      text = words(card)
      {
        "rating" => text[/([\d.]+) out of 5 stars/, 1]&.to_f,
        "reviews" => text[/([\d,]+) product ratings?/, 1]&.delete(",")&.to_i
      }
    end

    # The node's text, one space between text nodes. node.text would glue
    # "Time left" and "1d 4h" into "Time left1d 4h".
    def self.words(node)
      return "" if node.nil?

      node.xpath(".//text()").map { |text| text.text.strip }.reject(&:empty?)
        .reject { |text| text == "Opens in a new window or tab" }.join(" ").gsub(/\s+/, " ")
    end
  end
end
