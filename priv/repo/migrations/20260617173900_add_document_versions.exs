defmodule Docshare.Repo.Migrations.AddDocumentVersions do
  use Ecto.Migration

  def up do
    create table(:document_versions) do
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :label, :string
      add :raw_html, :text, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:document_versions, [:document_id, :version_number])
    create index(:document_versions, [:document_id])

    # Move each document's existing HTML into a first version.
    execute """
    INSERT INTO document_versions (document_id, version_number, label, raw_html, created_by_id, inserted_at, updated_at)
    SELECT id, 1, 'v1', raw_html, owner_id, now(), now() FROM documents
    """

    # Comments now belong to a specific version.
    alter table(:comments) do
      add :version_id, references(:document_versions, on_delete: :delete_all)
    end

    execute """
    UPDATE comments c
    SET version_id = dv.id
    FROM document_versions dv
    WHERE dv.document_id = c.document_id AND dv.version_number = 1
    """

    # version_id is required going forward; raw_html now lives on versions.
    execute "ALTER TABLE comments ALTER COLUMN version_id SET NOT NULL"

    alter table(:documents) do
      remove :raw_html
    end

    create index(:comments, [:version_id, :anchor])
  end

  def down do
    alter table(:documents) do
      add :raw_html, :text
    end

    execute """
    UPDATE documents d
    SET raw_html = dv.raw_html
    FROM document_versions dv
    WHERE dv.document_id = d.id AND dv.version_number = 1
    """

    alter table(:comments) do
      remove :version_id
    end

    drop table(:document_versions)
  end
end
