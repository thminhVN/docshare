defmodule DocshareWeb.DocumentLive.Show do
  use DocshareWeb, :live_view

  alias Docshare.Documents
  alias Docshare.Documents.Html

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    doc = Documents.get_document_by_token!(token)
    user = socket.assigns.current_user

    if Documents.can_access?(doc, user) do
      if connected?(socket), do: Documents.subscribe(doc.id)

      socket =
        socket
        |> assign(:doc, doc)
        |> assign(:owner?, Documents.owner?(doc, user))
        |> assign(:selected_anchor, nil)
        |> assign(:selected_label, nil)
        |> assign(:show_share, false)
        |> assign(:show_add_version, false)
        |> assign(:show_export, false)
        |> assign(:export_text, "")
        |> assign(:show_diff, false)
        |> assign(:diff_a, nil)
        |> assign(:diff_b, nil)
        |> assign(:diff, [])
        |> assign(:diff_steps, [])
        |> assign(:diff_frame, "")
        |> assign(:fullscreen, false)
        |> assign(:comment_form, to_form(%{"body" => ""}, as: :comment))
        |> assign(:invite_form, to_form(%{"email" => ""}, as: :invite))
        |> assign(:version_form, to_form(%{"label" => "", "raw_html" => ""}, as: :version))
        |> assign(:port_suggestion, nil)
        |> allow_upload(:version_file,
          accept: ~w(.html .htm),
          max_entries: 1,
          max_file_size: 5_000_000
        )
        |> load_versions()
        |> load_collaborators()

      {:ok, select_version(socket, Documents.latest_version(doc))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have access to that document.")
       |> redirect(to: ~p"/docs")}
    end
  end

  defp load_versions(socket) do
    doc = socket.assigns.doc

    socket
    |> assign(:versions, Documents.list_versions(doc))
    |> assign(:version_counts, Documents.comment_counts_by_version(doc))
  end

  # Switch the rendered/commented version.
  defp select_version(socket, version) do
    {processed, _anchors, head_html} = Html.process(version.raw_html)

    socket
    |> assign(:version, version)
    |> assign(:frame, build_frame(processed, head_html))
    |> assign(:selected_anchor, nil)
    |> assign(:selected_label, nil)
    |> load_comments()
    |> push_event("ds:select", %{anchor: nil})
  end

  defp load_comments(socket) do
    version = socket.assigns.version
    comments = Documents.list_comments(version)
    counts = Documents.comment_counts(version)

    socket
    |> assign(:comments, comments)
    |> assign(:counts, counts)
    |> push_event("ds:counts", %{counts: counts})
  end

  defp load_collaborators(socket) do
    assign(socket, :collaborators, Documents.list_collaborators(socket.assigns.doc))
  end

  ## Version events

  @impl true
  def handle_event("select_version", %{"id" => id}, socket) do
    version = Enum.find(socket.assigns.versions, &(to_string(&1.id) == id))
    socket = if(version, do: select_version(socket, version), else: socket)
    {:noreply, assign(socket, :port_suggestion, nil)}
  end

  def handle_event("toggle_fullscreen", _params, socket) do
    {:noreply, assign(socket, :fullscreen, !socket.assigns.fullscreen)}
  end

  def handle_event("toggle_export", _params, socket) do
    show = !socket.assigns.show_export

    text =
      if show,
        do: Documents.export_comments(socket.assigns.doc, socket.assigns.version),
        else: ""

    {:noreply, socket |> assign(:show_export, show) |> assign(:export_text, text)}
  end

  def handle_event("toggle_add_version", _params, socket) do
    {:noreply, assign(socket, :show_add_version, !socket.assigns.show_add_version)}
  end

  def handle_event("validate_version", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_diff", _params, socket) do
    if socket.assigns.show_diff do
      {:noreply, assign(socket, :show_diff, false)}
    else
      versions = socket.assigns.versions
      # Default: compare the current version against the next-older one.
      b = socket.assigns.version
      a = Enum.find(versions, b, &(&1.version_number < b.version_number))
      {:noreply, socket |> assign(:show_diff, true) |> compute_diff(a.id, b.id)}
    end
  end

  def handle_event("update_diff", %{"a" => a_id, "b" => b_id}, socket) do
    {:noreply, compute_diff(socket, a_id, b_id)}
  end

  def handle_event("add_version", %{"version" => params}, socket) do
    uploaded =
      consume_uploaded_entries(socket, :version_file, fn %{path: path}, _ ->
        {:ok, File.read!(path)}
      end)

    params =
      case uploaded do
        [html | _] -> Map.put(params, "raw_html", html)
        [] -> params
      end

    case Documents.add_version(socket.assigns.doc, socket.assigns.current_user, params) do
      {:ok, version} ->
        prev_version = socket.assigns.version
        mapping = Documents.compute_anchor_mapping(prev_version, version)
        portable_count = Documents.portable_comment_count(prev_version, mapping)

        port_suggestion =
          if portable_count > 0 do
            %{
              from_label: prev_version.label,
              to_label: version.label,
              count: portable_count,
              mapping: mapping,
              old_version_id: prev_version.id,
              new_version_id: version.id
            }
          end

        {:noreply,
         socket
         |> assign(:show_add_version, false)
         |> assign(:version_form, to_form(%{"label" => "", "raw_html" => ""}, as: :version))
         |> put_flash(:info, "Version #{version.label} added.")
         |> assign(:port_suggestion, port_suggestion)
         |> load_versions()
         |> then(&select_version(&1, version))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add version (HTML required).")}
    end
  end

  def handle_event("cancel-version-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :version_file, ref)}
  end

  ## Anchor / comment events

  def handle_event("select_anchor", %{"anchor" => anchor} = params, socket) do
    {:noreply,
     socket
     |> assign(:selected_anchor, anchor)
     |> assign(:selected_label, params["label"])
     |> push_event("ds:select", %{anchor: anchor})}
  end

  def handle_event("clear_anchor", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_anchor, nil)
     |> assign(:selected_label, nil)
     |> push_event("ds:select", %{anchor: nil})}
  end

  def handle_event("add_comment", %{"comment" => %{"body" => body}}, socket) do
    case socket.assigns.selected_anchor do
      nil ->
        {:noreply, put_flash(socket, :error, "Click a part of the document first.")}

      anchor ->
        attrs = %{
          "body" => body,
          "anchor" => anchor,
          "anchor_label" => socket.assigns.selected_label
        }

        case Documents.create_comment(socket.assigns.version, socket.assigns.current_user, attrs) do
          {:ok, _comment} ->
            {:noreply,
             socket
             |> assign(:comment_form, to_form(%{"body" => ""}, as: :comment))
             |> push_event("comment:reset", %{})
             |> load_comments()
             |> load_versions()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Comment can't be blank.")}
        end
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    comment = Documents.get_comment!(id)
    user = socket.assigns.current_user

    if comment.author_id == user.id or socket.assigns.owner? do
      :ok = Documents.delete_comment(comment)
    end

    {:noreply, socket}
  end

  def handle_event("toggle_resolved", %{"id" => id}, socket) do
    Documents.get_comment!(id) |> Documents.toggle_resolved()
    {:noreply, socket}
  end

  ## Sharing events

  def handle_event("toggle_share", _params, socket) do
    {:noreply, assign(socket, :show_share, !socket.assigns.show_share)}
  end

  def handle_event("invite", %{"invite" => %{"email" => email}}, socket) do
    case Documents.invite_collaborator(socket.assigns.doc, socket.assigns.current_user, email) do
      {:ok, _collab} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{email}.")
         |> assign(:invite_form, to_form(%{"email" => ""}, as: :invite))}

      {:error, {:email_delivery_failed, _reason}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not send invitation email. Check the mail provider configuration and try again."
         )}

      {:error, changeset} ->
        msg =
          changeset.errors
          |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Could not invite: #{msg}")}
    end
  end

  def handle_event("remove_collaborator", %{"id" => id}, socket) do
    Documents.get_collaborator!(id) |> Documents.remove_collaborator()
    {:noreply, socket}
  end

  ## Anchor porting events

  def handle_event("port_comments", _params, socket) do
    %{old_version_id: old_id, new_version_id: new_id, mapping: mapping, to_label: to_label} =
      socket.assigns.port_suggestion

    old_v = Documents.get_version!(old_id)
    new_v = Documents.get_version!(new_id)
    {:ok, count} = Documents.port_comments(old_v, new_v, mapping)

    {:noreply,
     socket
     |> assign(:port_suggestion, nil)
     |> put_flash(:info, "#{count} comment(s) ported to #{to_label}.")
     |> load_comments()
     |> load_versions()}
  end

  def handle_event("dismiss_port", _params, socket) do
    {:noreply, assign(socket, :port_suggestion, nil)}
  end

  ## PubSub

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:comment_created, :comment_deleted, :comment_updated] do
    {:noreply, socket |> load_comments() |> load_versions()}
  end

  def handle_info({:comments_ported, _count}, socket) do
    {:noreply, socket |> load_comments() |> load_versions()}
  end

  def handle_info({:version_created, _version}, socket) do
    {:noreply, load_versions(socket)}
  end

  def handle_info({:collaborators_changed, _id}, socket) do
    {:noreply, load_collaborators(socket)}
  end

  # Ignore stray messages (e.g. Swoosh test-adapter {:email, _} delivered to self).
  def handle_info(_msg, socket), do: {:noreply, socket}

  ## Helpers

  defp comments_for(comments, anchor), do: Enum.filter(comments, &(&1.anchor == anchor))

  # Renders a comment body with a small, GitHub-flavored subset of markdown.
  # The body is HTML-escaped first, so only the formatting we explicitly add is
  # ever emitted — user input can never inject markup.
  defp format_comment(body) do
    body
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> apply_markdown()
    |> Phoenix.HTML.raw()
  end

  defp apply_markdown(text) do
    text
    # [label](https://url)
    |> replace(~r/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/, fn _, label, url ->
      ~s(<a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-indigo-600 underline">#{label}</a>)
    end)
    # `inline code`
    |> replace(~r/`([^`\n]+)`/, fn _, code ->
      ~s(<code class="rounded bg-zinc-200 px-1 py-0.5 text-[0.85em]">#{code}</code>)
    end)
    # **bold**
    |> replace(~r/\*\*([^*\n]+)\*\*/, fn _, b -> "<strong>#{b}</strong>" end)
    # *italic* or _italic_ (only when the marker isn't part of a word, so URLs
    # like http://a_b_c and snake_case are left alone)
    |> replace(~r/(?<![\w*])[*_](?=\S)([^*_\n]+?)(?<=\S)[*_](?![\w*])/, fn _, i ->
      "<em>#{i}</em>"
    end)
  end

  defp replace(text, regex, fun), do: Regex.replace(regex, text, fun)

  defp compute_diff(socket, a_id, b_id) do
    versions = socket.assigns.versions
    a = Enum.find(versions, &(to_string(&1.id) == to_string(a_id)))
    b = Enum.find(versions, &(to_string(&1.id) == to_string(b_id)))

    diff = if a && b, do: Documents.diff_version_blocks(a, b), else: []
    head = if a && b, do: Documents.diff_head(a, b), else: ""

    steps =
      diff
      |> Enum.filter(&(elem(&1, 0) != :eq))
      |> Enum.with_index()
      |> Enum.map(fn {{op, blk}, i} ->
        %{n: i, op: op, label: String.slice(blk.text, 0, 70)}
      end)

    socket
    |> assign(:diff_a, a)
    |> assign(:diff_b, b)
    |> assign(:diff, diff)
    |> assign(:diff_steps, steps)
    |> assign(:diff_frame, build_diff_frame(diff, head))
  end

  # A rendered "redline": each block shown with its real HTML/styling, marked
  # added (green) / removed (red, struck) / unchanged.
  defp build_diff_frame(diff, head_html) do
    {rows, _} =
      Enum.map_reduce(diff, 0, fn {op, blk}, n ->
        case op do
          :eq ->
            {~s(<div class="dsrow ds-eq">#{blk.html}</div>), n}

          _ ->
            cls = if op == :ins, do: "ds-ins", else: "ds-del"
            {~s(<div id="step-#{n}" class="dsrow #{cls}">#{blk.html}</div>), n + 1}
        end
      end)

    content = Enum.join(rows, "\n")

    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    #{head_html}
    <style>
      html { font-family: ui-sans-serif, system-ui, sans-serif; padding: 8px 12px; color:#18181b; }
      .dsrow { position: relative; padding: 2px 8px 2px 22px; border-radius: 3px; margin: 2px 0; scroll-margin-top: 12px; }
      .dsrow::before { position: absolute; left: 6px; top: 2px; font-family: monospace; font-weight: 700; }
      .ds-ins { background: #e6ffed; }
      .ds-ins::before { content: "+"; color: #15803d; }
      .ds-del { background: #ffeef0; text-decoration: line-through; opacity: .85; }
      .ds-del::before { content: "\\2212"; color: #b91c1c; }
      .ds-eq { color: #6b7785; }
      .ds-eq::before { content: ""; }
      .ds-flash { outline: 2px solid #6366f1; outline-offset: 2px; transition: outline-color .8s; }
    </style>
    </head>
    <body>
    #{content}
    <script>
    window.addEventListener('message', function (e) {
      var d = e.data || {};
      if (d.type === 'ds:goto') {
        var el = document.getElementById('step-' + d.step);
        if (el) {
          el.scrollIntoView({ block: 'center', behavior: 'smooth' });
          el.classList.add('ds-flash');
          setTimeout(function () { el.classList.remove('ds-flash'); }, 1200);
        }
      }
    });
    </script>
    </body>
    </html>
    """
  end

  # Build the sandboxed iframe document: the document's own styles + user
  # content + our own CSS/JS. No user scripts are included.
  defp build_frame(processed_html, head_html) do
    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    #{head_html}
    #{mermaid_head(processed_html)}
    <style>
      html { font-family: ui-sans-serif, system-ui, sans-serif; padding: 8px 16px; color:#18181b; }
      [data-anchor] { position: relative; transition: background .1s, outline .1s; border-radius: 3px; }
      [data-anchor]:hover { outline: 2px solid rgba(99,102,241,.35); cursor: pointer; }
      [data-anchor].ds-selected { outline: 2px solid #6366f1; background: rgba(99,102,241,.08); }
      [data-anchor][data-ds-count]:not([data-ds-count="0"])::after {
        content: attr(data-ds-count);
        position: absolute; top: -8px; right: -8px;
        min-width: 16px; height: 16px; padding: 0 4px;
        background: #6366f1; color: #fff; font-size: 10px; line-height: 16px;
        text-align: center; border-radius: 8px; font-family: sans-serif;
      }
    </style>
    </head>
    <body>
    #{processed_html}
    <script>
    (function () {
      document.body.addEventListener('click', function (e) {
        var el = e.target.closest('[data-anchor]');
        if (!el) return;
        e.preventDefault();
        parent.postMessage({
          type: 'ds:select',
          anchor: el.getAttribute('data-anchor'),
          label: (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 120)
        }, '*');
      });
      window.addEventListener('message', function (e) {
        var d = e.data || {};
        if (d.type === 'ds:counts') {
          var counts = d.counts || {};
          document.querySelectorAll('[data-anchor]').forEach(function (el) {
            el.setAttribute('data-ds-count', counts[el.getAttribute('data-anchor')] || 0);
          });
        } else if (d.type === 'ds:select') {
          document.querySelectorAll('[data-anchor].ds-selected').forEach(function (el) {
            el.classList.remove('ds-selected');
          });
          if (d.anchor) {
            var sel = document.querySelector('[data-anchor="' + d.anchor + '"]');
            if (sel) { sel.classList.add('ds-selected'); sel.scrollIntoView({block:'center', behavior:'smooth'}); }
          }
        }
      });
      parent.postMessage({ type: 'ds:ready' }, '*');
    })();
    </script>
    </body>
    </html>
    """
  end

  # When the document uses Mermaid (e.g. <pre class="mermaid">graph TD; A--&gt;B;</pre>),
  # load Mermaid from a CDN inside the sandboxed frame and auto-render diagrams.
  defp mermaid_head(html) do
    if String.contains?(html, "mermaid") do
      """
      <script type="module">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
        mermaid.initialize({ startOnLoad: true });
      </script>
      """
    else
      ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-7rem)]">
      <div class="flex items-center justify-between pb-3 border-b mb-3 gap-3 flex-wrap">
        <div>
          <.link navigate={~p"/docs"} class="text-sm text-zinc-500 hover:underline">← All documents</.link>
          <h1 class="text-xl font-bold">{@doc.title}</h1>
        </div>

        <div class="flex items-center gap-2">
          <%!-- Version selector --%>
          <form id="version-select" phx-change="select_version">
            <select
              name="id"
              class="rounded-lg border-zinc-300 text-sm py-2 pr-8 focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option
                :for={v <- @versions}
                value={v.id}
                selected={v.id == @version.id}
              >
                {version_option_label(v, @version_counts)}
              </option>
            </select>
          </form>

          <button
            :if={length(@versions) > 1}
            phx-click="toggle_diff"
            title="Compare two versions"
            class="rounded-lg border border-zinc-300 text-zinc-700 px-3 py-2 text-sm font-semibold hover:bg-zinc-50"
          >
            ⇄ Compare
          </button>
          <button
            phx-click="toggle_export"
            title="Copy section + comment pairs to fix the document with an LLM"
            class="rounded-lg border border-zinc-300 text-zinc-700 px-3 py-2 text-sm font-semibold hover:bg-zinc-50"
          >
            ⧉ Export comments
          </button>
          <a
            href={~p"/docs/#{@doc.token}/versions/#{@version.id}/print"}
            target="_blank"
            title="Open a print-ready view — use browser Print → Save as PDF"
            class="rounded-lg border border-zinc-300 text-zinc-700 px-3 py-2 text-sm font-semibold hover:bg-zinc-50"
          >
            ⎙ Print / PDF
          </a>
          <button
            :if={@owner?}
            phx-click="toggle_add_version"
            class="rounded-lg border border-indigo-600 text-indigo-700 px-3 py-2 text-sm font-semibold hover:bg-indigo-50"
          >
            + New version
          </button>
          <button
            :if={@owner?}
            phx-click="toggle_share"
            class="rounded-lg bg-indigo-600 text-white px-3 py-2 text-sm font-semibold hover:bg-indigo-500"
          >
            Share
          </button>
        </div>
      </div>

      <p class="text-xs text-zinc-500 -mt-1 mb-3">
        Viewing <span class="font-semibold">{@version.label}</span>
        (version {@version.version_number} of {length(@versions)}) ·
        comments are specific to this version.
      </p>

      <div
        :if={@port_suggestion}
        class="mb-3 flex items-center justify-between gap-4 rounded-lg border border-indigo-200 bg-indigo-50 px-4 py-2.5 text-sm"
      >
        <span class="text-indigo-800">
          <strong>{@port_suggestion.count}</strong>
          open comment{if @port_suggestion.count != 1, do: "s", else: ""} from
          <strong>{@port_suggestion.from_label}</strong>
          can be ported to <strong>{@port_suggestion.to_label}</strong>.
        </span>
        <div class="flex shrink-0 gap-2">
          <button
            phx-click="port_comments"
            class="rounded-md bg-indigo-600 px-3 py-1 text-xs font-semibold text-white hover:bg-indigo-500"
          >
            Port comments
          </button>
          <button phx-click="dismiss_port" class="text-xs text-indigo-500 hover:text-indigo-700">
            Dismiss
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 flex-1 min-h-0">
        <%!-- Document render --%>
        <div
          class={[
            "border bg-white overflow-hidden",
            if(@fullscreen,
              do: "fixed inset-0 z-50 rounded-none",
              else: "relative lg:col-span-2 rounded-lg min-h-0"
            )
          ]}
          phx-window-keydown={@fullscreen && "toggle_fullscreen"}
          phx-key="Escape"
        >
          <button
            phx-click="toggle_fullscreen"
            title={if @fullscreen, do: "Exit fullscreen (Esc)", else: "Fullscreen"}
            class="absolute top-2 right-2 z-10 rounded-md bg-zinc-900/70 text-white px-2.5 py-1.5 text-xs font-semibold hover:bg-zinc-900"
          >
            {if @fullscreen, do: "✕ Exit fullscreen", else: "⛶ Fullscreen"}
          </button>
          <iframe
            id={"doc-frame-#{@version.id}"}
            phx-hook="DocFrame"
            phx-update="ignore"
            sandbox="allow-scripts"
            allowfullscreen
            srcdoc={@frame}
            class="w-full h-full"
          ></iframe>
        </div>

        <%!-- Comments panel --%>
        <div class="border rounded-lg flex flex-col min-h-0 bg-zinc-50">
          <div class="p-3 border-b bg-white rounded-t-lg">
            <h2 class="font-semibold text-sm">Comments on {@version.label}</h2>
            <p class="text-xs text-zinc-500">Click a part of the document to comment on it.</p>
          </div>

          <div class="flex-1 overflow-y-auto p-3 space-y-4">
            <div :if={@selected_anchor} class="bg-white rounded-lg border p-3">
              <div class="flex items-start justify-between gap-2">
                <p class="text-xs text-indigo-700 font-medium italic line-clamp-2">
                  “{@selected_label}”
                </p>
                <button phx-click="clear_anchor" class="text-xs text-zinc-400 hover:text-zinc-700">✕</button>
              </div>

              <.form for={@comment_form} id="comment-form" phx-submit="add_comment" class="mt-3">
                <div id="comment-editor" phx-hook="CommentToolbar">
                  <div class="flex items-center gap-0.5 rounded-t-md border border-b-0 border-zinc-300 bg-zinc-50 px-1 py-1">
                    <button
                      type="button"
                      data-md="bold"
                      title="Bold"
                      class="rounded px-2 py-1 text-sm font-bold text-zinc-600 hover:bg-zinc-200"
                    >
                      B
                    </button>
                    <button
                      type="button"
                      data-md="italic"
                      title="Italic"
                      class="rounded px-2 py-1 text-sm italic text-zinc-600 hover:bg-zinc-200"
                    >
                      I
                    </button>
                    <button
                      type="button"
                      data-md="code"
                      title="Code"
                      class="rounded px-2 py-1 font-mono text-sm text-zinc-600 hover:bg-zinc-200"
                    >
                      &lt;/&gt;
                    </button>
                    <button
                      type="button"
                      data-md="link"
                      title="Link"
                      class="rounded px-2 py-1 text-sm text-zinc-600 hover:bg-zinc-200"
                    >
                      🔗
                    </button>
                  </div>
                  <textarea
                    name="comment[body]"
                    rows="2"
                    placeholder="Add a comment…"
                    class="w-full rounded-b-md border-zinc-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
                  >{@comment_form[:body].value}</textarea>
                </div>
                <button class="mt-2 w-full rounded-md bg-indigo-600 text-white text-sm font-semibold py-1.5 hover:bg-indigo-500">
                  Comment
                </button>
              </.form>

              <div class="mt-3 space-y-2">
                <.comment_card
                  :for={c <- comments_for(@comments, @selected_anchor)}
                  comment={c}
                  current_user={@current_user}
                  owner?={@owner?}
                />
              </div>
            </div>

            <div :if={!@selected_anchor} class="text-xs text-zinc-400 text-center py-4">
              No part selected.
            </div>

            <div :if={@comments != []}>
              <h3 class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-2">
                All comments on this version ({length(@comments)})
              </h3>
              <div class="space-y-2">
                <button
                  :for={c <- @comments}
                  phx-click="select_anchor"
                  phx-value-anchor={c.anchor}
                  phx-value-label={c.anchor_label}
                  class={[
                    "w-full text-left bg-white rounded-lg border p-2 hover:border-indigo-400",
                    c.resolved && "opacity-50"
                  ]}
                >
                  <p class="text-[11px] text-zinc-400 italic line-clamp-1">“{c.anchor_label}”</p>
                  <p class="text-sm text-zinc-800 line-clamp-2">{c.body}</p>
                  <p class="text-[11px] text-zinc-400">{c.author.email}</p>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Add-version modal --%>
      <div
        :if={@show_add_version}
        class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4"
      >
        <div class="bg-white rounded-xl p-6 w-full max-w-lg" phx-click-away="toggle_add_version">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-bold">Add a new version</h2>
            <button phx-click="toggle_add_version" class="text-zinc-400 hover:text-zinc-700">✕</button>
          </div>

          <.form
            for={@version_form}
            id="version-form"
            phx-change="validate_version"
            phx-submit="add_version"
          >
            <input
              type="text"
              name="version[label]"
              placeholder="Label (optional, e.g. v2)"
              class="w-full rounded-md border-zinc-300 text-sm mb-3 focus:border-indigo-500 focus:ring-indigo-500"
            />

            <div
              class="border-2 border-dashed rounded-lg p-3 mb-3"
              phx-drop-target={@uploads.version_file.ref}
            >
              <.live_file_input upload={@uploads.version_file} class="text-sm" />
              <p class="text-xs text-zinc-500 mt-1">Upload an .html file (overrides pasted HTML).</p>
              <div
                :for={entry <- @uploads.version_file.entries}
                class="mt-2 text-sm flex items-center gap-2"
              >
                <span>{entry.client_name}</span>
                <button
                  type="button"
                  phx-click="cancel-version-upload"
                  phx-value-ref={entry.ref}
                  class="text-red-600"
                >remove</button>
              </div>
            </div>

            <textarea
              name="version[raw_html]"
              rows="8"
              placeholder="…or paste HTML here"
              class="w-full text-sm rounded-md border-zinc-300 focus:border-indigo-500 focus:ring-indigo-500"
            ></textarea>

            <div class="flex justify-end gap-2 mt-3">
              <button type="button" phx-click="toggle_add_version" class="text-sm text-zinc-600">Cancel</button>
              <button class="rounded-md bg-indigo-600 text-white px-4 py-2 text-sm font-semibold hover:bg-indigo-500">
                Add version
              </button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Diff modal (fullscreen for easy tracking) --%>
      <div :if={@show_diff} class="fixed inset-0 bg-black/40 z-50 p-3 sm:p-4">
        <div
          class="bg-white rounded-xl p-5 w-full h-full flex flex-col"
          phx-window-keydown="toggle_diff"
          phx-key="Escape"
        >
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-bold">Compare versions</h2>
            <button phx-click="toggle_diff" class="text-zinc-400 hover:text-zinc-700">✕</button>
          </div>

          <form id="diff-form" phx-change="update_diff" class="flex items-center gap-2 text-sm mb-3">
            <select
              name="a"
              class="rounded-md border-zinc-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option :for={v <- @versions} value={v.id} selected={@diff_a && v.id == @diff_a.id}>
                {v.label}
              </option>
            </select>
            <span class="text-zinc-400">→</span>
            <select
              name="b"
              class="rounded-md border-zinc-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option :for={v <- @versions} value={v.id} selected={@diff_b && v.id == @diff_b.id}>
                {v.label}
              </option>
            </select>
            <span class="ml-auto text-xs flex gap-2">
              <span class="text-green-700">+{Enum.count(@diff, &(elem(&1, 0) == :ins))} added</span>
              <span class="text-red-700">−{Enum.count(@diff, &(elem(&1, 0) == :del))} removed</span>
            </span>
          </form>

          <div class="flex-1 min-h-0 flex gap-3">
            <%!-- Step sidebar: jump to each change --%>
            <nav
              id="diff-nav"
              phx-hook="DiffNav"
              class="w-56 shrink-0 overflow-y-auto rounded-md border bg-zinc-50 p-2 text-xs"
            >
              <p class="font-semibold text-zinc-500 uppercase tracking-wide px-1 mb-1">
                Changes ({length(@diff_steps)})
              </p>
              <div :if={@diff_steps == []} class="text-zinc-400 px-1 py-2">No changes.</div>
              <button
                :for={step <- @diff_steps}
                type="button"
                data-step={step.n}
                class={[
                  "w-full text-left rounded px-2 py-1.5 mb-1 hover:ring-1 hover:ring-indigo-300",
                  step.op == :ins && "bg-green-50 text-green-900",
                  step.op == :del && "bg-red-50 text-red-900 line-through"
                ]}
              >
                <span class="font-mono font-bold mr-1">{if step.op == :ins, do: "+", else: "−"}</span>
                {step.label}
              </button>
            </nav>

            <iframe
              id="diff-frame"
              sandbox="allow-scripts"
              srcdoc={@diff_frame}
              class="flex-1 w-full rounded-md border bg-white"
            ></iframe>
          </div>
        </div>
      </div>

      <%!-- Export modal --%>
      <div
        :if={@show_export}
        class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4"
      >
        <div class="bg-white rounded-xl p-6 w-full max-w-2xl" phx-click-away="toggle_export">
          <div class="flex items-center justify-between mb-1">
            <h2 class="text-lg font-bold">Export comments — {@version.label}</h2>
            <button phx-click="toggle_export" class="text-zinc-400 hover:text-zinc-700">✕</button>
          </div>
          <p class="text-xs text-zinc-500 mb-3">
            Section + comment pairs, ready to paste into an LLM prompt to fix the document.
          </p>

          <textarea
            id="export-text"
            readonly
            rows="14"
            class="w-full text-xs font-mono rounded-md border-zinc-300 bg-zinc-50 focus:border-indigo-500 focus:ring-indigo-500"
          >{@export_text}</textarea>

          <div class="flex justify-end gap-2 mt-3">
            <button type="button" phx-click="toggle_export" class="text-sm text-zinc-600">Close</button>
            <button
              id="copy-export"
              type="button"
              phx-hook="CopyButton"
              data-target="#export-text"
              class="rounded-md bg-indigo-600 text-white px-4 py-2 text-sm font-semibold hover:bg-indigo-500"
            >
              Copy to clipboard
            </button>
          </div>
        </div>
      </div>

      <%!-- Share modal --%>
      <div
        :if={@show_share}
        class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4"
      >
        <div class="bg-white rounded-xl p-6 w-full max-w-md" phx-click-away="toggle_share">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-bold">Share “{@doc.title}”</h2>
            <button phx-click="toggle_share" class="text-zinc-400 hover:text-zinc-700">✕</button>
          </div>

          <.form for={@invite_form} id="invite-form" phx-submit="invite" class="flex gap-2">
            <input
              type="email"
              name="invite[email]"
              placeholder="person@example.com"
              required
              class="flex-1 rounded-md border-zinc-300 text-sm focus:border-indigo-500 focus:ring-indigo-500"
            />
            <button class="rounded-md bg-indigo-600 text-white px-3 text-sm font-semibold hover:bg-indigo-500">
              Invite
            </button>
          </.form>
          <p class="text-xs text-zinc-500 mt-2">
            They get an email with a link. They must sign in with this address to access it.
          </p>

          <h3 class="text-sm font-semibold mt-4 mb-2">People with access</h3>
          <ul class="space-y-1">
            <li class="flex items-center justify-between text-sm">
              <span>{@current_user.email}</span>
              <span class="text-xs text-zinc-400">owner</span>
            </li>
            <li :for={c <- @collaborators} class="flex items-center justify-between text-sm">
              <span>{c.email}</span>
              <button
                phx-click="remove_collaborator"
                phx-value-id={c.id}
                class="text-xs text-red-600 hover:underline"
              >
                remove
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp version_option_label(version, counts) do
    n = Map.get(counts, version.id, 0)
    base = "#{version.label} — #{Calendar.strftime(version.inserted_at, "%Y-%m-%d %H:%M")}"
    if n > 0, do: "#{base} (#{n} 💬)", else: base
  end

  attr :comment, :map, required: true
  attr :current_user, :map, required: true
  attr :owner?, :boolean, required: true

  defp comment_card(assigns) do
    ~H"""
    <div class={["rounded-md border p-2 bg-zinc-50", @comment.resolved && "opacity-60"]}>
      <div class="flex items-center justify-between">
        <span class="text-xs font-semibold text-zinc-700">{@comment.author.email}</span>
        <span class="text-[10px] text-zinc-400">{Calendar.strftime(
          @comment.inserted_at,
          "%b %d %H:%M"
        )}</span>
      </div>
      <p class="text-sm text-zinc-800 whitespace-pre-wrap mt-1">{format_comment(@comment.body)}</p>
      <div class="flex gap-3 mt-1">
        <button
          phx-click="toggle_resolved"
          phx-value-id={@comment.id}
          class="text-[11px] text-zinc-500 hover:underline"
        >
          {if @comment.resolved, do: "Reopen", else: "Resolve"}
        </button>
        <button
          :if={@comment.author_id == @current_user.id or @owner?}
          phx-click="delete_comment"
          phx-value-id={@comment.id}
          class="text-[11px] text-red-600 hover:underline"
        >
          Delete
        </button>
      </div>
    </div>
    """
  end
end
