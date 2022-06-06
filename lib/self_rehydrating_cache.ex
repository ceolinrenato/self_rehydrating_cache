defmodule SelfRehydratingCache do
  @moduledoc """
  Documentation for `SelfRehydratingCache`.
  """

  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  @doc """
  Registers a function that will be computed periodically to update the cache.
  Arguments:
    - `fun`: a 0-arity function that computes the value and returns either
      `{:ok, value}` or `{:error, reason}`.
    - `key`: associated with the function and is used to retrieve the stored
    value.
    - `ttl` ("time to live"): how long (in milliseconds) the value is stored
      before it is discarded if the value is not refreshed.
    - `refresh_interval`: how often (in milliseconds) the function is
      recomputed and the new value stored. `refresh_interval` must be strictly
      smaller than `ttl`. After the value is refreshed, the `ttl` counter is
      restarted.
  The value is stored only if `{:ok, value}` is returned by `fun`. If `{:error,
  reason}` is returned, the value is not stored and `fun` must be retried on
  the next run.
  """
  @spec register_function(
          fun :: (() -> {:ok, any()} | {:error, any()}),
          key :: any,
          ttl :: non_neg_integer(),
          refresh_interval :: non_neg_integer()
        ) :: :ok | {:error, :already_registered}
  def register_function(fun, key, ttl, refresh_interval)
      when is_function(fun, 0) and is_integer(ttl) and ttl > 0 and
             is_integer(refresh_interval) and
             refresh_interval < ttl do
    with :ok <- validate_already_registered(key),
         {:ok, _pid} <-
           DynamicSupervisor.start_child(
             SelfRehydratingCache.KeysDynamicSupervisor,
             {SelfRehydratingCache.Key,
              refresh_interval: refresh_interval, ttl: ttl, key: key, hydrating_fun: fun}
           ) do
      :ok
    end
  end

  @doc """
  Get the value associated with `key`.
  Details:
    - If the value for `key` is stored in the cache, the value is returned
      immediately.
    - If a recomputation of the function is in progress, the last stored value
      is returned.
    - If the value for `key` is not stored in the cache but a computation of
      the function associated with this `key` is in progress, wait up to
      `timeout` milliseconds. If the value is computed within this interval,
      the value is returned. If the computation does not finish in this
      interval, `{:error, :timeout}` is returned.
    - If `key` is not associated with any function, return `{:error,
      :not_registered}`
  """
  @spec get(any(), non_neg_integer(), Keyword.t()) :: result
  def get(key, timeout \\ 30_000, _opts \\ []) when is_integer(timeout) and timeout > 0 do
    with {:ok, pid} <- get_key_process_pid(key) do
      get_cached_value_task =
        Task.async(fn ->
          GenServer.call(pid, :get_value, :infinity)
        end)

      case Task.yield(get_cached_value_task, timeout) || Task.shutdown(get_cached_value_task) do
        nil ->
          {:error, :timeout}

        reply ->
          reply
      end
    end
  end

  defp get_key_process_pid(key) do
    case Registry.lookup(SelfRehydratingCache.KeyProcessRegistry, key) do
      [{pid, _}] ->
        {:ok, pid}

      _ ->
        {:error, :not_registered}
    end
  end

  defp validate_already_registered(key) do
    case get_key_process_pid(key) do
      {:ok, _pid} ->
        {:error, :already_registered}

      _ ->
        :ok
    end
  end
end
