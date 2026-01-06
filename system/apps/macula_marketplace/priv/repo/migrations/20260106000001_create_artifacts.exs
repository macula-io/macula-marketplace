defmodule MaculaMarketplace.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Identity
      add :artifact_id, :string, null: false
      add :version, :string, null: false

      # Type & Location
      add :type, :string, null: false

      # Container artifacts
      add :registry, :string
      add :image_digest, :string
      add :platforms, {:array, :string}, default: []

      # Downloadable artifacts
      add :download_url, :string
      add :download_size, :integer
      add :checksum, :string

      # Metadata
      add :display_name, :string, null: false
      add :description, :text
      add :license, :string
      add :homepage, :string
      add :source_repo, :string
      add :keywords, {:array, :string}, default: []

      # Pricing
      add :pricing_type, :string
      add :pricing_tier, :string

      # Requirements (JSON)
      add :requirements, :map, default: %{}

      # Publisher & Signature
      add :publisher_did, :string, null: false
      add :signature, :text
      add :published_at, :utc_datetime, null: false

      # Status
      add :revoked_at, :utc_datetime
      add :revoked_reason, :string
      add :deprecated_at, :utc_datetime
      add :deprecated_reason, :string
      add :replacement_id, :string

      timestamps(type: :utc_datetime)
    end

    # Unique constraint on artifact_id + version
    create unique_index(:artifacts, [:artifact_id, :version])

    # Indexes for common queries
    create index(:artifacts, [:publisher_did])
    create index(:artifacts, [:type])
    create index(:artifacts, [:published_at])
    create index(:artifacts, [:display_name])

    # Full-text search index (SQLite FTS5 would be ideal but not via Ecto)
    # For now, we use LIKE queries which work fine for small datasets
  end
end
