defmodule DocshareWeb.DocumentLive.Index do
  use DocshareWeb, :live_view

  alias Docshare.Documents
  alias Docshare.Documents.Html

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_docs(socket)}
  end

  defp load_docs(socket) do
    docs = Documents.list_documents_for_user(socket.assigns.current_user)
    versions = Documents.latest_versions_for(docs)

    previews =
      Map.new(docs, fn doc ->
        {doc.id, preview_frame(versions[doc.id])}
      end)

    socket
    |> assign(:documents, docs)
    |> assign(:previews, previews)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    doc = Documents.get_document!(id)

    if Documents.owner?(doc, socket.assigns.current_user) do
      {:ok, _} = Documents.delete_document(doc)
      {:noreply, load_docs(socket)}
    else
      {:noreply, put_flash(socket, :error, "Only the owner can delete a document.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="flex items-center justify-between mb-8">
        <div>
          <.header>
            My documents
            <:subtitle>HTML docs you own or have been invited to comment on.</:subtitle>
          </.header>
        </div>
        <.link navigate={~p"/docs/new"}>
          <.button>+ New document</.button>
        </.link>
      </div>

      <div
        :if={@documents == []}
        class="text-center py-16 text-zinc-500 border border-dashed rounded-lg"
      >
        No documents yet.
        <.link navigate={~p"/docs/new"} class="text-indigo-600 underline">Create one</.link>.
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        <div
          :for={doc <- @documents}
          class="group flex flex-col border rounded-lg overflow-hidden bg-white hover:shadow-md transition-shadow"
        >
          <.link navigate={~p"/docs/#{doc.token}"} class="block relative h-44 bg-zinc-50 border-b overflow-hidden">
            <iframe
              :if={@previews[doc.id]}
              srcdoc={@previews[doc.id]}
              sandbox=""
              scrolling="no"
              loading="lazy"
              tabindex="-1"
              aria-hidden="true"
              class="w-[200%] h-[400px] origin-top-left scale-50 pointer-events-none border-0"
            >
            </iframe>
            <div
              :if={!@previews[doc.id]}
              class="flex items-center justify-center h-full text-xs text-zinc-400"
            >
              No preview
            </div>
          </.link>

          <div class="p-4">
            <.link
              navigate={~p"/docs/#{doc.token}"}
              class="block font-semibold text-indigo-700 hover:underline break-words"
            >
              {doc.title}
            </.link>
            <div class="flex items-center justify-between gap-2 mt-1">
              <p class="text-xs text-zinc-500">
                {if doc.owner_id == @current_user.id, do: "Owned by you", else: "Shared with you"}
                · updated {relative_time(doc.updated_at)}
              </p>
              <.link
                :if={doc.owner_id == @current_user.id}
                phx-click="delete"
                phx-value-id={doc.id}
                data-confirm="Delete this document and all its comments?"
                class="shrink-0 text-zinc-400 hover:text-red-600"
                title="Delete document"
                aria-label="Delete document"
              >
                <.icon name="hero-trash" class="h-4 w-4" />
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Human-friendly relative time, e.g. "just now", "5 minutes ago", "3 days ago".
  defp relative_time(%DateTime{} = at),
    do: relative_seconds(DateTime.diff(DateTime.utc_now(), at, :second))

  defp relative_time(%NaiveDateTime{} = at),
    do: relative_seconds(NaiveDateTime.diff(NaiveDateTime.utc_now(), at, :second))

  defp relative_seconds(seconds) do

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> ago(div(seconds, 60), "minute")
      seconds < 86_400 -> ago(div(seconds, 3600), "hour")
      seconds < 2_592_000 -> ago(div(seconds, 86_400), "day")
      seconds < 31_536_000 -> ago(div(seconds, 2_592_000), "month")
      true -> ago(div(seconds, 31_536_000), "year")
    end
  end

  defp ago(1, unit), do: "1 #{unit} ago"
  defp ago(n, unit), do: "#{n} #{unit}s ago"

  # A lightweight, fully-sandboxed (no scripts) render of the latest version,
  # used as a grid thumbnail. Reuses the same sanitizing pipeline as the viewer.
  defp preview_frame(nil), do: nil

  defp preview_frame(version) do
    {processed, _anchors, head_html} = Html.process(version.raw_html)

    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    #{head_html}
    <style>
      html { font-family: ui-sans-serif, system-ui, sans-serif; padding: 8px 16px; color:#18181b; }
      body { margin: 0; }
    </style>
    </head>
    <body>
    #{processed}
    </body>
    </html>
    """
  end
end
