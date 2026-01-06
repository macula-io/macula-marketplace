defmodule MaculaMarketplaceWeb.LicensesLive do
  @moduledoc """
  Manage UCAN license tokens.

  TODO: Implement license management with:
  - View held licenses
  - Issue new licenses (for publishers)
  - Revoke licenses
  - View delegation chains
  """

  use MaculaMarketplaceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-4">Licenses</h1>
      <p class="text-base-content/60 mb-8">
        Manage your UCAN license tokens for marketplace artifacts.
      </p>

      <div class="alert alert-info">
        <.icon name="hero-information-circle" class="w-5 h-5" />
        <span>License management is coming soon. You'll be able to issue, view, and revoke UCAN tokens.</span>
      </div>
    </div>
    """
  end
end
