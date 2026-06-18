defmodule Docshare.Documents.Collaborator do
  use Ecto.Schema
  import Ecto.Changeset

  schema "document_collaborators" do
    field :email, :string
    field :role, :string, default: "commenter"

    belongs_to :document, Docshare.Documents.Document
    belongs_to :user, Docshare.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(collaborator, attrs) do
    collaborator
    |> cast(attrs, [:email, :role, :document_id, :user_id])
    |> validate_required([:email, :document_id])
    |> update_change(:email, &String.downcase(String.trim(&1 || "")))
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be a valid email")
    |> validate_inclusion(:role, ["commenter", "viewer"])
    |> unique_constraint([:document_id, :email],
      name: :document_collaborators_document_id_email_index,
      message: "already invited"
    )
  end
end
