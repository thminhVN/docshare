defmodule Docshare.Repo.Migrations.AddPublicTokenToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :public_token, :string
    end

    create unique_index(:documents, [:public_token])
  end
end
