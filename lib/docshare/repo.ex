defmodule Docshare.Repo do
  use Ecto.Repo,
    otp_app: :docshare,
    adapter: Ecto.Adapters.Postgres
end
