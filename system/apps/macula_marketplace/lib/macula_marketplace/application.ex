defmodule MaculaMarketplace.Application do
  @moduledoc """
  Macula Marketplace application.

  Provides a local marketplace client that:
  - Subscribes to DHT PubSub events for artifact updates
  - Maintains a local SQLite index for fast querying
  - Manages UCAN license tokens and revocation cache
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MaculaMarketplace.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:macula_marketplace, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:macula_marketplace, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MaculaMarketplace.PubSub},
      # CRL cache for license revocation tracking
      MaculaMarketplace.Licensing.CRLCache,
      # Mesh subscriber for marketplace events
      MaculaMarketplace.Mesh.Subscriber
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MaculaMarketplace.Supervisor)
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
