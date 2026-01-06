defmodule MaculaMarketplaceWeb.BrowseLive do
  @moduledoc """
  Browse marketplace artifacts.

  Displays a searchable list of artifacts from the local SQLite index.
  Updates in real-time as new artifacts are published via mesh events.
  """

  use MaculaMarketplaceWeb, :live_view

  alias MaculaMarketplace.Artifacts.Index

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to marketplace updates for real-time UI updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MaculaMarketplace.PubSub, "marketplace:updates")
    end

    artifacts = Index.list_all(page: 1, per_page: 20)
    type_counts = Index.count_by_type()

    {:ok,
     socket
     |> assign(:artifacts, artifacts)
     |> assign(:type_counts, type_counts)
     |> assign(:search_query, "")
     |> assign(:selected_type, nil)
     |> assign(:page, 1)
     |> assign(:mesh_connected, MaculaMarketplace.Mesh.Subscriber.connected?())}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    artifacts =
      if String.length(query) > 0 do
        Index.search(query, type: socket.assigns.selected_type)
      else
        Index.list_all(type: socket.assigns.selected_type)
      end

    {:noreply,
     socket
     |> assign(:artifacts, artifacts)
     |> assign(:search_query, query)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    type_atom = if type == "", do: nil, else: String.to_existing_atom(type)

    artifacts =
      if String.length(socket.assigns.search_query) > 0 do
        Index.search(socket.assigns.search_query, type: type_atom)
      else
        Index.list_all(type: type_atom)
      end

    {:noreply,
     socket
     |> assign(:artifacts, artifacts)
     |> assign(:selected_type, type_atom)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_info({:artifact_published, _artifact}, socket) do
    # Refresh the list when new artifact arrives
    artifacts = refresh_artifacts(socket)
    type_counts = Index.count_by_type()

    {:noreply,
     socket
     |> assign(:artifacts, artifacts)
     |> assign(:type_counts, type_counts)}
  end

  @impl true
  def handle_info({:artifact_updated, _artifact}, socket) do
    artifacts = refresh_artifacts(socket)
    {:noreply, assign(socket, :artifacts, artifacts)}
  end

  @impl true
  def handle_info({:artifact_revoked, _artifact}, socket) do
    artifacts = refresh_artifacts(socket)
    type_counts = Index.count_by_type()

    {:noreply,
     socket
     |> assign(:artifacts, artifacts)
     |> assign(:type_counts, type_counts)}
  end

  @impl true
  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp refresh_artifacts(socket) do
    if String.length(socket.assigns.search_query) > 0 do
      Index.search(socket.assigns.search_query, type: socket.assigns.selected_type)
    else
      Index.list_all(type: socket.assigns.selected_type, page: socket.assigns.page)
    end
  end

  defp type_label(:container), do: "Container"
  defp type_label(:onnx_model), do: "ONNX Model"
  defp type_label(:tweann_genome), do: "TWEANN Genome"
  defp type_label(:dataset), do: "Dataset"
  defp type_label(:beam_release), do: "BEAM Release"
  defp type_label(:helm_chart), do: "Helm Chart"
  defp type_label(_), do: "Unknown"

  defp type_icon(:container), do: "hero-cube"
  defp type_icon(:onnx_model), do: "hero-cpu-chip"
  defp type_icon(:tweann_genome), do: "hero-variable"
  defp type_icon(:dataset), do: "hero-circle-stack"
  defp type_icon(:beam_release), do: "hero-rocket-launch"
  defp type_icon(:helm_chart), do: "hero-cloud"
  defp type_icon(_), do: "hero-question-mark-circle"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <!-- Header -->
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-3xl font-bold">Marketplace</h1>
          <p class="text-base-content/60">Browse artifacts available in the mesh</p>
        </div>

        <div class="flex items-center gap-2">
          <%= if @mesh_connected do %>
            <div class="badge badge-success gap-1">
              <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span>
              Connected
            </div>
          <% else %>
            <div class="badge badge-warning gap-1">
              <span class="w-2 h-2 rounded-full bg-warning"></span>
              Offline
            </div>
          <% end %>
        </div>
      </div>

      <!-- Search and Filters -->
      <div class="flex flex-col md:flex-row gap-4 mb-6">
        <div class="flex-1">
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search artifacts..."
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </form>
        </div>

        <div class="flex gap-2">
          <select
            class="select select-bordered"
            phx-change="filter_type"
            name="type"
          >
            <option value="">All Types</option>
            <option value="container" selected={@selected_type == :container}>Containers</option>
            <option value="onnx_model" selected={@selected_type == :onnx_model}>ONNX Models</option>
            <option value="tweann_genome" selected={@selected_type == :tweann_genome}>TWEANN Genomes</option>
            <option value="dataset" selected={@selected_type == :dataset}>Datasets</option>
            <option value="beam_release" selected={@selected_type == :beam_release}>BEAM Releases</option>
            <option value="helm_chart" selected={@selected_type == :helm_chart}>Helm Charts</option>
          </select>
        </div>
      </div>

      <!-- Type Stats -->
      <div class="grid grid-cols-2 md:grid-cols-6 gap-2 mb-6">
        <%= for {type, count} <- @type_counts do %>
          <button
            phx-click="filter_type"
            phx-value-type={type}
            class={"card bg-base-200 p-3 text-center hover:bg-base-300 transition-colors #{if @selected_type == type, do: "ring-2 ring-primary", else: ""}"}
          >
            <.icon name={type_icon(type)} class="w-6 h-6 mx-auto mb-1" />
            <div class="text-xs font-medium"><%= type_label(type) %></div>
            <div class="text-lg font-bold"><%= count %></div>
          </button>
        <% end %>
      </div>

      <!-- Artifacts Grid -->
      <%= if length(@artifacts) == 0 do %>
        <div class="text-center py-12">
          <.icon name="hero-inbox" class="w-12 h-12 mx-auto text-base-content/40 mb-4" />
          <p class="text-base-content/60">No artifacts found</p>
          <%= if not @mesh_connected do %>
            <p class="text-sm text-warning mt-2">
              Connect to the mesh to discover artifacts
            </p>
          <% end %>
        </div>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for artifact <- @artifacts do %>
            <.link navigate={~p"/artifacts/#{artifact.artifact_id}/#{artifact.version}"} class="card bg-base-200 hover:bg-base-300 transition-colors">
              <div class="card-body">
                <div class="flex items-start justify-between">
                  <div class="flex items-center gap-2">
                    <.icon name={type_icon(artifact.type)} class="w-5 h-5 text-primary" />
                    <span class="badge badge-sm"><%= type_label(artifact.type) %></span>
                  </div>
                  <span class="badge badge-ghost"><%= artifact.version %></span>
                </div>

                <h3 class="card-title text-lg mt-2"><%= artifact.display_name %></h3>

                <%= if artifact.description do %>
                  <p class="text-sm text-base-content/70 line-clamp-2">
                    <%= artifact.description %>
                  </p>
                <% end %>

                <div class="flex items-center justify-between mt-4 text-xs text-base-content/50">
                  <span><%= artifact.publisher_did |> String.split(":") |> List.last() %></span>
                  <span><%= Calendar.strftime(artifact.published_at, "%b %d, %Y") %></span>
                </div>

                <%= if artifact.pricing_type do %>
                  <div class="mt-2">
                    <%= case artifact.pricing_type do %>
                      <% :free -> %>
                        <span class="badge badge-success">Free</span>
                      <% :subscription -> %>
                        <span class="badge badge-info">Subscription</span>
                      <% :one_time -> %>
                        <span class="badge badge-warning">One-time</span>
                      <% _ -> %>
                        <span class="badge"><%= artifact.pricing_type %></span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
