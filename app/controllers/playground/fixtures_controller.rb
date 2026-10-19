class Playground::FixturesController < ApplicationController
  layout "minimal"

  # GET /playground/fixtures
  # List all cached fixtures
  def index
    @domains = Playground::FixtureCache.list_domains
    @fixtures = Playground::FixtureCache.list_fixtures(params[:for_domain])
    @stats = Playground::FixtureCache.stats
    @selected_domain = params[:for_domain]
  end

  # DELETE /playground/fixtures/:id
  # Clear a specific fixture by URL
  def destroy
    url = params[:url]

    if url.present? && Playground::FixtureCache.clear_fixture(url)
      flash[:notice] = "Cleared fixture for #{url}"
    else
      flash[:error] = "Fixture not found"
    end

    redirect_back(fallback_location: playground_fixtures_path)
  end

  # DELETE /playground/fixtures/destroy_all
  # Clear a single fixture by URL, all fixtures for a domain, or all fixtures
  def destroy_all
    if params[:url].present?
      if Playground::FixtureCache.clear_fixture(params[:url])
        flash[:notice] = "Cleared fixture for #{params[:url]}"
      else
        flash[:error] = "Fixture not found"
      end
    elsif params[:domain].present?
      count = Playground::FixtureCache.clear_domain(params[:domain])
      flash[:notice] = "Cleared #{count} fixtures for #{params[:domain]}"
    else
      count = Playground::FixtureCache.clear_all_fixtures
      flash[:notice] = "Cleared all #{count} fixtures"
    end

    redirect_back(fallback_location: playground_fixtures_path)
  end
end
