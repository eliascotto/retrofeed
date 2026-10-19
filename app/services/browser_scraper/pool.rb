class BrowserScraper
  module Pool
    class << self
      # Executes a block of code with a browser scraper, ensuring proper cleanup
      # If the scraper crashes or exhausts its session, it will be discarded
      # Otherwise, the scraper will be reset for reuse
      def with_scraper(options = {}, &block)
        scraper = checkout(options)
        yield scraper
      ensure
        if scraper&.crashed? || scraper&.exhausted?
          discard(scraper)
        else
          scraper.reset
        end
      end

      # Shuts down the browser scraper for the current thread
      def shutdown_current_thread
        scraper = Thread.current[:browser_scraper]
        scraper.quit if scraper
        Thread.current[:browser_scraper] = nil
      end

      private
        def checkout(options)
          scraper = Thread.current[:browser_scraper]
          return scraper if scraper && !scraper.crashed? && !scraper.exhausted?

          discard(scraper)
          Thread.current[:browser_scraper] = BrowserScraper.new(options)
        end

        def discard(scraper)
          scraper&.force_cleanup

          if Thread.current[:browser_scraper] == scraper
            Thread.current[:browser_scraper] = nil
          end
        end
    end
  end
end
