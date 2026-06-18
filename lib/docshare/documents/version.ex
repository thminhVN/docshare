defmodule Docshare.Documents.Version do
  use Ecto.Schema
  import Ecto.Changeset

  schema "document_versions" do
    field :version_number, :integer
    field :label, :string
    field :raw_html, :string

    belongs_to :document, Docshare.Documents.Document
    belongs_to :created_by, Docshare.Accounts.User
    has_many :comments, Docshare.Documents.Comment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:version_number, :label, :raw_html, :document_id, :created_by_id])
    |> validate_required([:version_number, :raw_html, :document_id])
    |> validate_length(:raw_html, min: 1, max: 5_000_000)
    |> validate_length(:label, max: 100)
    |> unique_constraint([:document_id, :version_number],
      name: :document_versions_document_id_version_number_index
    )
  end
end
