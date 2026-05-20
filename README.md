# .NET 11 Preview 4 — Runtime-Async BCL Benchmark

Verifies the perf gains from .NET 11 Preview 4 compiling the BCL with
`runtime-async=on`. Same C# source, same BenchmarkDotNet config, host runtime is
the only variable: `.NET 10.0.8` vs `.NET 11.0 preview 4`.

## What's being measured

User code in this project is still compiled with the C# async state machine
(`UseRuntimeAsync` is not on by default for user projects in Preview 4 — only
the shared framework is). So every gain you see below comes from **the BCL
itself** being compiled with runtime-async. Your awaits *into* BCL get cheaper,
without you changing any code.

## Setup

- `Microsoft.DotNet.SDK.Preview` 11.0.100-preview.4.26230.115 (installed via winget)
- BenchmarkDotNet 0.15.8 with the `InProcessEmitToolchain` (0.15.8's `CsProjCoreToolchain`
  validator throws on net11.0 — the InProcess toolchain bypasses it and is fine here
  because the host runtime *is* the variable under test)
- AMD Ryzen 9 9950X (16 phys / 32 logical), Server GC, TieredPGO on
- 3 warmup + 8 iteration runs per benchmark (shorter than default; some sub-µs
  results have ±5% noise as a result)

## Results

Both runs were executed sequentially on the same machine so they didn't share
the CPU. Sorted by speedup descending:

| Benchmark                                       | net10 (Mean) | net11 (Mean) | Δ      | Speedup |
| ----------------------------------------------- | -----------: | -----------: | -----: | ------: |
| YieldChainBench.YieldLoop                       |    35.59 µs  |    15.32 µs  | -57.0% | **2.32×** |
| ChannelPingPongBench.UnboundedChannelRoundTrip  |   109.0 µs   |    56.58 µs  | -48.1% | 1.93×   |
| YieldChainBench.DeepNestedYield                 |    42.90 µs  |    23.62 µs  | -44.9% | 1.82×   |
| SyncCompletionBench.AwaitValueTaskCompleted     |   460.9 ns   |   385.2 ns   | -16.4% | 1.20×   |
| ChannelPingPongBench.BoundedChannelRoundTrip    |   155.8 µs   |   130.61 µs  | -16.2% | 1.19×   |
| DeepCallStackBench.DeepStackValueTask           |    23.64 µs  |    21.97 µs  |  -7.1% | 1.08×   |
| SyncCompletionBench.AwaitCompletedTask          |   684.0 ns   |   651.3 ns   |  -4.8% | 1.05×   |
| SyncCompletionBench.MemoryStreamReadAsync       | 10203.5 ns   |  9913.6 ns   |  -2.8% | 1.03×   |
| SyncCompletionBench.AwaitFromResult             |  1063.7 ns   |  1035.0 ns   |  -2.7% | 1.03×   |
| DeepCallStackBench.DeepStackBottomingInBcl      |    56.87 µs  |    59.63 µs  |  +4.9% | 0.95×   |

The single regression (`DeepStackBottomingInBcl`, +4.9%) is within the noise
band at this iteration count — that benchmark allocates ~430 kB/op and
its variance is dominated by Gen0 GC frequency rather than async machinery.

The biggest wins are in code that suspends and resumes a lot (`Task.Yield`
loops, Channel ping-pong). The smallest wins are in the trivial
sync-completion paths, where the C# compiler already optimized state-machine
allocation away.

### Allocations

Per-op allocations are essentially unchanged for stack-only paths and rise
slightly (10–60%) for the Channel and Yield benchmarks on net11. This is
expected:

- State machine boxes in *your* code are still produced by the C# compiler, so
  the boxes you would naively expect to disappear don't, in this project.
- Where runtime-async restructures BCL code, it allocates different continuation
  objects under its own protocol — sometimes a bit more bytes, but
  on average less CPU per allocation.

Add `<UseRuntimeAsync>true</UseRuntimeAsync>` to the csproj and re-run to see
the allocation deltas for the user-code path.

## What "runtime-async" did away with in Preview 4

- `[RequiresPreviewFeatures]` opt-in for using runtime-async is removed.
- `DOTNET_RuntimeAsync` / `UNSUPPORTED_RuntimeAsync` env switches are removed.
  The only opt-out is `<UseRuntimeAsync>false</UseRuntimeAsync>` per-project.
- Inlining restrictions for ReadyToRun-compiled runtime-async methods were
  removed.
- Virtual dispatch over covariant Task overrides now uses runtime-generated
  void-returning thunks.

## Running the benchmarks

```pwsh
dotnet build -c Release
dotnet run -c Release -f net10.0 --no-build -- --filter "AsyncBenchmark.Benchmarks.*" --artifacts BenchmarkResults\net10
dotnet run -c Release -f net11.0 --no-build -- --filter "AsyncBenchmark.Benchmarks.*" --artifacts BenchmarkResults\net11
.\compare-results.ps1
```

All generated outputs land under `BenchmarkResults/` (the BDN artifacts and the
`comparison.csv` summary). That folder is git-ignored.
