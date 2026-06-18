defmodule Docshare.Repo.Migrations.CreateDocs do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :title, :string, null: false
      add :token, :string, null: false
      add :raw_html, :text, null: false
      add :owner_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:documents, [:token])
    create index(:documents, [:owner_id])

    create table(:document_collaborators) do
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :role, :string, null: false, default: "commenter"
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:document_collaborators, [:document_id, :email])
    create index(:document_collaborators, [:email])

    create table(:comments) do
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :delete_all), null: false
      add :anchor, :string, null: false
      add :anchor_label, :string
      add :body, :text, null: false
      add :resolved, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:document_id])
    create index(:comments, [:document_id, :anchor])
  end
end
