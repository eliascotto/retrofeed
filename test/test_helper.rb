ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

require "rails/test_help"
require "webmock/minitest"
require "turbo/broadcastable/test_helper"

# Allow localhost connections for system tests
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize workers: :number_of_processors

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActiveJob::TestHelper
    include SessionTestHelper
    include Turbo::Broadcastable::TestHelper

    # Replaces a singleton method on `target` with `replacement` for the duration
    # of the block, then restores the original. Drop-in for `Object#stub` from
    # `minitest/mock`, which was removed in Minitest 6 (Ruby 4.0 default).
    def stub_singleton(target, name, replacement)
      sclass = target.singleton_class
      original = target.method(name)
      sclass.define_method(name) do |*args, **kwargs, &block|
        replacement.respond_to?(:call) ? replacement.call(*args, **kwargs, &block) : replacement
      end
      yield
    ensure
      sclass.define_method(name, original) if original
    end

    def use_engine(engine)
      original = Markdown.engine
      Markdown.engine = engine
      yield
    ensure
      Markdown.engine = original
    end

    def stub_archive_request(url, fixture_path)
      if url.nil?
        raise "URL cannot be nil"
      end

      if fixture_path.nil?
        raise "Fixture path cannot be nil"
      end

      html_content = File.read(fixture_path)
      stub_request(:get, url).to_return(body: html_content, status: 200)

      # Also stub index page request (same content as archive for simplicity)
      uri = URI.parse(url)
      origin = uri.origin
      stub_request(:get, origin).to_return(body: html_content, status: 200) unless origin == url
      stub_request(:get, "#{origin}/").to_return(body: html_content, status: 200)

      # Stub any favicon requests that might be extracted from the archive HTML
      # Use a regex to match any favicon-like request for this domain
      stub_request(:get, /#{Regexp.escape(uri.host)}.*\/(favicon|icon|apple-touch-icon).*/).to_return(status: 404)
    end

    # Records `deliver_now` invocations and fails `verify` if it was never called.
    # Stand-in for the `Minitest::Mock.new + expect(:deliver_now, ...) + verify`
    # pattern used by the mailer-job tests. Intentionally does not define `call`,
    # so `stub_singleton` won't mistake it for a callable replacement.
    class DeliverExpectation
      def initialize
        @count = 0
      end

      def deliver_now(*, **, &)
        @count += 1
        true
      end

      def verify
        @count > 0 || raise(Minitest::Assertion, "expected deliver_now to be called at least once")
      end
    end
  end
end

class ActionDispatch::IntegrationTest
  def json_response
    @json_response ||= JSON.parse(response.body)
  end
end
