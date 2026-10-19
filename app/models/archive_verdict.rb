# Value object capturing why contains_valid_archive? accepted or rejected a page.
#
# Built by WebProcessor.contains_valid_archive_with_reason? so the playground can
# explain a validation failure: which of the three checks passed and the link
# counts involved. passed_check is the first check that met the threshold
# (:article_like, :date_paths, or :pattern), or nil when the page is not an archive.
class ArchiveVerdict
  attr_reader :valid, :base_url, :min_links,
    :local_links_count, :candidate_paths_count,
    :article_like_count, :date_paths_count,
    :top_pattern, :top_pattern_count, :passed_check

  def initialize(base_url:,
                 min_links:,
                 valid: false,
                 local_links_count: 0,
                 candidate_paths_count: 0,
                 article_like_count: 0,
                 date_paths_count: 0,
                 top_pattern: nil,
                 top_pattern_count: 0,
                 passed_check: nil)
    @base_url = base_url
    @min_links = min_links
    @valid = valid
    @local_links_count = local_links_count
    @candidate_paths_count = candidate_paths_count
    @article_like_count = article_like_count
    @date_paths_count = date_paths_count
    @top_pattern = top_pattern
    @top_pattern_count = top_pattern_count
    @passed_check = passed_check
  end

  def valid?
    @valid
  end
end
