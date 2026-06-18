defmodule Docshare.Documents.Html do
  @moduledoc """
  Parses user-supplied HTML, strips dangerous content, and tags each
  block-level "part" with a stable `data-anchor` attribute so comments can be
  anchored to it.

  `process/1` returns `{body_html, anchors, head_html}`:

    * `body_html`  – the sanitized, anchored body content
    * `anchors`    – `[%{id: "b3", label: "..."}]` in document order
    * `head_html`  – `<style>`/`<link rel=stylesheet>` pulled from the original
      document so the page keeps its styling when re-rendered
  """

  # Tags that become individually-commentable "parts".
  @block_tags ~w(p h1 h2 h3 h4 h5 h6 li blockquote pre td th figcaption dd dt summary)

  # Tags removed entirely from user content (we inject our own script).
  @drop_tags ~w(script noscript iframe object embed)

  def process(raw_html) when is_binary(raw_html) do
    doc = Floki.parse_document!(raw_html)

    head_html = collect_head(doc)

    body_nodes =
      case Floki.find(doc, "body") do
        [{"body", _, children} | _] -> children
        _ -> doc
      end

    {tree, _counter, anchors} = walk(body_nodes, 0, [])
    {Floki.raw_html(tree, encode: false), Enum.reverse(anchors), head_html}
  end

  @doc """
  Returns the document's leaf block elements in order as
  `[%{text: "...", html: "<p>...</p>"}]`. `html` is sanitized and carries no
  `data-anchor`, so unchanged blocks compare byte-for-byte across versions
  (used for rendered version diffs).
  """
  def blocks(raw_html) when is_binary(raw_html) do
    doc = Floki.parse_document!(raw_html)

    body =
      case Floki.find(doc, "body") do
        [{"body", _, children} | _] -> children
        _ -> doc
      end

    collect_blocks(body, []) |> Enum.reverse()
  end

  defp collect_blocks(nodes, acc) when is_list(nodes),
    do: Enum.reduce(nodes, acc, &collect_blocks/2)

  defp collect_blocks({:comment, _}, acc), do: acc
  defp collect_blocks({tag, _, _}, acc) when tag in @drop_tags, do: acc

  defp collect_blocks({tag, attrs, children}, acc) do
    if tag in @block_tags and not has_block_child?(children) do
      node = {tag, sanitize_attrs(attrs), children}
      [%{text: text_of(children), html: Floki.raw_html(node, encode: false)} | acc]
    else
      collect_blocks(children, acc)
    end
  end

  defp collect_blocks(_other, acc), do: acc

  defp has_block_child?(nodes), do: Enum.any?(nodes, &block_node?/1)
  defp block_node?({tag, _, children}), do: tag in @block_tags or has_block_child?(children)
  defp block_node?(_), do: false

  # Keep the document's own stylesheets so it renders as designed.
  defp collect_head(doc) do
    styles = Floki.find(doc, "style")
    links = Floki.find(doc, "link[rel=stylesheet]")
    Floki.raw_html(styles ++ links, encode: false)
  end

  defp walk(nodes, counter, anchors) when is_list(nodes) do
    Enum.reduce(nodes, {[], counter, anchors}, fn node, {acc, c, a} ->
      {n, c2, a2} = walk(node, c, a)
      {acc ++ List.wrap(n), c2, a2}
    end)
  end

  defp walk({:comment, _}, counter, anchors), do: {[], counter, anchors}

  defp walk({tag, _attrs, _children}, counter, anchors) when tag in @drop_tags do
    {[], counter, anchors}
  end

  defp walk({tag, attrs, children}, counter, anchors) do
    attrs = sanitize_attrs(attrs)

    if tag in @block_tags do
      id = "b#{counter}"
      text = text_of(children)
      anchor = %{id: id, label: String.slice(text, 0, 120), text: text, tag: to_string(tag)}
      attrs = [{"data-anchor", id} | attrs]
      {kids, c2, a2} = walk(children, counter + 1, [anchor | anchors])
      {{tag, attrs, kids}, c2, a2}
    else
      {kids, c2, a2} = walk(children, counter, anchors)
      {{tag, attrs, kids}, c2, a2}
    end
  end

  defp walk(text, counter, anchors) when is_binary(text), do: {text, counter, anchors}
  defp walk(other, counter, anchors), do: {other, counter, anchors}

  # Strip event handlers and javascript: urls.
  defp sanitize_attrs(attrs) do
    attrs
    |> Enum.reject(fn {name, _} -> String.starts_with?(String.downcase(name), "on") end)
    |> Enum.map(fn {name, value} ->
      down = String.downcase(name)

      if down in ["href", "src", "action"] and
           String.starts_with?(String.trim(String.downcase(value)), "javascript:") do
        {name, "#"}
      else
        {name, value}
      end
    end)
  end

  defp text_of(nodes) do
    nodes
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Builds the sandboxed-iframe `srcdoc` for a processed document: the document's
  own styles + sanitized content + our own CSS/JS. No user scripts run.

  Options:

    * `:interactive` (default `true`) — when `false`, omits the comment-anchor
      affordances and the LiveView select/counts bridge, producing a read-only
      view (used by public share links). Mermaid diagram click-to-zoom is
      available in both modes.
  """
  def frame(processed_html, head_html, opts \\ []) do
    interactive? = Keyword.get(opts, :interactive, true)

    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    #{head_html}
    #{mermaid_head(processed_html)}
    <style>
      html { font-family: ui-sans-serif, system-ui, sans-serif; padding: 8px 16px; color:#18181b; }
      #{anchor_css(interactive?)}
      .mermaid { cursor: zoom-in; }
      .ds-zoom-overlay {
        position: fixed; inset: 0; z-index: 9999;
        background: #e5e7eb;
        display: flex; align-items: center; justify-content: center; overflow: hidden;
      }
      .ds-zoom-canvas {
        transform-origin: center center; cursor: grab;
        will-change: transform; touch-action: none;
        display: flex; align-items: center; justify-content: center;
      }
      .ds-zoom-canvas.dragging { cursor: grabbing; }
      /* Fill the viewport; the viewBox keeps it crisp at any size. */
      .ds-zoom-canvas svg {
        width: 92vw !important; height: 90vh !important;
        max-width: none !important; max-height: none !important;
        display: block;
      }
      .ds-zoom-bar {
        position: fixed; bottom: 16px; left: 50%; transform: translateX(-50%);
        display: flex; gap: 6px; z-index: 10000;
      }
      .ds-zoom-bar button {
        background: #fff; border: 1px solid #d4d4d8; border-radius: 6px;
        width: 34px; height: 34px; font-size: 17px; line-height: 1; cursor: pointer;
        color: #18181b; font-family: sans-serif; box-shadow: 0 1px 2px rgba(0,0,0,.12);
        display: inline-flex; align-items: center; justify-content: center; padding: 0;
      }
      .ds-zoom-bar button:hover { background: #f4f4f5; }
      .ds-zoom-hint {
        position: fixed; bottom: 60px; left: 50%; transform: translateX(-50%);
        color: #52525b; font-size: 11px; font-family: sans-serif; z-index: 10000;
        background: rgba(255,255,255,.75); padding: 3px 10px; border-radius: 999px;
      }
    </style>
    </head>
    <body>
    #{processed_html}
    <script>
    (function () {
      // --- Mermaid diagram zoom lightbox ---
      var zoom = null;
      function applyZoom() {
        if (!zoom) return;
        zoom.canvas.style.transform =
          'translate(' + zoom.tx + 'px,' + zoom.ty + 'px) scale(' + zoom.scale + ')';
      }
      function closeZoom() {
        if (zoom) { zoom.overlay.remove(); zoom = null; }
      }
      function setScale(s) {
        zoom.scale = Math.min(Math.max(s, 0.25), 8);
        applyZoom();
      }
      function openZoom(svg) {
        closeZoom();
        var overlay = document.createElement('div');
        overlay.className = 'ds-zoom-overlay';
        var canvas = document.createElement('div');
        canvas.className = 'ds-zoom-canvas';
        canvas.appendChild(svg.cloneNode(true));
        var bar = document.createElement('div');
        bar.className = 'ds-zoom-bar';
        bar.innerHTML =
          '<button type="button" data-z="out" title="Zoom out">\\u2212</button>' +
          '<button type="button" data-z="in" title="Zoom in">+</button>' +
          '<button type="button" data-z="reset" title="Reset">\\u21BA</button>' +
          '<button type="button" data-z="close" title="Close (Esc)">\\u2715</button>';
        var hint = document.createElement('div');
        hint.className = 'ds-zoom-hint';
        hint.textContent = 'Scroll to zoom \\u00B7 drag to pan \\u00B7 Esc to close';
        overlay.appendChild(canvas);
        overlay.appendChild(bar);
        overlay.appendChild(hint);
        document.body.appendChild(overlay);
        zoom = { overlay: overlay, canvas: canvas, scale: 1, tx: 0, ty: 0 };
        applyZoom();

        overlay.addEventListener('click', function (e) { if (e.target === overlay) closeZoom(); });
        bar.addEventListener('click', function (e) {
          var b = e.target.closest('button'); if (!b) return;
          var z = b.getAttribute('data-z');
          if (z === 'in') setScale(zoom.scale * 1.25);
          else if (z === 'out') setScale(zoom.scale / 1.25);
          else if (z === 'reset') { zoom.scale = 1; zoom.tx = 0; zoom.ty = 0; applyZoom(); }
          else if (z === 'close') closeZoom();
        });
        overlay.addEventListener('wheel', function (e) {
          e.preventDefault();
          setScale(zoom.scale * (e.deltaY < 0 ? 1.1 : 1 / 1.1));
        }, { passive: false });

        var dragging = false, sx = 0, sy = 0;
        canvas.addEventListener('pointerdown', function (e) {
          dragging = true; sx = e.clientX - zoom.tx; sy = e.clientY - zoom.ty;
          canvas.classList.add('dragging'); canvas.setPointerCapture(e.pointerId);
        });
        canvas.addEventListener('pointermove', function (e) {
          if (!dragging) return;
          zoom.tx = e.clientX - sx; zoom.ty = e.clientY - sy; applyZoom();
        });
        canvas.addEventListener('pointerup', function () {
          dragging = false; canvas.classList.remove('dragging');
        });
      }
      window.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeZoom(); });

      document.body.addEventListener('click', function (e) {
        var mer = e.target.closest('.mermaid');
        if (mer) {
          var svg = mer.querySelector('svg');
          if (svg) { e.preventDefault(); openZoom(svg); return; }
        }
        #{select_js(interactive?)}
      });
      #{bridge_js(interactive?)}
    })();
    </script>
    </body>
    </html>
    """
  end

  defp anchor_css(false), do: ""

  defp anchor_css(true) do
    """
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
    """
  end

  defp select_js(false), do: ""

  defp select_js(true) do
    """
    var el = e.target.closest('[data-anchor]');
    if (!el) return;
    e.preventDefault();
    parent.postMessage({
      type: 'ds:select',
      anchor: el.getAttribute('data-anchor'),
      label: (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 120)
    }, '*');
    """
  end

  defp bridge_js(false), do: ""

  defp bridge_js(true) do
    """
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
end
