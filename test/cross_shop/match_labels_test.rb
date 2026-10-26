require "test_helper"
require "tmpdir"
require "cross_shop/match_labels"

class MatchLabelsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "labels.csv")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def row(amazon_id, ebay_id, tier: "title")
    {"query" => "q", "tier" => tier, "score" => "0.6", "amazon_id" => amazon_id, "amazon_title" => "t",
     "amazon_price" => "100.0", "other_store" => "ebay", "other_id" => ebay_id, "other_title" => "t",
     "other_price" => "90.0", "other_condition" => "new"}
  end

  # Hand labels are the expensive part. Regenerating the file must keep them.
  def test_regenerating_keeps_existing_labels_and_notes
    labels = CrossShop::MatchLabels.new(@path)
    labels.write([row("A1", "E1"), row("A2", "E2")])
    table = CSV.read(@path, headers: true, encoding: "UTF-8")
    table.each { |r| r["label"], r["note"] = "y", "same colorway" if r["other_id"] == "E1" }
    File.write(@path, table.to_csv)

    labels.write([row("A1", "E1"), row("A3", "E3")])

    rows = labels.read
    assert_equal %w[y], rows.select { |r| r["other_id"] == "E1" }.map { |r| r["label"] }
    assert_equal "same colorway", rows.find { |r| r["other_id"] == "E1" }["note"]
    assert_equal %w[E1 E3], rows.map { |r| r["other_id"] }
  end

  def test_precision_counts_only_labelled_rows_per_tier
    rows = [
      row("A1", "E1", tier: "style_code").merge("label" => "y"),
      row("A2", "E2").merge("label" => "y"),
      row("A3", "E3").merge("label" => "n"),
      row("A4", "E4").merge("label" => "")
    ]

    report = CrossShop::MatchLabels.precision(rows)

    assert_equal({labelled: 1, correct: 1}, report.fetch("style_code"))
    assert_equal({labelled: 2, correct: 1}, report.fetch("title"))
    assert_equal({labelled: 3, correct: 2}, report.fetch("all"))
  end

  def test_a_label_other_than_y_or_n_fails_loudly
    rows = [row("A1", "E1").merge("label" => "yes")]

    assert_raises(ArgumentError) { CrossShop::MatchLabels.precision(rows) }
  end
end
