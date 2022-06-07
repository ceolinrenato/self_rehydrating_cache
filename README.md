# SelfRehydratingCache

This is a periodic self-rehydrating cache. Functions of 0-arity can be registered using:

```elixir
SelfRehydratingCache.register_function(fun, key, ttl, refresh_interval)
```

The functions are registered under a key, there are processes that periodically recompute the values returned by the function and store then under that key. The values can be retrieved using:

```elixir
SelfRehydratingCache.get(key)
```

## Process Tree

The SelfRehydratingCache application has a supervisor tree with 3 children:

- `SelfRehydratingCache.KeysDynamicSupervisor`: this module is a dynamic supervisor that has the one process per registered function under it, this is to make sure those processes will be restarted if they exit abnormally.
- `SelfRehydratingCache.KeyProcessRegistry`: this module is a [Registry](https://hexdocs.pm/elixir/Registry.html), it's used to map the keys registered with their respective process PID of a `KeysDynamicSupervisor` children. It also makes sure there's a single running process for each key.
- `SelfRehydratingCache.TaskSupervisor`: this is a task supervisor used to run the hydrating functions concurrently without blocking the key processes.

The processes living under `SelfRehydratingCache.KeysDynamicSupervisor` are GenServers implemented in the `SelfRehydratingCache.Key` module, each registered function has it's own process. Most of self hydrating logic is handled in the Key process: it stores the cached value on its state, runs refresh/ttl timers, handle synchronous calls to get the current cached value, notify waiting callers when a value is available, schedule tasks for the hydrating functions and handle the messages returned by the task processes. It also traps exits and make sure to clear the references.

![image](https://user-images.githubusercontent.com/49283261/172396645-578f58ad-b67e-4e94-b0b2-3fd0ed0e8d84.png)
(Example of a running application with 5 registered functions on the cache)

## Running Unit Tests

This is a mix project, so tests can be run with:

```
mix test
```
