defmodule Docshare.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("RELEASE_ROOT") do
      Docshare.Release.migrate()
      Docshare.Release.seed()
    end

    children = [
      DocshareWeb.Telemetry,
      Docshare.Repo,
      {DNSCluster, query: Application.get_env(:docshare, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Docshare.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Docshare.Finch},
      # Start a worker by calling: Docshare.Worker.start_link(arg)
      # {Docshare.Worker, arg},
      # Start to serve requests, typically the last entry
      DocshareWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Docshare.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DocshareWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
