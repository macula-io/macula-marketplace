defmodule MaculaMarketplaceWeb.PublishLive do
  @moduledoc """
  Publish new artifacts to the marketplace.

  TODO: Implement artifact publishing form with:
  - Artifact metadata entry
  - Container/download URL configuration
  - Pricing configuration
  - Ed25519 signing with org private key
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
      <h1 class="text-3xl font-bold mb-4">Publish Artifact</h1>
      <p class="text-base-content/60 mb-8">
        Share your artifacts with the Macula mesh network.
      </p>

      <div class="alert alert-info">
        <.icon name="hero-information-circle" class="w-5 h-5" />
        <span>Publishing is coming soon. You'll be able to publish containers, models, genomes, and more.</span>
      </div>
    </div>
    """
  end
end
