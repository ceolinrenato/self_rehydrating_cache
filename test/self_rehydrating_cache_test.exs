defmodule SelfRehydratingCacheTest do
  use ExUnit.Case, async: false

  describe "register_function/4" do
    test "register a function under a key, creates a process for that key and returns :ok" do
      key = "supervisor_and_registry_test"

      sample_function = fn -> {:ok, "Awesome"} end

      assert :ok == SelfRehydratingCache.register_function(sample_function, key, 10_000, 1_000)

      assert [{pid, _}] = Registry.lookup(SelfRehydratingCache.KeyProcessRegistry, key)

      assert {:undefined, pid, :worker, [SelfRehydratingCache.Key]} in DynamicSupervisor.which_children(
               SelfRehydratingCache.KeysDynamicSupervisor
             )
    end

    test "returns an error if there's alredy a function registered on that key" do
      key = "duplicated_key_test"

      sample_function = fn -> {:ok, "Amazing"} end

      assert :ok == SelfRehydratingCache.register_function(sample_function, key, 10_000, 1_000)

      another_sample_function = fn -> {:ok, "Astonishing"} end

      assert {:error, :already_registered} ==
               SelfRehydratingCache.register_function(another_sample_function, key, 1_000, 500)
    end
  end

  describe "get/3" do
    test "returns a value if there's one cached for key" do
      key = "cached_entry_immediate_return_test"
      value = "Incredible #{Enum.random(100..999)}"

      sample_function = fn -> {:ok, value} end

      SelfRehydratingCache.register_function(sample_function, key, 10_000, 1_000)

      assert {:ok, value} == SelfRehydratingCache.get(key)
    end

    test "returns latest cached entry without blocking even if a recomputation function is ongoing" do
      key = "latest_cached_entry_immediate_return_test"
      value = "Astounding #{Enum.random(100..999)}"
      refresh_interval = 100
      function_delay = 400

      sample_function = fn ->
        Process.sleep(function_delay)
        {:ok, value}
      end

      datetime_before_await = DateTime.utc_now()

      SelfRehydratingCache.register_function(sample_function, key, 10_000, refresh_interval)
      [{pid, _}] = Registry.lookup(SelfRehydratingCache.KeyProcessRegistry, key)

      assert {:ok, value} == SelfRehydratingCache.get(key)

      # Wait until we're sure another refresh cycle ran
      Process.sleep(refresh_interval)

      assert %SelfRehydratingCache.Key.State{running_hydrating_task_ref: task_ref} =
               :sys.get_state(pid)

      assert is_reference(task_ref)

      assert {:ok, value} == SelfRehydratingCache.get(key)

      datetime_after_await = DateTime.utc_now()

      # the multiplier in the delta assertion is less than 2,
      # this indicates that it didn't block the caller process
      # for twice the sample function delay, so get/1
      # immediately returned the last cached value

      assert_in_delta(
        DateTime.to_unix(datetime_before_await, :millisecond),
        DateTime.to_unix(datetime_after_await, :millisecond),
        function_delay * 1.2 + refresh_interval
      )
    end

    test "awaits for hydration function to return, if it finishes before timeout return the resultant value" do
      key = "sync_await_returning_before_timeout_test"
      value = "Wonderful"
      function_delay = 200

      sample_function = fn ->
        Process.sleep(function_delay)
        {:ok, value}
      end

      datetime_before_await = DateTime.utc_now()

      SelfRehydratingCache.register_function(sample_function, key, 10_000, 1_000)

      assert {:ok, value} == SelfRehydratingCache.get(key)

      datetime_after_await = DateTime.utc_now()

      # the multiplier in the delta assertion is in between 0.5 and 1,
      # this indicates that it did block the caller process
      # for at least half the sample function delay, so get/1
      # awaited for the hydrating fun to complete

      refute_in_delta(
        DateTime.to_unix(datetime_before_await, :millisecond),
        DateTime.to_unix(datetime_after_await, :millisecond),
        function_delay * 0.9
      )
    end

    test "don't wait past timeout and return an error" do
      key = "sync_await_past_timeout_test"
      function_delay = 5_000
      timeout = 200

      sample_function = fn ->
        Process.sleep(function_delay)
        {:ok, "Subarashi"}
      end

      datetime_before_await = DateTime.utc_now()

      SelfRehydratingCache.register_function(sample_function, key, 10_000, 1_000)

      assert {:error, :timeout} == SelfRehydratingCache.get(key, timeout)

      datetime_after_await = DateTime.utc_now()

      assert DateTime.to_unix(datetime_after_await, :millisecond) -
               DateTime.to_unix(datetime_before_await, :millisecond) >= timeout
    end

    test "if the hydration function returns an error do not store a value on the cache" do
      key = "failed_hydration_test"
      timeout = 200

      sample_function = fn -> {:error, "reason"} end

      SelfRehydratingCache.register_function(sample_function, key, 20_000, 10_000)

      assert {:error, :timeout} == SelfRehydratingCache.get(key, timeout)
    end
  end
end
