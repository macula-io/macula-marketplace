defmodule MaculaMarketplace.Licensing.CRLCache do
  @moduledoc """
  Certificate Revocation List (CRL) cache for UCAN tokens.

  Maintains a local cache of revoked license tokens. The cache is
  populated from `io.macula.marketplace.license_revoked` events
  received via DHT PubSub.

  ## Cache Persistence

  Revocations are stored in ETS for fast lookup and persisted to
  SQLite for durability across restarts.

  ## TTL and Refresh

  - Default TTL: 24 hours
  - Grace period: 7 days after revocation (time for nodes to sync)
  - Cache refreshes on mesh reconnection via heartbeat
  """

  use GenServer
  require Logger

  @table_name :ucan_crl_cache
  @default_ttl_hours 24

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a license token is revoked.
  """
  def revoked?(token_cid) when is_binary(token_cid) do
    case :ets.lookup(@table_name, token_cid) do
      [{^token_cid, _revoked_at}] -> true
      [] -> false
    end
  end

  @doc """
  Add a revocation to the cache.
  """
  def add_revocation(token_cid, revoked_at) do
    GenServer.cast(__MODULE__, {:add_revocation, token_cid, revoked_at})
  end

  @doc """
  Get all revocations (for debugging/admin).
  """
  def list_revocations do
    :ets.tab2list(@table_name)
  end

  @doc """
  Get the count of cached revocations.
  """
  def count do
    :ets.info(@table_name, :size)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

    # Load persisted revocations from SQLite
    load_persisted_revocations()

    # Schedule periodic cleanup of old revocations
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:add_revocation, token_cid, revoked_at}, state) do
    # Add to ETS cache
    :ets.insert(@table_name, {token_cid, revoked_at})

    # Persist to SQLite
    persist_revocation(token_cid, revoked_at)

    Logger.debug("[CRLCache] Added revocation: #{token_cid}")

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_revocations()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private helpers

  defp load_persisted_revocations do
    # Load from SQLite revocations table
    case MaculaMarketplace.Repo.query("SELECT token_cid, revoked_at FROM license_revocations") do
      {:ok, %{rows: rows}} ->
        Enum.each(rows, fn [cid, revoked_at] ->
          :ets.insert(@table_name, {cid, revoked_at})
        end)

        Logger.info("[CRLCache] Loaded #{length(rows)} revocations from database")

      {:error, _reason} ->
        # Table might not exist yet, that's fine
        Logger.debug("[CRLCache] No existing revocations to load")
    end
  end

  defp persist_revocation(token_cid, revoked_at) do
    sql = """
    INSERT INTO license_revocations (token_cid, revoked_at, inserted_at)
    VALUES (?1, ?2, ?3)
    ON CONFLICT (token_cid) DO NOTHING
    """

    now = DateTime.utc_now() |> DateTime.to_naive()

    case MaculaMarketplace.Repo.query(sql, [token_cid, revoked_at, now]) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.error("[CRLCache] Failed to persist: #{inspect(reason)}")
    end
  end

  defp cleanup_old_revocations do
    # Remove revocations older than grace period (7 days past TTL)
    cutoff = DateTime.utc_now() |> DateTime.add(-(@default_ttl_hours + 168), :hour)

    :ets.foldl(
      fn {cid, revoked_at}, acc ->
        case DateTime.from_iso8601(revoked_at) do
          {:ok, dt, _} when dt < cutoff ->
            :ets.delete(@table_name, cid)
            acc + 1

          _ ->
            acc
        end
      end,
      0,
      @table_name
    )
  end

  defp schedule_cleanup do
    # Run cleanup every hour
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end
end
