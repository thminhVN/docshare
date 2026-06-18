# Seeds the k_sync report as an example document. Idempotent.
#   mix run priv/repo/demo_seed.exs
alias Docshare.{Accounts, Documents, Repo}
alias Docshare.Documents.Document

file = "/Users/minh/Downloads/reverse_engineering_k_sync_v1.html"
html = File.read!(file)

title =
  case Regex.run(~r/<title[^>]*>(.*?)<\/title>/is, html) do
    [_, t] -> String.trim(t)
    _ -> "k_sync report"
  end

email = "demo@docshare.local"
password = "demopassword123"

owner =
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, u} = Accounts.register_user(%{email: email, password: password})
      u

    u ->
      u
  end

# Reuse an existing demo doc with this title if present, else create it.
doc =
  Repo.get_by(Document, owner_id: owner.id, title: title) ||
    (
      {:ok, d} =
        Documents.create_document(owner, %{
          "title" => title,
          "raw_html" => html,
          "label" => "v1"
        })

      d
    )

version = Documents.latest_version(doc)

# Add a couple of example comments on the first parts (only if none yet).
if Documents.list_comments(version) == [] do
  {_processed, anchors, _head} = Documents.Html.process(html)

  for {anchor, body} <-
        Enum.zip(
          Enum.map(Enum.take(anchors, 2), & &1.id),
          ["Phần này cần làm rõ phạm vi.", "Bổ sung sơ đồ luồng dữ liệu ở đây."]
        ) do
    Documents.create_comment(version, owner, %{
      "body" => body,
      "anchor" => anchor,
      "anchor_label" => "(seed)"
    })
  end
end

IO.puts("""

✅ Demo ready.
   Login:    #{email}  /  #{password}
   Document: #{title}
   URL:      http://localhost:4000/docs/#{doc.token}
   Versions: #{length(Documents.list_versions(doc))}  ·  v1 comments: #{length(Documents.list_comments(version))}
""")
