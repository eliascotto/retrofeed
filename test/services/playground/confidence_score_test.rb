require "test_helper"

class Playground::ConfidenceScoreTest < ActiveSupport::TestCase
  test "collapsed extraction yields low confidence despite 100% domain match" do
    articles = 3.times.map { |i| { url: "https://x.com/blog/p#{i}" } }
    score, breakdown = Playground::ConfidenceScore.new(
      base_score: 0.65, method: "link_analysis",
      articles: articles, archive_domain: "x.com", available_link_count: 246
    ).calculate

    assert score < 0.4, "expected penalized score, got #{score}"
    assert breakdown[:adjustments].any? { |a| a[:factor].include?("coverage") }
  end

  test "full-coverage extraction keeps healthy confidence" do
    articles = 50.times.map { |i| { url: "https://x.com/blog/p#{i}" } }
    score, _ = Playground::ConfidenceScore.new(
      base_score: 0.65, method: "link_analysis",
      articles: articles, archive_domain: "x.com", available_link_count: 50
    ).calculate

    assert score >= 0.65
  end
end
