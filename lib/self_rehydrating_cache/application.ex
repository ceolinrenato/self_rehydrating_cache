defmodule SelfRehydratingCache.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: SelfRehydratingCache.Worker.start_link(arg)
      # {SelfRehydratingCache.Worker, arg}
      SelfRehydratingCache.KeysDynamicSupervisor,
      {Registry, name: SelfRehydratingCache.KeyProcessRegistry, keys: :unique},
      {Task.Supervisor, name: SelfRehydratingCache.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SelfRehydratingCache.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
