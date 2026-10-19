# Class usefull to store the trace of an extractor run, for playground use.
class ExtractionTrace
  attr_accessor :phase, :phase_detail, :strategy, :base_url, :base_path,
    :final_url, :containers_count, :dropped_urls, :article_like_links,
    :phase_results, :container_candidates

  def initialize(strategy:,
                 base_url:,
                 phase: nil,
                 base_path: nil,
                 phase_detail: nil,
                 final_url: nil,
                 containers_count: nil,
                 dropped_urls: nil,
                 article_like_links: nil,
                 phase_results: nil,
                 container_candidates: nil)
    @phase = phase # The phase of the extractor run
    @phase_detail = phase_detail # Extra details about the phase
    @strategy = strategy  # Extractor strategy used
    @base_url = base_url
    @base_path = base_path
    @final_url = final_url
    @containers_count = containers_count
    @dropped_urls = dropped_urls
    @article_like_links = article_like_links
    # Debug-only "what-if": per-phase would-be result counts and the candidate
    # containers ArchiveContainerExtractor considered. Populated only in debug mode.
    @phase_results = phase_results
    @container_candidates = container_candidates
  end
end
