defmodule DocshareWeb.DocumentLive.Index do
  use DocshareWeb, :live_view

  alias Docshare.Documents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :documents, list_docs(socket))}
  end

  defp list_docs(socket),
    do: Documents.list_documents_for_user(socket.assigns.current_user)

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    doc = Documents.get_document!(id)

    if Documents.owner?(doc, socket.assigns.current_user) do
      {:ok, _} = Documents.delete_document(doc)
      {:noreply, assign(socket, :documents, list_docs(socket))}
    else
      {:noreply, put_flash(socket, :error, "Only the owner can delete a document.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
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

      <div :if={@documents == []} class="text-center py-16 text-zinc-500 border border-dashed rounded-lg">
        No documents yet. <.link navigate={~p"/docs/new"} class="text-indigo-600 underline">Create one</.link>.
      </div>

      <ul class="divide-y divide-zinc-200 border rounded-lg overflow-hidden">
        <li :for={doc <- @documents} class="flex items-center justify-between p-4 hover:bg-zinc-50">
          <div>
            <.link navigate={~p"/docs/#{doc.token}"} class="font-semibold text-indigo-700 hover:underline">
              {doc.title}
            </.link>
            <p class="text-xs text-zinc-500">
              {if doc.owner_id == @current_user.id, do: "Owned by you", else: "Shared with you"}
              · updated {Calendar.strftime(doc.updated_at, "%Y-%m-%d %H:%M")}
            </p>
          </div>
          <div class="flex items-center gap-3">
            <.link navigate={~p"/docs/#{doc.token}"} class="text-sm text-zinc-600 hover:underline">Open</.link>
            <.link
              :if={doc.owner_id == @current_user.id}
              phx-click="delete"
              phx-value-id={doc.id}
              data-confirm="Delete this document and all its comments?"
              class="text-sm text-red-600 hover:underline"
            >
              Delete
            </.link>
          </div>
        </li>
      </ul>
    </div>
    """
  end
end
