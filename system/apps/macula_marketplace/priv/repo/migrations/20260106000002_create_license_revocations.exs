defmodule MaculaMarketplace.Repo.Migrations.CreateLicenseRevocations do
  use Ecto.Migration

  def change do
    create table(:license_revocations, primary_key: false) do
      add :token_cid, :string, primary_key: true
      add :revoked_at, :string, null: false
      add :reason, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:license_revocations, [:revoked_at])
  end
end
