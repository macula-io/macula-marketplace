defmodule MaculaMarketplace.Repo do
  use Ecto.Repo,
    otp_app: :macula_marketplace,
    adapter: Ecto.Adapters.SQLite3
end
