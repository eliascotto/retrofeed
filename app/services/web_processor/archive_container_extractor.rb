class WebProcessor
  module ArchiveContainerExtractor
    # Default container selectors (in priority order)
    # Used when no custom rules exist to focus on main content area
    DEFAULT_CONTAINER_SELECTORS = [
      "main",
      "#content",
      "#main",
      "#main-content",
      ".content",
      ".main",
      ".main-content",
      '[role="main"]'
    ].freeze

    # Finds the default content area using semantic selectors
    #
    # @param doc [Nokogiri::HTML::Document] The HTML document
    # @return [Nokogiri::XML::Node, nil] The content container or nil
    def self.find_container(url, doc)
      rule = SiteProfile.for(url)
      container = rule&.extract_archive_container(doc, url)
      return container unless container.nil?

      DEFAULT_CONTAINER_SELECTORS.each do |selector|
        container = doc.at_css(selector)
        # Only use if it contains article-like content (links with text)
        if container && container.css("a[href]").length >= 2
          return container
        end
      end

      nil
    end

    # Debug-only companion to find_container: returns every container candidate
    # considered, with its link count, so the playground can show why a given
    # container won. Mirrors find_container's selection rule (custom container
    # wins; otherwise the first default selector with >= 2 links) without changing
    # the hot path.
    #
    # @param url [String] The page URL
    # @param doc [Nokogiri::HTML::Document] The HTML document
    # @return [Array<Hash>] Candidates with keys :selector, :link_count, :chosen, :source
    def self.container_candidates(url, doc)
      rule = SiteProfile.for(url)
      custom = rule&.extract_archive_container(doc, url)
      if custom
        [ { selector: "SiteProfile##{rule.class.name.demodulize}",
            link_count: custom.css("a[href]").length,
            chosen: true,
            source: :custom } ]
      else
        chosen_found = false
        DEFAULT_CONTAINER_SELECTORS.map do |selector|
          container = doc.at_css(selector)
          link_count = container ? container.css("a[href]").length : 0
          chosen = !chosen_found && container.present? && link_count >= 2
          chosen_found ||= chosen
          { selector: selector, link_count: link_count, chosen: chosen, source: :default }
        end
      end
    end
  end
end
