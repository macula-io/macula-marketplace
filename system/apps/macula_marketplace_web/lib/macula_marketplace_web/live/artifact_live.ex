defmodule MaculaMarketplaceWeb.ArtifactLive do
  @moduledoc """
  View details of a specific artifact.
  """

  use MaculaMarketplaceWeb, :live_view

  alias MaculaMarketplace.Artifacts.Index

  @impl true
  def mount(%{"artifact_id" => artifact_id, "version" => version}, _session, socket) do
    case Index.get(artifact_id, version) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Artifact not found")
         |> push_navigate(to: ~p"/browse")}

      artifact ->
        versions = Index.list_versions(artifact_id)

        {:ok,
         socket
         |> assign(:artifact, artifact)
         |> assign(:versions, versions)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <.link navigate={~p"/browse"} class="btn btn-ghost btn-sm gap-2 mb-4">
        <.icon name="hero-arrow-left" class="w-4 h-4" />
        Back to Browse
      </.link>

      <div class="card bg-base-200">
        <div class="card-body">
          <h1 class="card-title text-2xl"><%= @artifact.display_name %></h1>
          <p class="text-base-content/60"><%= @artifact.artifact_id %></p>

          <div class="flex gap-2 my-4">
            <span class="badge badge-primary"><%= @artifact.type %></span>
            <span class="badge badge-outline">v<%= @artifact.version %></span>
            <%= if @artifact.pricing_type == :free do %>
              <span class="badge badge-success">Free</span>
            <% end %>
          </div>

          <%= if @artifact.description do %>
            <p class="text-base-content/80 my-4"><%= @artifact.description %></p>
          <% end %>

          <div class="divider">Details</div>

          <dl class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt class="font-medium text-base-content/60">Publisher</dt>
              <dd><%= @artifact.publisher_did %></dd>
            </div>
            <div>
              <dt class="font-medium text-base-content/60">Published</dt>
              <dd><%= Calendar.strftime(@artifact.published_at, "%B %d, %Y") %></dd>
            </div>
            <%= if @artifact.license do %>
              <div>
                <dt class="font-medium text-base-content/60">License</dt>
                <dd><%= @artifact.license %></dd>
              </div>
            <% end %>
            <%= if @artifact.homepage do %>
              <div>
                <dt class="font-medium text-base-content/60">Homepage</dt>
                <dd><a href={@artifact.homepage} class="link" target="_blank"><%= @artifact.homepage %></a></dd>
              </div>
            <% end %>
          </dl>

          <div class="divider">Versions</div>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Version</th>
                  <th>Published</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <%= for v <- @versions do %>
                  <tr class={if v.version == @artifact.version, do: "bg-base-300"}>
                    <td>
                      <.link navigate={~p"/artifacts/#{@artifact.artifact_id}/#{v.version}"} class="link">
                        <%= v.version %>
                      </.link>
                    </td>
                    <td><%= Calendar.strftime(v.published_at, "%b %d, %Y") %></td>
                    <td>
                      <%= if v.revoked_at do %>
                        <span class="badge badge-error badge-sm">Revoked</span>
                      <% else %>
                        <span class="badge badge-success badge-sm">Available</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
