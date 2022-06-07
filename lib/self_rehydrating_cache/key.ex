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
      :running_hydrating_task_ref,
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

    task = Task.Supervisor.async_nolink(SelfRehydratingCache.TaskSupervisor, state.hydrating_fun)

    {:ok, %{state | running_hydrating_task_ref: task.ref}}
  end

  @impl GenServer
  def handle_info(
        :refresh,
        %State{running_hydrating_task_ref: task_ref} = state
      )
      when is_reference(task_ref) do
    {:noreply, schedule_refresh(state)}
  end

  @impl GenServer
  def handle_info(
        :refresh,
        %State{hydrating_fun: hydrating_fun} = state
      ) do
    task = Task.Supervisor.async_nolink(SelfRehydratingCache.TaskSupervisor, hydrating_fun)

    {:noreply, schedule_refresh(%{state | running_hydrating_task_ref: task.ref})}
  end

  @impl GenServer
  def handle_info(:expire, %State{} = state),
    do: {:noreply, %{state | value: nil, hydrated?: false}}

  @impl GenServer
  def handle_info({task_ref, result}, %State{running_hydrating_task_ref: task_ref} = state) do
    Process.demonitor(task_ref, [:flush])

    new_state =
      case result do
        {:ok, value} ->
          %{state | value: value, hydrated?: true, running_hydrating_task_ref: nil}
          |> schedule_expiration()
          |> notify_waiting_callers()

        _ ->
          %{state | running_hydrating_task_ref: nil}
      end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, task_ref, :process, _pid, _reason},
        %State{running_hydrating_task_ref: task_ref} = state
      ),
      do: {:noreply, %{state | running_hydrating_task_ref: nil}}

  @impl GenServer
  def handle_call(
        :get_value,
        caller,
        %State{hydrated?: false, waiting_callers: waiting_callers} = state
      ),
      do: {:noreply, %{state | waiting_callers: [caller | waiting_callers]}}

  @impl GenServer
  def handle_call(
        :get_value,
        _caller,
        %State{value: value} = state
      ),
      do: {:reply, value, state}

  @impl GenServer
  def terminate(_reason, %State{ttl_timer: ttl_timer, refresh_timer: refresh_timer}) do
    if is_reference(ttl_timer), do: Process.cancel_timer(ttl_timer)
    if is_reference(refresh_timer), do: Process.cancel_timer(refresh_timer)

    :ok
  end

  defp schedule_refresh(%State{refresh_interval: refresh_interval} = state),
    do: %{
      state
      | refresh_timer: Process.send_after(self(), :refresh, refresh_interval)
    }

  defp schedule_refresh(state), do: state

  defp schedule_expiration(%State{ttl: ttl, ttl_timer: ttl_timer} = state) do
    if is_reference(ttl_timer), do: Process.cancel_timer(ttl_timer)

    %{
      state
      | ttl_timer: Process.send_after(self(), :expire, ttl)
    }
  end

  defp schedule_expiration(state), do: state

  defp notify_waiting_callers(%State{waiting_callers: waiting_callers, value: value} = state) do
    Enum.each(waiting_callers, fn caller ->
      GenServer.reply(caller, value)
    end)

    %{state | waiting_callers: []}
  end
end
