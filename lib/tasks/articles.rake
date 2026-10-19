namespace :articles do
  desc "Backfill missing content for articles without content_html or content_md"
  task backfill_content: :environment do
    articles = Article.where(content_html: [ nil, "" ]).where(content_md: [ nil, "" ])
    total = articles.count

    if total == 0
      puts "No articles need content backfilling."
      exit
    end

    puts "Found #{total} articles without content."
    puts "Starting backfill process..."
    puts ""

    success_count = 0
    failed_count = 0
    permanent_error_count = 0

    articles.find_each(batch_size: 10).with_index do |article, index|
      print "[#{index + 1}/#{total}] Processing article #{article.id}: #{article.url}... "
      STDOUT.flush

      result = WebProcessor.extract_article_content(article.url)

      if result && result[:content]
        content = result[:content]
        raw_title = content[:title] || article.title
        cleaned_title = WebProcessor::TitleCleaner.clean_article_title(raw_title, article)
        article.update!(
          title: cleaned_title,
          content_html: content[:content_html],
          content_md: content[:content_md],
          word_count: content[:word_count],
          publication_date: content[:published] || article.publication_date
        )
        success_count += 1
        puts "✓ Success (#{content[:word_count] || 0} words)"
      elsif result && result[:error]
        # Check if it's a permanent error (HTTP 4xx)
        if result[:error].match?(/HTTP error! status: (40[0-8]|41[0-8]|451)/)
          permanent_error_count += 1
          puts "✗ Permanent error (#{result[:error]})"
        else
          failed_count += 1
          puts "✗ Failed (#{result[:error]})"
        end
      else
        failed_count += 1
        puts "✗ Failed (unknown error)"
      end

      # Small delay to avoid overwhelming the server
      sleep 0.5
    end

    puts ""
    puts "=" * 60
    puts "Backfill Summary:"
    puts "  Total processed: #{total}"
    puts "  Successfully backfilled: #{success_count}"
    puts "  Permanent errors (404, etc.): #{permanent_error_count}"
    puts "  Transient failures: #{failed_count}"
    puts "=" * 60
  end

  desc "Show statistics about articles with missing content"
  task stats: :environment do
    total = Article.count
    without_content = Article.where(content_html: [ nil, "" ]).where(content_md: [ nil, "" ]).count
    with_content = total - without_content

    puts "Article Statistics:"
    puts "  Total articles: #{total}"
    puts "  With content: #{with_content} (#{(with_content.to_f / total * 100).round(1)}%)"
    puts "  Without content: #{without_content} (#{(without_content.to_f / total * 100).round(1)}%)"

    if without_content > 0
      puts ""
      puts "Sample articles without content:"
      Article.where(content_html: [ nil, "" ]).where(content_md: [ nil, "" ]).limit(10).each do |article|
        puts "  - ID #{article.id}: #{article.url}"
      end
    end
  end

  desc "List articles by website"
  task :list, [ :website_id ] => :environment do |t, args|
    website_id = args[:website_id]
    website = Website.find(website_id)

    unless website
      puts "Website with ID #{website_id} not found"
      return
    end

    articles = website.articles.order(created_at: :desc)

    puts "Articles for website #{website_id}:"
    puts "=" * 60
    articles.each do |article|
      puts "  - #{article.id}: #{article.title} (#{article.url})"
    end
    puts "=" * 60
  end

  desc "Remove article by id"
  task :remove, [ :article_id ] => :environment do |t, args|
    article_id = args[:article_id]
    article = Article.find(article_id)

    unless article
      puts "Article with ID #{article_id} not found"
      return
    end

    article.destroy
    puts "Article removed correctly"
  end

  desc "Remove article content by id"
  task :reset, [ :article_id ] => :environment do |t, args|
    article_id = args[:article_id]
    article = Article.find(article_id)

    unless article
      puts "Article with ID #{article_id} not found"
      return
    end

    article.update!(
      content_html: "",
      content_md: "",
      content_hash: "",
      content_fetch_failed_at: nil,
      failure_reason: nil,
      publication_date: nil,
      word_count: nil,
      status: "pending",
    )
    puts "Article reset correctly"
  end

  desc "Set article as pending"
  task :set_pending, [ :article_id ] => :environment do |t, args|
    article_id = args[:article_id]
    article = Article.find(article_id)

    unless article
      puts "Article with ID #{article_id} not found"
      return
    end

    article.update!(status: :pending)
    puts "Article #{article_id} set to pending"
  end
end
