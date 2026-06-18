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
end
