defmodule DocshareWeb.DocumentLiveTest do
  use DocshareWeb.ConnCase

  import Phoenix.LiveViewTest
  import Docshare.AccountsFixtures
  import Swoosh.TestAssertions

  alias Docshare.Documents

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp create_doc(user) do
    {:ok, doc} =
      Documents.create_document(user, %{
        "title" => "Test Doc",
        "raw_html" => "<h1>Hello</h1><p>World</p>"
      })

    doc
  end

  test "index lists owned documents", %{conn: conn, user: user} do
    create_doc(user)
    {:ok, _view, html} = live(conn, ~p"/docs")
    assert html =~ "My documents"
    assert html =~ "Test Doc"
    assert html =~ "Owned by you"
  end

  test "new document form creates and redirects to show", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/new")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("form",
               document: %{title: "Pasted", raw_html: "<h1>Hi</h1><p>there</p>"}
             )
             |> render_submit()

    assert to =~ "/docs/"
    {:ok, _show, html} = live(conn, to)
    assert html =~ "Pasted"
    # Renders the doc in a sandboxed iframe
    assert html =~ ~s(sandbox="allow-scripts")
    assert html =~ "doc-frame"
  end

  test "selecting a part and commenting works in real time", %{conn: conn, user: user} do
    doc = create_doc(user)
    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")

    # Simulate the iframe telling us a part was clicked.
    render_hook(view, "select_anchor", %{"anchor" => "b0", "label" => "Hello"})

    html =
      view
      |> form("#comment-form", comment: %{body: "Nice heading"})
      |> render_submit()

    assert html =~ "Nice heading"
    version = Documents.latest_version(doc)
    assert [%{body: "Nice heading", anchor: "b0"}] = Documents.list_comments(version)
  end

  test "versions are independent: switching shows that version's comments", %{
    conn: conn,
    user: user
  } do
    doc = create_doc(user)
    v1 = Documents.latest_version(doc)

    {:ok, v2} =
      Documents.add_version(doc, user, %{"label" => "v2", "raw_html" => "<p>Second draft</p>"})

    # Comment on v1.
    {:ok, _} =
      Documents.create_comment(v1, user, %{
        "body" => "on v1",
        "anchor" => "b0",
        "anchor_label" => "Hello"
      })

    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")
    # Latest version (v2) is shown by default and has no comments yet.
    assert render(view) =~ "Comments on v2"
    refute render(view) =~ "on v1"

    # Switch to v1 and its comment appears.
    html =
      view
      |> form("form[phx-change=select_version]", id: v1.id)
      |> render_change()

    assert html =~ "Comments on v1"
    assert html =~ "on v1"
    assert [] = Documents.list_comments(v2)
  end

  test "owner can invite a collaborator by email", %{conn: conn, user: user} do
    doc = create_doc(user)
    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")

    # Open the Share modal so the invite form is rendered.
    view |> element("button", "Share") |> render_click()

    html =
      view
      |> form("#invite-form", invite: %{email: "friend@example.com"})
      |> render_submit()

    assert html =~ "Invitation sent to friend@example.com"
    assert [%{email: "friend@example.com"}] = Documents.list_collaborators(doc)

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn
               {_name, "friend@example.com"} -> true
               "friend@example.com" -> true
               _other -> false
             end)

      assert email.from == {"DocShare", "noreply@gatetroy.com"}
      assert email.text_body =~ "/docs/#{doc.token}?invited_email=friend%40example.com"
      assert email.html_body =~ "/docs/#{doc.token}?invited_email=friend%40example.com"
    end)
  end

  test "emailed document URL redirects logged-out users to login with return_to", %{user: user} do
    doc = create_doc(user)

    conn = get(build_conn(), ~p"/docs/#{doc.token}?invited_email=friend@example.com")

    assert redirected_to(conn) ==
             "/users/log_in?return_to=%2Fdocs%2F#{doc.token}%3Finvited_email%3Dfriend%40example.com"

    assert get_session(conn, :user_return_to) ==
             "/docs/#{doc.token}?invited_email=friend@example.com"
  end

  test "owner can resend an invitation to an existing collaborator", %{conn: conn, user: user} do
    doc = create_doc(user)
    assert {:ok, _collaborator} = Documents.invite_collaborator(doc, user, "friend@example.com")

    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")
    view |> element("button", "Share") |> render_click()

    html =
      view
      |> form("#invite-form", invite: %{email: "friend@example.com"})
      |> render_submit()

    assert html =~ "Invitation sent to friend@example.com"
    assert [%{email: "friend@example.com"}] = Documents.list_collaborators(doc)

    assert_email_sent(to: "friend@example.com")
  end

  test "removing a collaborator revokes access but keeps their comments", %{
    conn: conn,
    user: user
  } do
    collaborator = user_fixture(%{email: "friend@example.com"})
    doc = create_doc(user)
    version = Documents.latest_version(doc)

    assert {:ok, _collaborator} = Documents.invite_collaborator(doc, user, collaborator.email)

    assert {:ok, _comment} =
             Documents.create_comment(version, collaborator, %{
               "body" => "Please clarify this section",
               "anchor" => "b0",
               "anchor_label" => "Hello"
             })

    [collaborator_access] = Documents.list_collaborators(doc)
    assert :ok = Documents.remove_collaborator(collaborator_access)

    refute Documents.can_access?(doc, collaborator)

    assert [%{body: "Please clarify this section", author: %{email: "friend@example.com"}}] =
             Documents.list_comments(version)

    {:ok, _owner_view, html} = live(conn, ~p"/docs/#{doc.token}")
    assert html =~ "Please clarify this section"
    assert html =~ "friend@example.com"

    collaborator_conn = log_in_user(build_conn(), collaborator)
    assert {:error, {:redirect, %{to: "/docs"}}} = live(collaborator_conn, ~p"/docs/#{doc.token}")
  end

  test "mermaid diagrams get the renderer injected into the frame", %{conn: conn, user: user} do
    {:ok, doc} =
      Documents.create_document(user, %{
        "title" => "Diagram",
        "raw_html" => ~s(<h1>Flow</h1><pre class="mermaid">graph TD; A--&gt;B;</pre>)
      })

    {:ok, _view, html} = live(conn, ~p"/docs/#{doc.token}")
    assert html =~ "mermaid.esm.min.mjs"
    assert html =~ "startOnLoad"
  end

  test "owner can add a version by uploading a file", %{conn: conn, user: user} do
    doc = create_doc(user)
    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")

    view |> element("button", "+ New version") |> render_click()

    file =
      file_input(view, "#version-form", :version_file, [
        %{name: "v2.html", content: "<h1>Second draft</h1>", type: "text/html"}
      ])

    render_upload(file, "v2.html")
    view |> form("#version-form", version: %{label: "v2"}) |> render_submit()

    versions = Documents.list_versions(doc)
    assert Enum.any?(versions, &(&1.label == "v2" and &1.raw_html =~ "Second draft"))
  end

  test "export pairs each section's content with its comments", %{conn: conn, user: user} do
    doc = create_doc(user)
    version = Documents.latest_version(doc)

    {:ok, _} =
      Documents.create_comment(version, user, %{
        "body" => "Make this clearer",
        "anchor" => "b0",
        "anchor_label" => "Hello"
      })

    # Context builder produces the section + comment pairing.
    text = Documents.export_comments(doc, version)
    assert text =~ "Section <h1>"
    assert text =~ "Hello"
    assert text =~ "Make this clearer — #{user.email}"
    assert text =~ "Return the full updated HTML"

    # And the UI exposes it via the export modal + copy button.
    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")
    html = view |> element("button", "Export comments") |> render_click()
    assert html =~ "Make this clearer"
    assert html =~ ~s(phx-hook="CopyButton")
  end

  test "can show a rendered diff between two versions", %{conn: conn, user: user} do
    doc = create_doc(user)

    {:ok, _v2} =
      Documents.add_version(doc, user, %{
        "label" => "v2",
        "raw_html" => "<h1>Hello</h1><p>Changed world</p>"
      })

    # Block-level diff: shared heading equal, paragraph changed (del + ins),
    # carrying rendered HTML rather than source.
    [v2, v1] = Documents.list_versions(doc)
    diff = Documents.diff_version_blocks(v1, v2)
    assert {:eq, %{html: "<h1>Hello</h1>"}} = Enum.find(diff, &(elem(&1, 0) == :eq))
    assert Enum.any?(diff, &(&1 == {:del, %{text: "World", html: "<p>World</p>"}}))

    assert Enum.any?(
             diff,
             &(&1 == {:ins, %{text: "Changed world", html: "<p>Changed world</p>"}})
           )

    # UI: Compare button opens a modal that renders the redline in an iframe.
    {:ok, view, _html} = live(conn, ~p"/docs/#{doc.token}")
    html = view |> element("button", "Compare") |> render_click()
    assert html =~ "Compare versions"
    assert html =~ "id=\"diff-frame\""
    # srcdoc carries the rendered blocks with diff classes.
    assert html =~ "ds-ins"
    assert html =~ "ds-del"
    assert html =~ "Changed world"
    # Step sidebar lists each change and is wired to jump.
    assert html =~ "id=\"diff-nav\""
    assert html =~ ~s(phx-hook="DiffNav")
    assert html =~ "Changes (2)"
    assert html =~ ~s(data-step="0")
  end

  test "document detail can toggle fullscreen", %{conn: conn, user: user} do
    doc = create_doc(user)
    {:ok, view, html} = live(conn, ~p"/docs/#{doc.token}")
    assert html =~ "Fullscreen"

    html = view |> element("button", "Fullscreen") |> render_click()
    assert html =~ "Exit fullscreen"
    assert html =~ "fixed inset-0 z-50"

    html = view |> element("button", "Exit fullscreen") |> render_click()
    refute html =~ "Exit fullscreen"
  end

  test "non-collaborator is denied access", %{conn: conn} do
    other = user_fixture()
    doc = create_doc(other)

    assert {:error, {:redirect, %{to: "/docs"}}} = live(conn, ~p"/docs/#{doc.token}")
  end
end
