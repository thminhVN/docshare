defmodule DocshareWeb.DocumentController do
  use DocshareWeb, :controller

  alias Docshare.Documents
  alias Docshare.Documents.Html

  def print(conn, %{"token" => token, "version_id" => version_id}) do
    doc = Documents.get_document_by_token!(token)

    if Documents.can_access?(doc, conn.assigns.current_user) do
      version = Documents.get_version!(version_id)
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
      |> put_flash(:error, "You don't have access to that document.")
      |> redirect(to: ~p"/docs")
    end
  end
end
