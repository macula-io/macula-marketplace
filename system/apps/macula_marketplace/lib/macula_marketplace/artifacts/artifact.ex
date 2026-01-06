defmodule MaculaMarketplace.Artifacts.Artifact do
  @moduledoc """
  Schema for marketplace artifacts stored in the local SQLite index.

  This is a read model that gets populated from DHT PubSub events.
  The marketplace subscribes to `io.macula.marketplace.*` topics and
  maintains this local index for fast querying.

  ## Artifact Types

  - `:container` - Docker/OCI container images (ghcr.io)
  - `:onnx_model` - ONNX neural network models
  - `:tweann_genome` - TWEANN genome files
  - `:dataset` - Training/inference datasets
  - `:beam_release` - Erlang/Elixir releases
  - `:helm_chart` - Kubernetes Helm charts
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type artifact_type ::
          :container | :onnx_model | :tweann_genome | :dataset | :beam_release | :helm_chart

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "artifacts" do
    # Identity
    field :artifact_id, :string
    field :version, :string

    # Type & Location
    field :type, Ecto.Enum,
      values: [:container, :onnx_model, :tweann_genome, :dataset, :beam_release, :helm_chart]

    # Container artifacts
    field :registry, :string
    field :image_digest, :string
    field :platforms, {:array, :string}, default: []

    # Downloadable artifacts
    field :download_url, :string
    field :download_size, :integer
    field :checksum, :string

    # Metadata
    field :display_name, :string
    field :description, :string
    field :license, :string
    field :homepage, :string
    field :source_repo, :string
    field :keywords, {:array, :string}, default: []

    # Pricing
    field :pricing_type, Ecto.Enum, values: [:free, :subscription, :one_time, :usage_based]
    field :pricing_tier, :string

    # Requirements (stored as JSON)
    field :requirements, :map, default: %{}

    # Publisher & Signature
    field :publisher_did, :string
    field :signature, :string
    field :published_at, :utc_datetime

    # Status
    field :revoked_at, :utc_datetime
    field :revoked_reason, :string
    field :deprecated_at, :utc_datetime
    field :deprecated_reason, :string
    field :replacement_id, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(artifact_id version type display_name publisher_did published_at)a
  @optional_fields ~w(
    registry image_digest platforms
    download_url download_size checksum
    description license homepage source_repo keywords
    pricing_type pricing_tier requirements signature
    revoked_at revoked_reason deprecated_at deprecated_reason replacement_id
  )a

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:artifact_id, :version])
    |> validate_container_fields()
    |> validate_download_fields()
  end

  defp validate_container_fields(changeset) do
    case get_field(changeset, :type) do
      :container ->
        changeset
        |> validate_required([:registry])

      _ ->
        changeset
    end
  end

  defp validate_download_fields(changeset) do
    type = get_field(changeset, :type)

    if type in [:onnx_model, :tweann_genome, :dataset, :beam_release] do
      changeset
      |> validate_required([:download_url, :checksum])
    else
      changeset
    end
  end
end
