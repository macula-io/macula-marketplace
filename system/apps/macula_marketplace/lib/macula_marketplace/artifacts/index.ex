defmodule MaculaMarketplace.Artifacts.Index do
  @moduledoc """
  Local SQLite index for marketplace artifacts.

  This read model is populated from DHT PubSub events. It provides
  fast local querying without requiring network access - important
  for edge deployments that may be intermittently connected.

  ## Usage

      # Search artifacts by keyword
      Index.search("neural network")

      # List by publisher
      Index.list_by_publisher("did:macula:io.macula.acme")

      # Get specific artifact
      Index.get("io.macula.acme.my-service", "1.2.3")

      # List all versions
      Index.list_versions("io.macula.acme.my-service")
  """

  import Ecto.Query
  alias MaculaMarketplace.Repo
  alias MaculaMarketplace.Artifacts.Artifact

  @doc """
  Search artifacts by keyword in display_name, description, and keywords.
  """
  def search(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    type_filter = Keyword.get(opts, :type)
    include_revoked = Keyword.get(opts, :include_revoked, false)

    search_pattern = "%#{query}%"

    Artifact
    |> where([a], ilike(a.display_name, ^search_pattern))
    |> or_where([a], ilike(a.description, ^search_pattern))
    |> maybe_filter_type(type_filter)
    |> maybe_exclude_revoked(include_revoked)
    |> order_by([a], desc: a.published_at)
    |> paginate(page, per_page)
    |> Repo.all()
  end

  @doc """
  List artifacts by publisher DID.
  """
  def list_by_publisher(publisher_did, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Artifact
    |> where([a], a.publisher_did == ^publisher_did)
    |> where([a], is_nil(a.revoked_at))
    |> order_by([a], desc: a.published_at)
    |> paginate(page, per_page)
    |> Repo.all()
  end

  @doc """
  Get a specific artifact by ID and version.
  """
  def get(artifact_id, version) do
    Artifact
    |> where([a], a.artifact_id == ^artifact_id and a.version == ^version)
    |> Repo.one()
  end

  @doc """
  Get the latest version of an artifact.
  """
  def get_latest(artifact_id) do
    Artifact
    |> where([a], a.artifact_id == ^artifact_id)
    |> where([a], is_nil(a.revoked_at))
    |> order_by([a], desc: a.published_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  List all versions of an artifact.
  """
  def list_versions(artifact_id) do
    Artifact
    |> where([a], a.artifact_id == ^artifact_id)
    |> order_by([a], desc: a.published_at)
    |> select([a], %{version: a.version, published_at: a.published_at, revoked_at: a.revoked_at})
    |> Repo.all()
  end

  @doc """
  Upsert an artifact from a marketplace event.
  """
  def upsert(attrs) do
    artifact_id = Map.get(attrs, :artifact_id) || Map.get(attrs, "artifact_id")
    version = Map.get(attrs, :version) || Map.get(attrs, "version")

    case get(artifact_id, version) do
      nil ->
        %Artifact{}
        |> Artifact.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Artifact.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Mark an artifact as revoked.
  """
  def mark_revoked(artifact_id, version, reason \\ nil) do
    case get(artifact_id, version) do
      nil ->
        {:error, :not_found}

      artifact ->
        artifact
        |> Ecto.Changeset.change(%{
          revoked_at: DateTime.utc_now(),
          revoked_reason: reason
        })
        |> Repo.update()
    end
  end

  @doc """
  Mark an artifact as deprecated.
  """
  def mark_deprecated(artifact_id, version, reason, replacement_id \\ nil) do
    case get(artifact_id, version) do
      nil ->
        {:error, :not_found}

      artifact ->
        artifact
        |> Ecto.Changeset.change(%{
          deprecated_at: DateTime.utc_now(),
          deprecated_reason: reason,
          replacement_id: replacement_id
        })
        |> Repo.update()
    end
  end

  @doc """
  List all artifacts, optionally filtered.
  """
  def list_all(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    type_filter = Keyword.get(opts, :type)

    Artifact
    |> where([a], is_nil(a.revoked_at))
    |> maybe_filter_type(type_filter)
    |> order_by([a], desc: a.published_at)
    |> paginate(page, per_page)
    |> Repo.all()
  end

  @doc """
  Count artifacts by type.
  """
  def count_by_type do
    Artifact
    |> where([a], is_nil(a.revoked_at))
    |> group_by([a], a.type)
    |> select([a], {a.type, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  # Private helpers

  defp maybe_filter_type(query, nil), do: query

  defp maybe_filter_type(query, type) do
    where(query, [a], a.type == ^type)
  end

  defp maybe_exclude_revoked(query, true), do: query

  defp maybe_exclude_revoked(query, false) do
    where(query, [a], is_nil(a.revoked_at))
  end

  defp paginate(query, page, per_page) do
    offset = (page - 1) * per_page

    query
    |> limit(^per_page)
    |> offset(^offset)
  end
end
