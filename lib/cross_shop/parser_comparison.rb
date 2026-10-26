module CrossShop
  # Field-by-field comparison of our eBay parser with SearchApi's output,
  # paired by item ID. The pages were saved at another time and from another
  # place than SearchApi's fetch, so only listings present in both are
  # compared, and the rest are reported rather than counted as differences.
  module ParserComparison
    FIELDS = %w[
      title subtitle condition extracted_price extracted_price_range shipping extracted_shipping is_sponsored
    ].freeze

    Result = Data.define(:paired_ids, :only_ours, :only_theirs, :fields)
    Field = Data.define(:counts, :examples)

    def self.compare(ours:, theirs:, fields: FIELDS)
      ours_by_id = ours.to_h { |item| [item["item_id"], item] }
      theirs_by_id = theirs.to_h { |item| [item["item_id"], item] }
      paired = ours_by_id.keys & theirs_by_id.keys

      Result.new(
        paired_ids: paired,
        only_ours: ours_by_id.keys - theirs_by_id.keys,
        only_theirs: theirs_by_id.keys - ours_by_id.keys,
        fields: fields.to_h { |field| [field, compare_field(field, paired, ours_by_id, theirs_by_id)] }
      )
    end

    def self.compare_field(field, ids, ours, theirs)
      counts = {agree: 0, differ: 0, only_ours: 0, only_theirs: 0}
      examples = []
      ids.each do |id|
        mine = ours[id][field]
        theirs_value = theirs[id][field]
        next if mine.nil? && theirs_value.nil?

        if mine.nil?
          counts[:only_theirs] += 1
        elsif theirs_value.nil?
          counts[:only_ours] += 1
        elsif same?(mine, theirs_value)
          counts[:agree] += 1
        else
          counts[:differ] += 1
          examples << [id, mine, theirs_value] if examples.size < 5
        end
      end
      Field.new(counts:, examples:)
    end

    def self.same?(a, b)
      if a.is_a?(Numeric) && b.is_a?(Numeric)
        (a - b).abs < 0.005
      elsif a.is_a?(String) && b.is_a?(String)
        a.split.join(" ") == b.split.join(" ")
      else
        a == b
      end
    end
  end
end
