require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = true

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Email delivery configuration
  # Use :test to capture emails in ActionMailer::Base.deliveries
  # Use :resend to actually send emails via Resend API (set RESEND_API_KEY in .env)
  if ENV["RESEND_API_KEY"].present?
    config.action_mailer.delivery_method = :resend
    config.action_mailer.raise_delivery_errors = true
  else
    config.action_mailer.delivery_method = :test
    config.action_mailer.raise_delivery_errors = false
  end

  # Make template changes take effect immediately.
  config.action_mailer.perform_caching = false
  config.action_mailer.preview_paths = [ Rails.root.join("test/mailers/previews") ]

  # Set localhost to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "retrofeed.localhost", port: 3006 }
  config.action_mailer.default_options = {
    from: ENV.fetch("MAILER_FROM_EMAIL", "noreply@retrofeed.app")
  }

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Log to STDOUT so job logs appear in foreman output (bin/dev)
  # Set LOG_TO_FILE=1 to also duplicate logs to log/development.log
  if ENV["LOG_TO_FILE"] == "1"
    stdout_logger = ActiveSupport::Logger.new(STDOUT)
    file_logger = ActiveSupport::Logger.new(Rails.root.join("log/development.log").to_s)
    broadcast_logger = ActiveSupport::BroadcastLogger.new(stdout_logger, file_logger)
    config.logger = ActiveSupport::TaggedLogging.new(broadcast_logger)
  else
    config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  end

  # Log level
  config.log_level = :debug

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = false

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Use Solid Queue for background jobs in development
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Enable mock web data in development
  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Allow requests from localhost, retrofeed.localhost, and retrofeed-<number>:<port>
  config.hosts = %w[ retrofeed.localhost localhost 127.0.0.1 ] + [ /^retrofeed-\d+(:\d+)$/, /^192\.168\.0\.\d+(:\d+)?$/ ]
end
