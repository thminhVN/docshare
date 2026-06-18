defmodule Docshare.Documents do
  @moduledoc """
  The Documents context: hosting HTML docs, sharing them by email, and
  per-part commenting.
  """

  import Ecto.Query, warn: false
  alias Docshare.Repo
  alias Docshare.Accounts.User
  alias Docshare.Documents.{Document, Version, Collaborator, Comment, Notifier, Html}

  @pubsub Docshare.PubSub

  ## Documents

  @doc "Documents the user owns or has been invited to (by email)."
  def list_documents_for_user(%User{} = user) do
    email = String.downcase(user.email)

    owned =
      from(d in Document, where: d.owner_id == ^user.id)

    shared =
      from(d in Document,
        join: c in Collaborator,
        on: c.document_id == d.id,
        where: fragment("lower(?)", c.email) == ^email
      )

    union_all(owned, ^shared)
    |> subquery()
    |> order_by([d], desc: d.updated_at)
    |> Repo.all()
    |> Enum.uniq_by(& &1.id)
  end

  def get_document!(id), do: Repo.get!(Document, id)

  def get_document_by_token!(token), do: Repo.get_by!(Document, token: token)

  @doc """
  Creates a document together with its first version (v1). `attrs` must include
  `"title"` and `"raw_html"`, and may include a `"label"` for the version.
  """
  def create_document(%User{} = user, attrs) do
    label = Map.get(attrs, "label") || "v1"
    raw_html = Map.get(attrs, "raw_html")

    Repo.transaction(fn ->
      doc =
        %Document{owner_id: user.id}
        |> Document.changeset(attrs)
        |> Repo.insert!()

      %Version{document_id: doc.id, created_by_id: user.id}
      |> Version.changeset(%{
        "document_id" => doc.id,
        "created_by_id" => user.id,
        "version_number" => 1,
        "label" => label,
        "raw_html" => raw_html
      })
      |> Repo.insert!()

      doc
    end)
  rescue
    e in Ecto.InvalidChangesetError -> {:error, e.changeset}
  end

  def update_document(%Document{} = document, attrs) do
    document
    |> Document.changeset(attrs)
    |> Repo.update()
  end

  def delete_document(%Document{} = document), do: Repo.delete(document)

  def change_document(%Document{} = document, attrs \\ %{}),
    do: Document.changeset(document, attrs)

  ## Versions

  @doc "All versions of a document, newest first."
  def list_versions(%Document{} = doc) do
    from(v in Version, where: v.document_id == ^doc.id, order_by: [desc: v.version_number])
    |> Repo.all()
  end

  def get_version!(id), do: Repo.get!(Version, id)

  def get_version_by_number!(%Document{} = doc, number) do
    Repo.get_by!(Version, document_id: doc.id, version_number: number)
  end

  def latest_version(%Document{} = doc) do
    from(v in Version,
      where: v.document_id == ^doc.id,
      order_by: [desc: v.version_number],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Builds a plain-text export pairing each commented section's content with its
  comments, formatted to paste into an LLM prompt to revise the document.
  """
  def export_comments(%Document{} = doc, %Version{} = version) do
    {_body, anchors, _head} = Html.process(version.raw_html)
    text_by_anchor = Map.new(anchors, &{&1.id, &1})

    grouped =
      version
      |> list_comments()
      |> Enum.group_by(& &1.anchor)

    # Keep document order, only sections that have comments.
    items =
      anchors
      |> Enum.filter(&Map.has_key?(grouped, &1.id))
      |> Enum.with_index(1)
      |> Enum.map(fn {anchor, idx} ->
        section = Map.get(text_by_anchor, anchor.id)
        comments = grouped[anchor.id]

        comment_lines =
          comments
          |> Enum.map(fn c ->
            status = if c.resolved, do: " [resolved]", else: ""
            "  - #{c.body} — #{c.author.email}#{status}"
          end)
          |> Enum.join("\n")

        """
        [#{idx}] Section <#{section.tag}>
        Section content:
        \"\"\"
        #{section.text}
        \"\"\"
        Comment(s):
        #{comment_lines}
        """
      end)

    header = """
    You are revising an HTML document titled "#{doc.title}" (version #{version.label}).
    Below are reviewer comments. Each item shows the exact section text a comment
    refers to, followed by the comment(s). Update the document to address every
    comment, preserving the existing structure and styling. Return the full updated HTML.

    ========================================
    """

    body =
      case items do
        [] -> "(No comments on this version yet.)\n"
        _ -> Enum.join(items, "\n----------------------------------------\n")
      end

    header <> "\n" <> body
  end

  @doc """
  Block-level diff between two versions for *rendered* display. Returns an
  ordered list of `{:eq | :del | :ins, %{text, html}}` blocks.
  """
  def diff_version_blocks(%Version{} = a, %Version{} = b) do
    List.myers_difference(Html.blocks(a.raw_html), Html.blocks(b.raw_html))
    |> Enum.flat_map(fn {op, items} -> Enum.map(items, &{op, &1}) end)
  end

  @doc "Combined `<style>`/`<link>` head of both versions, for the diff frame."
  def diff_head(%Version{} = a, %Version{} = b) do
    {_b, _a2, head_a} = Html.process(a.raw_html)
    {_b2, _a3, head_b} = Html.process(b.raw_html)
    head_a <> head_b
  end

  @doc "Adds a new version (auto-incremented number) to a document."
  def add_version(%Document{} = doc, %User{} = user, attrs) do
    next = ((latest_version(doc) && latest_version(doc).version_number) || 0) + 1
    label = Map.get(attrs, "label")
    label = if label in [nil, ""], do: "v#{next}", else: label

    result =
      %Version{document_id: doc.id, created_by_id: user.id}
      |> Version.changeset(%{
        "document_id" => doc.id,
        "created_by_id" => user.id,
        "version_number" => next,
        "label" => label,
        "raw_html" => Map.get(attrs, "raw_html")
      })
      |> Repo.insert()

    case result do
      {:ok, version} ->
        touch_document(doc)
        broadcast(doc.id, {:version_created, version})
        {:ok, version}

      error ->
        error
    end
  end

  defp touch_document(%Document{} = doc) do
    from(d in Document, where: d.id == ^doc.id)
    |> Repo.update_all(set: [updated_at: DateTime.utc_now() |> DateTime.truncate(:second)])
  end

  @doc "Owner has full control; invited emails get commenter access."
  def owner?(%Document{} = doc, %User{} = user), do: doc.owner_id == user.id

  def can_access?(%Document{} = doc, %User{} = user) do
    owner?(doc, user) or collaborator?(doc, user)
  end

  defp collaborator?(%Document{} = doc, %User{} = user) do
    email = String.downcase(user.email)

    Repo.exists?(
      from c in Collaborator,
        where: c.document_id == ^doc.id and fragment("lower(?)", c.email) == ^email
    )
  end

  ## Collaborators / sharing

  def list_collaborators(%Document{} = doc) do
    from(c in Collaborator, where: c.document_id == ^doc.id, order_by: [asc: c.inserted_at])
    |> Repo.all()
  end

  @doc """
  Invites `email` to the document and emails them an invitation link.
  Links an existing user account if one matches the email.
  """
  def invite_collaborator(%Document{} = doc, %User{} = inviter, email, role \\ "commenter") do
    email = String.downcase(String.trim(email || ""))

    with {:ok, collaborator} <- get_or_insert_collaborator(doc, email, role),
         {:ok, _email} <- Notifier.deliver_invitation(collaborator, doc, inviter) do
      broadcast(doc.id, {:collaborators_changed, doc.id})
      {:ok, collaborator}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, {:email_delivery_failed, reason}}
    end
  end

  defp get_or_insert_collaborator(%Document{} = doc, email, role) do
    case Repo.get_by(Collaborator, document_id: doc.id, email: email) do
      %Collaborator{} = collaborator ->
        {:ok, collaborator}

      nil ->
        user = Repo.get_by(User, email: email)

        %Collaborator{document_id: doc.id}
        |> Collaborator.changeset(%{
          email: email,
          role: role,
          document_id: doc.id,
          user_id: user && user.id
        })
        |> Repo.insert()
        |> case do
          {:ok, collaborator} ->
            {:ok, collaborator}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  def remove_collaborator(%Collaborator{} = collaborator) do
    {:ok, _} = Repo.delete(collaborator)
    broadcast(collaborator.document_id, {:collaborators_changed, collaborator.document_id})
    :ok
  end

  def get_collaborator!(id), do: Repo.get!(Collaborator, id)

  ## Comments (scoped to a version)

  def list_comments(%Version{} = version) do
    from(c in Comment,
      where: c.version_id == ^version.id,
      order_by: [asc: c.inserted_at],
      preload: [:author]
    )
    |> Repo.all()
  end

  @doc "Map of anchor id => count for a version, for the comment badges."
  def comment_counts(%Version{} = version) do
    from(c in Comment,
      where: c.version_id == ^version.id and c.resolved == false,
      group_by: c.anchor,
      select: {c.anchor, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count of open comments per version, for the version selector."
  def comment_counts_by_version(%Document{} = doc) do
    from(c in Comment,
      where: c.document_id == ^doc.id and c.resolved == false,
      group_by: c.version_id,
      select: {c.version_id, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def create_comment(%Version{} = version, %User{} = author, attrs) do
    merged =
      Map.merge(attrs, %{
        "document_id" => version.document_id,
        "version_id" => version.id,
        "author_id" => author.id
      })

    result =
      %Comment{}
      |> Comment.changeset(merged)
      |> Repo.insert()

    case result do
      {:ok, comment} ->
        comment = Repo.preload(comment, :author)
        broadcast(version.document_id, {:comment_created, comment})
        {:ok, comment}

      error ->
        error
    end
  end

  def get_comment!(id), do: Repo.get!(Comment, id) |> Repo.preload(:author)

  def delete_comment(%Comment{} = comment) do
    {:ok, _} = Repo.delete(comment)
    broadcast(comment.document_id, {:comment_deleted, comment})
    :ok
  end

  def toggle_resolved(%Comment{} = comment) do
    {:ok, comment} =
      comment
      |> Comment.changeset(%{"resolved" => !comment.resolved})
      |> Repo.update()

    comment = Repo.preload(comment, :author)
    broadcast(comment.document_id, {:comment_updated, comment})
    {:ok, comment}
  end

  ## Anchor porting

  # Blocks whose text similarity is at least this are considered the same block.
  @similarity_threshold 0.85

  @doc """
  Maps anchor ids from `old_v` to the closest matching anchor ids in `new_v`
  using Jaro distance on block text. Greedy bipartite match — each anchor is
  used at most once on each side. Only pairs with similarity ≥
  #{@similarity_threshold} are included.
  """
  def compute_anchor_mapping(%Version{} = old_v, %Version{} = new_v) do
    {_body, old_anchors, _head} = Html.process(old_v.raw_html)
    {_body, new_anchors, _head} = Html.process(new_v.raw_html)

    for(old <- old_anchors, new <- new_anchors,
      do: {String.jaro_distance(old.text, new.text), old.id, new.id}
    )
    |> Enum.sort_by(&(-elem(&1, 0)))
    |> Enum.reduce({%{}, MapSet.new()}, fn {sim, old_id, new_id}, {mapping, used} ->
      if sim >= @similarity_threshold and not Map.has_key?(mapping, old_id) and
           not MapSet.member?(used, new_id) do
        {Map.put(mapping, old_id, new_id), MapSet.put(used, new_id)}
      else
        {mapping, used}
      end
    end)
    |> elem(0)
  end

  @doc "Count of open comments in `old_v` whose anchors have a match in `mapping`."
  def portable_comment_count(_old_v, mapping) when map_size(mapping) == 0, do: 0

  def portable_comment_count(%Version{} = old_v, mapping) do
    keys = Map.keys(mapping)

    Repo.aggregate(
      from(c in Comment,
        where: c.version_id == ^old_v.id and c.resolved == false and c.anchor in ^keys
      ),
      :count
    )
  end

  @doc """
  Copies open comments from `old_v` to `new_v`, remapping anchor ids via
  `mapping` and updating anchor labels to match the new block text.
  Returns `{:ok, count}`.
  """
  def port_comments(_old_v, _new_v, mapping) when map_size(mapping) == 0, do: {:ok, 0}

  def port_comments(%Version{} = old_v, %Version{} = new_v, mapping) do
    {_body, new_anchors, _head} = Html.process(new_v.raw_html)
    new_label_by_id = Map.new(new_anchors, &{&1.id, &1.label})
    keys = Map.keys(mapping)

    portables =
      from(c in Comment,
        where: c.version_id == ^old_v.id and c.resolved == false and c.anchor in ^keys
      )
      |> Repo.all()

    {:ok, count} =
      Repo.transaction(fn ->
        Enum.each(portables, fn c ->
          new_anchor_id = Map.fetch!(mapping, c.anchor)

          %Comment{}
          |> Comment.changeset(%{
            "document_id" => new_v.document_id,
            "version_id" => new_v.id,
            "author_id" => c.author_id,
            "anchor" => new_anchor_id,
            "anchor_label" => Map.get(new_label_by_id, new_anchor_id, c.anchor_label),
            "body" => c.body
          })
          |> Repo.insert!()
        end)

        length(portables)
      end)

    broadcast(new_v.document_id, {:comments_ported, count})
    {:ok, count}
  end

  ## PubSub

  def subscribe(document_id),
    do: Phoenix.PubSub.subscribe(@pubsub, topic(document_id))

  defp broadcast(document_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, topic(document_id), message)

  defp topic(document_id), do: "doc:#{document_id}"
end
