defmodule SelfRehydratingCache.KeysDynamicSupervisor do
  @moduledoc """
  DynamicSupervisor that holds `` processes.
  """

  use DynamicSupervisor

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end
end
