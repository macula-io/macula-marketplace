defmodule MaculaMarketplaceWeb.Api.ArtifactController do
  @moduledoc """
  REST API for marketplace artifacts.

  This API enables mesh RPC proxying - other mesh participants
  can query this marketplace's local index via HTTP.
  """

  use MaculaMarketplaceWeb, :controller

  alias MaculaMarketplace.Artifacts.Index

  def index(conn, params) do
    query = Map.get(params, "q", "")
    type = params |> Map.get("type") |> parse_type()
    page = params |> Map.get("page", "1") |> String.to_integer()
    per_page = params |> Map.get("per_page", "20") |> String.to_integer()

    artifacts =
      if String.length(query) > 0 do
        Index.search(query, type: type, page: page, per_page: per_page)
      else
        Index.list_all(type: type, page: page, per_page: per_page)
      end

    json(conn, %{
      data: Enum.map(artifacts, &artifact_to_json/1),
      meta: %{
        page: page,
        per_page: per_page,
        count: length(artifacts)
      }
    })
  end

  def show(conn, %{"artifact_id" => artifact_id, "version" => version}) do
    case Index.get(artifact_id, version) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Artifact not found"})

      artifact ->
        json(conn, %{data: artifact_to_json(artifact)})
    end
  end

  def create(conn, _params) do
    # TODO: Implement artifact publishing via API
    # This requires signature verification
    conn
    |> put_status(:not_implemented)
    |> json(%{error: "Publishing via API not yet implemented"})
  end

  # Private helpers

  defp parse_type(nil), do: nil
  defp parse_type(""), do: nil

  defp parse_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> nil
  end

  defp artifact_to_json(artifact) do
    %{
      id: artifact.id,
      artifact_id: artifact.artifact_id,
      version: artifact.version,
      type: artifact.type,
      display_name: artifact.display_name,
      description: artifact.description,
      publisher_did: artifact.publisher_did,
      published_at: artifact.published_at,
      pricing_type: artifact.pricing_type,
      pricing_tier: artifact.pricing_tier,
      license: artifact.license,
      homepage: artifact.homepage,
      registry: artifact.registry,
      download_url: artifact.download_url,
      revoked_at: artifact.revoked_at,
      deprecated_at: artifact.deprecated_at
    }
  end
end
