defmodule MaculaMarketplaceWeb.Router do
  use MaculaMarketplaceWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MaculaMarketplaceWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MaculaMarketplaceWeb do
    pipe_through :browser

    # Redirect home to browse
    get "/", PageController, :home

    # LiveView routes
    live_session :default, layout: {MaculaMarketplaceWeb.Layouts, :app} do
      live "/browse", BrowseLive
      live "/artifacts/:artifact_id/:version", ArtifactLive
      live "/publish", PublishLive
      live "/licenses", LicensesLive
    end
  end

  # API for mesh RPC integration
  scope "/api", MaculaMarketplaceWeb.Api do
    pipe_through :api

    # Marketplace search API (for mesh RPC proxying)
    get "/artifacts", ArtifactController, :index
    get "/artifacts/:artifact_id/:version", ArtifactController, :show
    post "/artifacts", ArtifactController, :create
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:macula_marketplace_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MaculaMarketplaceWeb.Telemetry
    end
  end
end
