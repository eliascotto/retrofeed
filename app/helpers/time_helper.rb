module TimeHelper
  # Shorten the time ago string to a more readable format
  def short_time_ago_in_words(time)
    distance = time_ago_in_words(time)

    distance
      .gsub(/about |over |almost |less than /, "")
      .gsub(/(\d+)\s*seconds?/, '\1s')
      .gsub(/(\d+)\s*minutes?/, '\1m')
      .gsub(/(\d+)\s*hours?/, '\1h')
      .gsub(/(\d+)\s*days?/, '\1d')
      .gsub(/(\d+)\s*weeks?/, '\1w')
      .gsub(/(\d+)\s*months?/, '\1mo')
      .gsub(/(\d+)\s*years?/, '\1y')
  end
end
