defmodule Docshare.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :title, :string
    field :token, :string

    belongs_to :owner, Docshare.Accounts.User
    has_many :versions, Docshare.Documents.Version
    has_many :collaborators, Docshare.Documents.Collaborator
    has_many :comments, Docshare.Documents.Comment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> maybe_put_token()
  end

  defp maybe_put_token(changeset) do
    case get_field(changeset, :token) do
      nil -> put_change(changeset, :token, gen_token())
      _ -> changeset
    end
  end

  defp gen_token do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
