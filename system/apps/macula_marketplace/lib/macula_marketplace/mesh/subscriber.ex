defmodule MaculaMarketplace.Mesh.Subscriber do
  @moduledoc """
  Subscribe to marketplace events from the Macula mesh DHT PubSub.

  This GenServer subscribes to `io.macula.marketplace.*` topics and
  updates the local SQLite index as events arrive. It also broadcasts
  updates to Phoenix.PubSub for LiveView reactivity.

  ## Topics Subscribed

  - `io.macula.marketplace.artifact_published`
  - `io.macula.marketplace.artifact_updated`
  - `io.macula.marketplace.artifact_deprecated`
  - `io.macula.marketplace.artifact_revoked`
  - `io.macula.marketplace.license_revoked`

  ## State Refresh

  When starting or reconnecting after being offline, the subscriber
  can request a state refresh from any marketplace service via the
  `io.macula.marketplace.refresh` RPC procedure.
  """

  use GenServer
  require Logger

  alias MaculaMarketplace.Artifacts.Index

  @topics [
    "io.macula.marketplace.artifact_published",
    "io.macula.marketplace.artifact_updated",
    "io.macula.marketplace.artifact_deprecated",
    "io.macula.marketplace.artifact_revoked",
    "io.macula.marketplace.license_revoked"
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Request a state refresh from the mesh.

  This replays all marketplace events since the given timestamp,
  allowing the local index to be rebuilt.
  """
  def request_refresh(from_timestamp \\ nil) do
    GenServer.call(__MODULE__, {:request_refresh, from_timestamp})
  end

  @doc """
  Check if the subscriber is connected to the mesh.
  """
  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Check if mesh is available
    mesh_enabled = Application.get_env(:macula_marketplace, :mesh_enabled, true)

    state = %{
      subscribed: false,
      mesh_enabled: mesh_enabled,
      last_event_at: nil,
      events_processed: 0
    }

    if mesh_enabled do
      # Subscribe to topics after a short delay to allow mesh to connect
      Process.send_after(self(), :subscribe, 1000)
    else
      Logger.info("[Marketplace.Subscriber] Mesh disabled, running in offline mode")
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    case subscribe_to_topics() do
      :ok ->
        Logger.info("[Marketplace.Subscriber] Subscribed to marketplace topics")
        {:noreply, %{state | subscribed: true}}

      {:error, reason} ->
        Logger.warning(
          "[Marketplace.Subscriber] Failed to subscribe: #{inspect(reason)}, retrying..."
        )

        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:macula_pubsub, topic, payload}, state) do
    case Jason.decode(payload) do
      {:ok, event} ->
        handle_event(topic, event)
        new_state = %{state | last_event_at: DateTime.utc_now(), events_processed: state.events_processed + 1}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[Marketplace.Subscriber] Failed to decode event: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.subscribed and state.mesh_enabled, state}
  end

  @impl true
  def handle_call({:request_refresh, from_timestamp}, _from, state) do
    result = do_request_refresh(from_timestamp)
    {:reply, result, state}
  end

  # Event Handlers

  defp handle_event("io.macula.marketplace.artifact_published", %{"manifest" => manifest}) do
    Logger.info("[Marketplace] Artifact published: #{manifest["artifact_id"]} v#{manifest["version"]}")

    case Index.upsert(normalize_manifest(manifest)) do
      {:ok, artifact} ->
        broadcast_update({:artifact_published, artifact})

      {:error, changeset} ->
        Logger.error("[Marketplace] Failed to index artifact: #{inspect(changeset.errors)}")
    end
  end

  defp handle_event("io.macula.marketplace.artifact_updated", %{"manifest" => manifest}) do
    Logger.info("[Marketplace] Artifact updated: #{manifest["artifact_id"]} v#{manifest["version"]}")

    case Index.upsert(normalize_manifest(manifest)) do
      {:ok, artifact} ->
        broadcast_update({:artifact_updated, artifact})

      {:error, changeset} ->
        Logger.error("[Marketplace] Failed to update artifact: #{inspect(changeset.errors)}")
    end
  end

  defp handle_event("io.macula.marketplace.artifact_deprecated", event) do
    artifact_id = event["artifact_id"]
    version = event["version"]
    reason = event["reason"]
    replacement_id = event["replacement_id"]

    Logger.info("[Marketplace] Artifact deprecated: #{artifact_id} v#{version}")

    case Index.mark_deprecated(artifact_id, version, reason, replacement_id) do
      {:ok, artifact} ->
        broadcast_update({:artifact_deprecated, artifact})

      {:error, reason} ->
        Logger.error("[Marketplace] Failed to deprecate artifact: #{inspect(reason)}")
    end
  end

  defp handle_event("io.macula.marketplace.artifact_revoked", event) do
    artifact_id = event["artifact_id"]
    version = event["version"]
    reason = event["reason"]

    Logger.warning("[Marketplace] Artifact revoked: #{artifact_id} v#{version} - #{reason}")

    case Index.mark_revoked(artifact_id, version, reason) do
      {:ok, artifact} ->
        broadcast_update({:artifact_revoked, artifact})

      {:error, reason} ->
        Logger.error("[Marketplace] Failed to revoke artifact: #{inspect(reason)}")
    end
  end

  defp handle_event("io.macula.marketplace.license_revoked", event) do
    license_cid = event["license_cid"]
    Logger.warning("[Marketplace] License revoked: #{license_cid}")

    # Add to local CRL cache (for UCAN validation)
    MaculaMarketplace.Licensing.CRLCache.add_revocation(license_cid, event["revoked_at"])

    broadcast_update({:license_revoked, license_cid})
  end

  defp handle_event(topic, event) do
    Logger.debug("[Marketplace] Unhandled event on #{topic}: #{inspect(event)}")
  end

  # Private helpers

  defp subscribe_to_topics do
    Enum.reduce_while(@topics, :ok, fn topic, _acc ->
      case :macula.subscribe(topic) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_manifest(manifest) do
    # Convert string keys to atoms for Ecto changeset
    manifest
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Map.new()
  rescue
    ArgumentError ->
      # If atom doesn't exist, keep as string and let changeset handle it
      manifest
  end

  defp broadcast_update(event) do
    Phoenix.PubSub.broadcast(
      MaculaMarketplace.PubSub,
      "marketplace:updates",
      event
    )
  end

  defp do_request_refresh(from_timestamp) do
    reply_topic = "io.macula.marketplace.refresh_reply.#{UUID.uuid4()}"

    request = %{
      reply_topic: reply_topic,
      from_timestamp: from_timestamp,
      batch_size: 100
    }

    # Subscribe to reply topic first
    :ok = :macula.subscribe(reply_topic)

    # Call the refresh RPC
    case :macula.call("io.macula.marketplace.refresh", request) do
      {:ok, %{"request_id" => request_id}} ->
        Logger.info("[Marketplace.Subscriber] Refresh requested: #{request_id}")
        {:ok, request_id}

      {:error, reason} ->
        :macula.unsubscribe(reply_topic, self())
        {:error, reason}
    end
  end
end
