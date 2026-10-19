class WebProcessor
  module AuthorExtractor
    extend self

    # Extracts the author from the given URL, results, and document.
    # Priority:
    # 1. Custom rule for the host
    # 2. Authors from results
    #
    # @param url [String, nil] The URL of the page
    # @param doc [Nokogiri::HTML::Document, nil] The parsed HTML document
    # @param results [Hash] The results hash containing authors
    # @return [String, nil] The extracted author or nil if not found
    def extract_author(url, doc, results)
      if url
        host = UrlUtils.extract_domain(url)
        rule = SiteProfile.for(host)
        if rule
          author = rule.extract_author(doc, url)
          return author if author.present?
        end
      end

      if results && results[:authors].present?
        return results[:authors].first
      end

      nil
    end
  end
end
