# HTTP client for the Node.js extractor server with connection pooling.
#
# Uses thread-local persistent HTTP connections to avoid TCP handshake overhead
# while remaining thread-safe. Each thread gets its own connection that is reused
# for subsequent requests within that thread.
#
# Configuration:
#   EXTRACTOR_HOST - Host of the extractor server (default: localhost)
#   EXTRACTOR_PORT - Port of the extractor server (default: 3880)
#
# Usage:
#   result = ExtractorClient.extract(url: "https://example.com")
#   result = ExtractorClient.extract(url: "https://example.com", html: "<html>...")
#
class ExtractorClient
  class ExtractorError < StandardError; end
  class ConnectionError < ExtractorError; end
  class TimeoutError < ExtractorError; end

  # Default configuration
  DEFAULT_HOST = "localhost".freeze
  DEFAULT_PORT = 3880
  REQUEST_TIMEOUT = 30 # seconds
  OPEN_TIMEOUT = 5 # seconds

  # Thread-local key for storing HTTP connection
  THREAD_LOCAL_KEY = :extractor_client_http

  class << self
    # Extract content from a single URL or HTML
    #
    # @param url [String] The URL of the article
    # @param html [String, nil] Optional pre-fetched HTML content
    # @return [Hash] Extracted content with :contentHtml, :contentMd, etc. or :error
    def extract(url:, html: nil)
      payload = { url: url }
      payload[:html] = html if html.present?

      post_json("/extract", payload)
    end

    # Check if the extractor server is healthy
    #
    # @return [Hash] Health status with :status, :uptime, :memory
    def health
      get_json("/health")
    end

    # Check if the extractor server is available
    #
    # @return [Boolean] true if server responds to health check
    def available?
      health[:status] == "ok"
    rescue ExtractorError
      false
    end

    # Reset the connection for the current thread (useful for testing or after configuration change)
    def reset_connection!
      http = Thread.current[THREAD_LOCAL_KEY]
      if http
        http.finish if http.started?
        Thread.current[THREAD_LOCAL_KEY] = nil
      end
    end

    # Reset connections for all threads (for testing only - not thread-safe for production use)
    def reset_all_connections!
      reset_connection!
    end

    private

    def host
      ENV.fetch("EXTRACTOR_HOST", DEFAULT_HOST)
    end

    def port
      ENV.fetch("EXTRACTOR_PORT", DEFAULT_PORT).to_i
    end

    # Get or create a persistent HTTP connection for the current thread.
    # Thread-safe because each thread has its own connection stored in thread-local storage.
    def connection
      http = Thread.current[THREAD_LOCAL_KEY]

      if http.nil? || !http.started?
        http = Net::HTTP.new(host, port)
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = REQUEST_TIMEOUT
        http.keep_alive_timeout = 30
        http.start
        Thread.current[THREAD_LOCAL_KEY] = http
      end

      http
    end

    # Make a POST request with JSON body
    def post_json(path, body)
      request = Net::HTTP::Post.new(path)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = body.to_json

      execute_request(request)
    end

    # Make a GET request
    def get_json(path)
      request = Net::HTTP::Get.new(path)
      request["Accept"] = "application/json"

      execute_request(request)
    end

    # Execute request with automatic reconnection on failure
    def execute_request(request)
      response = connection.request(request)
      parse_response(response)
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, IOError => e
      # Connection lost, reset and retry once
      reset_connection!
      begin
        response = connection.request(request)
        parse_response(response)
      rescue Errno::ECONNREFUSED => e
        raise ConnectionError, "Extractor server not available at #{host}:#{port}: #{e.message}"
      end
    rescue Net::OpenTimeout => e
      raise TimeoutError, "Connection to extractor server timed out: #{e.message}"
    rescue Net::ReadTimeout => e
      raise TimeoutError, "Extractor server response timed out: #{e.message}"
    end

    def parse_response(response)
      case response.code.to_i
      when 200
        JSON.parse(response.body, symbolize_names: true)
      when 400
        error_body = JSON.parse(response.body, symbolize_names: true) rescue {}
        { error: error_body[:error] || "Bad request" }
      when 413
        { error: "Request body too large" }
      when 404
        { error: "Endpoint not found" }
      else
        { error: "Extractor returned HTTP #{response.code}" }
      end
    rescue JSON::ParserError => e
      { error: "Invalid JSON response: #{e.message}" }
    end
  end
end
