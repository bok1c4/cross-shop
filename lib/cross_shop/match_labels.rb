require "csv"
require "fileutils"

module CrossShop
  # The hand-labelled match sample: one CSV row per pair the grouping uses.
  # `label` is y (same product: same model and colorway) or n; `note` is free.
  class MatchLabels
    COLUMNS = %w[
      query tier score amazon_id amazon_title amazon_price amazon_link
      other_store other_id other_title other_price other_condition other_link label note
    ].freeze

    def initialize(path)
      @path = path
    end

    def read
      return [] unless File.exist?(@path)

      CSV.read(@path, headers: true, encoding: "UTF-8").map(&:to_h)
    end

    # Writes the given pairs, keeping label and note for pairs the file
    # already had. Pairs no longer produced are dropped with their labels.
    def write(rows)
      previous = read.to_h { |row| [key(row), row] }
      FileUtils.mkdir_p(File.dirname(@path))
      CSV.open(@path, "w", encoding: "UTF-8") do |csv|
        csv << COLUMNS
        rows.each do |row|
          kept = previous.fetch(key(row), {})
          merged = row.merge("label" => kept["label"], "note" => kept["note"])
          csv << COLUMNS.map { |column| merged[column] }
        end
      end
    end

    # Precision per tier and overall, over labelled rows only:
    # {"title" => {labelled: 2, correct: 1}, ..., "all" => {...}}
    def self.precision(rows)
      labelled = rows.reject { |row| row["label"].to_s.strip.empty? }
      unknown = labelled.map { |row| row["label"].strip }.uniq - %w[y n]
      raise ArgumentError, "labels must be y or n, found #{unknown.inspect}" unless unknown.empty?

      count = ->(subset) { {labelled: subset.size, correct: subset.count { |row| row["label"].strip == "y" }} }
      labelled.group_by { |row| row["tier"] }.transform_values(&count).merge("all" => count.call(labelled))
    end

    private

    def key(row)
      [row["amazon_id"], row["other_store"], row["other_id"]]
    end
  end
end
