defmodule DocshareWeb.DocumentController do
  use DocshareWeb, :controller

  alias Docshare.Documents
  alias Docshare.Documents.Html

  def print(conn, %{"token" => token, "version_id" => version_id}) do
    doc = Documents.get_document_by_token!(token)

    if Documents.can_access?(doc, conn.assigns.current_user) do
      render_print(conn, doc, version_id)
    else
      conn
      |> put_flash(:error, "You don't have access to that document.")
      |> redirect(to: ~p"/docs")
    end
  end

  def public_print(conn, %{"public_token" => token, "version_id" => version_id}) do
    case Documents.get_public_document(token) do
      nil ->
        conn
        |> put_flash(:error, "This shared document is not available.")
        |> redirect(to: ~p"/")

      doc ->
        render_print(conn, doc, version_id)
    end
  end

  defp render_print(conn, doc, version_id) do
    version = Documents.get_version!(version_id)

    if version.document_id == doc.id do
      {body_html, _anchors, head_html} = Html.process(version.raw_html)

      render(conn, :print,
        layout: false,
        doc: doc,
        version: version,
        body_html: body_html,
        head_html: head_html,
        has_mermaid: String.contains?(body_html, "mermaid")
      )
    else
      conn
      |> put_flash(:error, "Version not found for this document.")
      |> redirect(to: ~p"/")
    end
  end
end
