defmodule MaculaMarketplaceWeb.PageController do
  use MaculaMarketplaceWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/browse")
  end
end
