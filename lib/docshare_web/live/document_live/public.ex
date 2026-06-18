defmodule DocshareWeb.DocumentLive.Public do
  @moduledoc """
  Public, read-only view of a document shared via its public token. No
  authentication required; comments, sharing, and editing are not available.
  """
  use DocshareWeb, :live_view

  alias Docshare.Documents
  alias Docshare.Documents.Html

  @impl true
  def mount(%{"public_token" => token}, _session, socket) do
    case Documents.get_public_document(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This shared document is not available.")
         |> redirect(to: ~p"/")}

      doc ->
        versions = Documents.list_versions(doc)

        socket =
          socket
          |> assign(:doc, doc)
          |> assign(:versions, versions)
          |> assign(:fullscreen, false)
          |> assign(:page_title, doc.title)

        {:ok, select_version(socket, Documents.latest_version(doc))}
    end
  end

  defp select_version(socket, version) do
    {processed, _anchors, head_html} = Html.process(version.raw_html)

    socket
    |> assign(:version, version)
    |> assign(:frame, Html.frame(processed, head_html, interactive: false))
  end

  @impl true
  def handle_event("select_version", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.versions, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      version -> {:noreply, select_version(socket, version)}
    end
  end

  def handle_event("toggle_fullscreen", _params, socket) do
    {:noreply, assign(socket, :fullscreen, !socket.assigns.fullscreen)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-7rem)]">
      <div class="flex items-center justify-between pb-3 border-b mb-3 gap-3 flex-wrap">
        <div>
          <span class="inline-flex items-center gap-1 text-xs font-medium text-zinc-500">
            <.icon name="hero-eye" class="h-4 w-4" /> Read-only shared document
          </span>
          <h1 class="text-xl font-bold">{@doc.title}</h1>
        </div>

        <div class="flex items-center gap-2">
          <form :if={length(@versions) > 1} id="version-select" phx-change="select_version">
            <select
              name="id"
              class="rounded-lg border-zinc-300 text-sm py-2 pr-8 focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option
                :for={v <- @versions}
                value={v.id}
                selected={v.id == @version.id}
              >
                {v.label} — {Calendar.strftime(v.inserted_at, "%Y-%m-%d %H:%M")}
              </option>
            </select>
          </form>

          <.link
            href={~p"/p/#{@doc.public_token}/versions/#{@version.id}/print"}
            target="_blank"
            class="rounded-lg border border-zinc-300 px-3 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
            title="Open a print-ready view — use browser Print → Save as PDF"
          >
            ⎙ Print / PDF
          </.link>
        </div>
      </div>

      <div
        class={[
          "border bg-white overflow-hidden",
          if(@fullscreen,
            do: "fixed inset-0 z-50 rounded-none",
            else: "relative rounded-lg flex-1 min-h-0"
          )
        ]}
        phx-window-keydown={@fullscreen && "toggle_fullscreen"}
        phx-key="Escape"
      >
        <button
          phx-click="toggle_fullscreen"
          title={if @fullscreen, do: "Exit fullscreen (Esc)", else: "Fullscreen"}
          aria-label={if @fullscreen, do: "Exit fullscreen", else: "Fullscreen"}
          class="absolute top-2 right-2 z-10 rounded-md bg-zinc-900/70 text-white px-2.5 py-1.5 text-sm font-semibold hover:bg-zinc-900"
        >
          {if @fullscreen, do: "✕", else: "⛶"}
        </button>
        <iframe
          id={"public-frame-#{@version.id}"}
          phx-update="ignore"
          sandbox="allow-scripts"
          allowfullscreen
          srcdoc={@frame}
          class="w-full h-full"
        ></iframe>
      </div>
    </div>
    """
  end
end
