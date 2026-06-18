defmodule Docshare.Documents.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :anchor, :string
    field :anchor_label, :string
    field :body, :string
    field :resolved, :boolean, default: false

    belongs_to :document, Docshare.Documents.Document
    belongs_to :version, Docshare.Documents.Version
    belongs_to :author, Docshare.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:anchor, :anchor_label, :body, :resolved, :document_id, :version_id, :author_id])
    |> validate_required([:anchor, :body, :document_id, :version_id, :author_id])
    |> validate_length(:body, min: 1, max: 5_000)
    |> validate_length(:anchor_label, max: 200)
  end
end
