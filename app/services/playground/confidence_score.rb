class Playground::ConfidenceScore
  MIN_LINKS_FOR_CHECK = 8
  COVERAGE_FLOOR = 0.3

  def initialize(
    base_score: 0,
    method: nil,
    articles: [],
    archive_domain: nil,
    available_link_count: 0
  )
    @base_score = base_score
    @method = method
    @articles = articles
    @archive_domain = archive_domain
    @available_link_count = available_link_count
  end

  # Calculates adjusted confidence score based on article domain match
  #
  # The initial confidence score is based on archive detection (link patterns).
  # This method adjusts it based on actual article extraction results.
  #
  # @return [Array<Float, Hash>] Adjusted score and breakdown
  def calculate
    validation = self.validate
    breakdown = {
      base_score: @base_score,
      base_reason: "Detection method: #{@method}",
      adjustments: []
    }

    # If no articles were extracted, reduce confidence significantly
    if validation[:total] == 0
      adjustment = -0.5
      breakdown[:adjustments] << {
        factor: "No articles extracted",
        impact: adjustment
      }
      final_score = [ @base_score + adjustment, 0.0 ].max
      breakdown[:final_score] = final_score
      return [ final_score, breakdown ]
    end

    # Calculate penalty based on external article percentage
    match_pct = validation[:match_percentage]

    if match_pct < 0.5
      # Less than 50% internal articles - major penalty
      adjustment = -0.6 * (1.0 - match_pct)
      breakdown[:adjustments] << {
        factor: "Low domain match (#{(match_pct * 100).round}% internal)",
        impact: adjustment.round(2)
      }
    elsif match_pct < 0.8
      # 50-80% internal - moderate penalty
      adjustment = -0.3 * (1.0 - match_pct)
      breakdown[:adjustments] << {
        factor: "Moderate domain match (#{(match_pct * 100).round}% internal)",
        impact: adjustment.round(2)
      }
    elsif match_pct < 1.0
      # 80-100% internal - minor penalty
      adjustment = -0.1 * (1.0 - match_pct)
      breakdown[:adjustments] << {
        factor: "Good domain match (#{(match_pct * 100).round}% internal)",
        impact: adjustment.round(2)
      }
    else
      adjustment = 0.0
      breakdown[:adjustments] << {
        factor: "Perfect domain match (100% internal)",
        impact: 0.0
      }
    end

    # Bonus for having many articles
    if validation[:internal] >= 10
      bonus = 0.05
      adjustment += bonus
      breakdown[:adjustments] << {
        factor: "Many internal articles (#{validation[:internal]})",
        impact: bonus
      }
    end

    # Extraction collapsed: far fewer articles kept than article-like links present
    # on the page signals a broken/degenerate extraction (e.g. one-link-per-section).
    coverage = @available_link_count.positive? ? @articles.count.to_f / @available_link_count : 1.0
    if @available_link_count >= MIN_LINKS_FOR_CHECK && coverage < COVERAGE_FLOOR
      adjustment = -0.5
      breakdown[:adjustments] << {
        factor: "Low extraction coverage (#{@articles.count}/#{@available_link_count} links kept)",
        impact: adjustment
      }
    end

    final_score = [ [ @base_score + adjustment, 0.0 ].max, 1.0 ].min
    breakdown[:final_score] = final_score.round(2)

    [ final_score.round(2), breakdown, validation ]
  end

  # Validates extracted articles by checking how many belong to the archive domain
  #
  # @return [Hash] Validation result with counts and percentage
  def validate
    return { total: 0, internal: 0, external: 0, match_percentage: 0.0 } if @articles.empty?

    internal_count = 0
    external_count = 0

    @articles.each do |article|
      next unless article[:url].present?

      article_domain = UrlUtils.extract_domain(article[:url])
      if article_domain == @archive_domain
        internal_count += 1
      else
        external_count += 1
      end
    end

    total = internal_count + external_count
    match_percentage = total > 0 ? (internal_count.to_f / total) : 0.0

    {
      total: total,
      internal: internal_count,
      external: external_count,
      match_percentage: match_percentage
    }
  end
end
