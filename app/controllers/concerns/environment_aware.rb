module EnvironmentAware
  extend ActiveSupport::Concern

  included do
    helper_method :development?
    helper_method :production?
    helper_method :env_local?
    helper_method :ensure_local
  end

  private
    def development?
      Rails.env.development?
    end

    def production?
      Rails.env.production?
    end

    def env_local?
      Rails.env.local?
    end

    def ensure_local
      unless env_local?
        render plain: "This feature is only available in local environment!", status: :forbidden
      end
    end
end
