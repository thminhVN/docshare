defmodule DocshareWeb.DocumentLive.New do
  use DocshareWeb, :live_view

  alias Docshare.Documents
  alias Docshare.Documents.Document

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(Documents.change_document(%Document{})))
     |> allow_upload(:html_file,
       accept: ~w(.html .htm),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"document" => params}, socket) do
    form =
      %Document{}
      |> Documents.change_document(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"document" => params}, socket) do
    uploaded =
      consume_uploaded_entries(socket, :html_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    params =
      case uploaded do
        [html | _] -> Map.put(params, "raw_html", html)
        [] -> params
      end

    case Documents.create_document(socket.assigns.current_user, params) do
      {:ok, doc} ->
        {:noreply,
         socket
         |> put_flash(:info, "Document created.")
         |> push_navigate(to: ~p"/docs/#{doc.token}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :html_file, ref)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        New document
        <:subtitle>Paste HTML or upload an <code>.html</code> file to host and share it.</:subtitle>
      </.header>

      <.simple_form for={@form} id="document-form" phx-change="validate" phx-submit="save" class="mt-6">
        <.input field={@form[:title]} type="text" label="Title" placeholder="My landing page draft" />

        <div>
          <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-1">
            Upload an HTML file (optional)
          </label>
          <div class="border-2 border-dashed rounded-lg p-4" phx-drop-target={@uploads.html_file.ref}>
            <.live_file_input upload={@uploads.html_file} class="text-sm" />
            <p class="text-xs text-zinc-500 mt-1">Up to 5 MB. Overrides the pasted HTML below.</p>

            <div :for={entry <- @uploads.html_file.entries} class="mt-2 text-sm flex items-center gap-2">
              <span>{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="text-red-600"
              >
                remove
              </button>
            </div>
            <p :for={err <- upload_errors(@uploads.html_file)} class="text-xs text-red-600">
              {error_to_string(err)}
            </p>
          </div>
        </div>

        <.input
          field={@form[:raw_html]}
          type="textarea"
          label="Or paste HTML"
          rows="12"
          phx-debounce="300"
          placeholder="<h1>Hello</h1><p>Comment on me…</p>"
        />

        <:actions>
          <.link navigate={~p"/docs"} class="text-sm text-zinc-600">Cancel</.link>
          <.button phx-disable-with="Creating…">Create document</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 5 MB)."
  defp error_to_string(:not_accepted), do: "Only .html / .htm files are allowed."
  defp error_to_string(:too_many_files), do: "Only one file allowed."
  defp error_to_string(other), do: to_string(other)
end
