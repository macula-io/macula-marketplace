defmodule MaculaMarketplace.Mesh.Publisher do
  @moduledoc """
  Publish artifact events to the Macula mesh DHT PubSub.

  This module handles publishing marketplace events:
  - `io.macula.marketplace.artifact_published` - New artifact available
  - `io.macula.marketplace.artifact_updated` - Version/metadata change
  - `io.macula.marketplace.artifact_deprecated` - End-of-life notice
  - `io.macula.marketplace.artifact_revoked` - Security/license revocation

  ## Usage

      # Publish a new artifact
      Publisher.publish_artifact(manifest, org_private_key)

      # Update an artifact
      Publisher.update_artifact(artifact_id, new_manifest, org_private_key)

      # Deprecate an artifact
      Publisher.deprecate_artifact(artifact_id, version, reason, replacement_id)

  ## Event Signing

  All events are signed with the publisher's Org CA private key (Ed25519).
  This proves the event came from the organization that owns the artifact.
  """

  require Logger

  @topic_prefix "io.macula.marketplace."

  @doc """
  Publish a new artifact to the marketplace.

  The manifest must include:
  - artifact_id: Unique identifier (e.g., "io.macula.acme.my-service")
  - version: SemVer version (e.g., "1.2.3")
  - type: Artifact type (:container, :onnx_model, etc.)
  - publisher_did: Publisher's DID (e.g., "did:macula:io.macula.acme")
  """
  def publish_artifact(manifest, private_key) do
    event = build_event("ArtifactPublished", %{
      manifest: sign_manifest(manifest, private_key),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    publish_to_mesh("artifact_published", event)
  end

  @doc """
  Publish an artifact update event.
  """
  def update_artifact(artifact_id, previous_version, new_manifest, private_key) do
    event = build_event("ArtifactUpdated", %{
      artifact_id: artifact_id,
      previous_version: previous_version,
      manifest: sign_manifest(new_manifest, private_key),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    publish_to_mesh("artifact_updated", event)
  end

  @doc """
  Publish a deprecation notice for an artifact.
  """
  def deprecate_artifact(artifact_id, version, reason, replacement_id \\ nil) do
    event = build_event("ArtifactDeprecated", %{
      artifact_id: artifact_id,
      version: version,
      reason: reason,
      replacement_id: replacement_id,
      sunset_at: nil,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    publish_to_mesh("artifact_deprecated", event)
  end

  @doc """
  Publish a revocation notice for an artifact.

  Used for security issues or license violations.
  """
  def revoke_artifact(artifact_id, version, reason, advisory_url \\ nil) do
    event = build_event("ArtifactRevoked", %{
      artifact_id: artifact_id,
      version: version,
      reason: reason,
      advisory_url: advisory_url,
      revoked_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    publish_to_mesh("artifact_revoked", event)
  end

  # Private helpers

  defp build_event(type, payload) do
    Map.put(payload, :type, type)
  end

  defp sign_manifest(manifest, private_key) do
    # Encode manifest for signing (exclude signature field)
    payload = manifest |> Map.delete(:signature) |> Jason.encode!()

    # Sign with Ed25519 using macula_nifs
    {:ok, signature} = :macula_crypto_nif.nif_ed25519_sign(payload, private_key)

    Map.put(manifest, :signature, Base.encode64(signature))
  end

  defp publish_to_mesh(topic_suffix, event) do
    topic = @topic_prefix <> topic_suffix
    payload = Jason.encode!(event)

    case :macula.publish(topic, payload) do
      :ok ->
        Logger.info("[Marketplace.Publisher] Published to #{topic}")
        :ok

      {:error, reason} ->
        Logger.error("[Marketplace.Publisher] Failed to publish to #{topic}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
