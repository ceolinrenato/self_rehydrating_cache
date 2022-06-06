defmodule SelfRehydratingCache.Key do
  use GenServer

  defmodule State do
    defstruct [
      :key,
      :hydrating_fun,
      :value,
      :refresh_timer,
      :ttl_timer,
      :refresh_interval,
      :ttl,
      test_env?: false,
      hydrated?: false,
      waiting_callers: []
    ]
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    name = {:via, Registry, {SelfRehydratingCache.KeyProcessRegistry, Keyword.get(opts, :key)}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> schedule_refresh()
      |> schedule_expiration()

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:refresh, %State{hydrating_fun: hydrating_fun} = state) do
    new_state =
      case hydrating_fun.() do
        {:ok, value} ->
          %{state | value: value, hydrated?: true}
          |> schedule_refresh()
          |> schedule_expiration()

        _ ->
          schedule_refresh(state)
      end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:expire, %State{} = state),
    do: {:noreply, schedule_refresh(%{state | value: nil, hydrated?: false})}

  @impl GenServer
  def terminate(_reason, %State{ttl_timer: ttl_timer, refresh_timer: refresh_timer}) do
    if is_reference(ttl_timer), do: Process.cancel_timer(ttl_timer)
    if is_reference(refresh_timer), do: Process.cancel_timer(refresh_timer)

    :ok
  end

  defp schedule_refresh(%State{refresh_interval: refresh_interval, test_env?: false} = state),
    do: %{
      state
      | refresh_timer: Process.send_after(self(), :refresh, refresh_interval)
    }

  defp schedule_refresh(state), do: state

  defp schedule_expiration(%State{ttl: ttl, ttl_timer: ttl_timer, test_env?: false} = state) do
    if is_reference(ttl_timer), do: Process.cancel_timer(ttl_timer)

    %{
      state
      | ttl_timer: Process.send_after(self(), :expire, ttl)
    }
  end

  defp schedule_expiration(state), do: state
end
