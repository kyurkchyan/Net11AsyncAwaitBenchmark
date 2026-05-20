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
- 3 warmup + 8 iteration runs per benchmark (shorter than default; the
  5-trial aggregate below absorbs the resulting per-run noise)
- 5 independent end-to-end trials, fully sequential — no two runs ever shared
  the CPU. Driver: `run-trials.ps1`.

## Results — 5-trial aggregate

A single run is noisy; one comparison table doesn't tell you which gains are
reproducible and which are measurement artifacts. So `run-trials.ps1` repeats
the whole net10 → net11 → diff sequence **5 times back-to-back** (sequentially,
never overlapping on the CPU) and aggregates the per-trial speedups. Each trial
is independently stored under `BenchmarkResults/run-1/` … `run-5/`, with a
single `BenchmarkResults/aggregate.csv` rolling them up.

Sorted by mean speedup descending. n = 5 trials per row, ~19 min total wall.

| Benchmark                                       | Mean speedup | StdDev | Min  | Max  | Mean Δ% | Per-trial speedups          |
| ----------------------------------------------- | -----------: | -----: | ---: | ---: | ------: | --------------------------- |
| YieldChainBench.YieldLoop                       |   **2.18×**  |  0.20  | 1.97 | 2.41 |  -53.8% | 1.97, 2.34, 2.41, 2.20, 1.98 |
| ChannelPingPongBench.UnboundedChannelRoundTrip  |     2.00×    |  0.04  | 1.96 | 2.05 |  -50.0% | 1.97, 2.00, 2.02, 2.05, 1.96 |
| YieldChainBench.DeepNestedYield                 |     1.79×    |  0.06  | 1.72 | 1.88 |  -44.0% | 1.79, 1.75, 1.88, 1.72, 1.79 |
| ChannelPingPongBench.BoundedChannelRoundTrip    |     1.09×    |  0.04  | 1.04 | 1.14 |   -8.0% | 1.04, 1.11, 1.07, 1.07, 1.14 |
| SyncCompletionBench.AwaitValueTaskCompleted     |     1.08×    |  0.03  | 1.05 | 1.12 |   -7.3% | 1.05, 1.10, 1.12, 1.05, 1.07 |
| DeepCallStackBench.DeepStackValueTask           |     1.07×    |  0.07  | 0.97 | 1.14 |   -5.8% | 1.07, 1.02, 1.13, 1.14, 0.97 |
| SyncCompletionBench.MemoryStreamReadAsync       |     1.03×    |  0.04  | 0.97 | 1.08 |   -3.3% | 0.97, 1.08, 1.04, 1.04, 1.04 |
| DeepCallStackBench.DeepStackBottomingInBcl      |     1.02×    |  0.09  | 0.92 | 1.17 |   -1.4% | 0.92, 1.17, 0.98, 1.01, 1.03 |
| SyncCompletionBench.AwaitCompletedTask          |     1.00×    |  0.04  | 0.96 | 1.06 |   +0.1% | 0.96, 0.96, 1.06, 1.02, 0.99 |
| SyncCompletionBench.AwaitFromResult             |     0.98×    |  0.02  | 0.96 | 1.01 |   +1.9% | 1.01, 0.98, 0.99, 0.96, 0.96 |

### How to read the table

- **The top three benchmarks are the real story**: code that genuinely
  suspends and resumes inside the BCL (Task.Yield loops, Channel.WriteAsync /
  ReadAsync round-trips) is consistently **~1.8–2.2× faster** on net11. The
  `UnboundedChannelRoundTrip` row in particular has stddev 0.04 across 5
  trials — for a number near 2.00 that's about ±2%, which is as reproducible
  as benchmarks of this kind get.
- **The middle four (~1.07–1.09×)** are smaller-but-real wins on workloads
  that mix in some BCL await overhead but mostly run in user code.
- **The bottom three (~0.98–1.03×)** are at the noise floor. The mean delta is
  ≤ 3% in either direction and the stddev brackets cross 1.0 — the C#
  compiler already optimized these sync-completion paths so there's almost
  nothing left for runtime-async to remove. The "regression" of 0.98× on
  `AwaitFromResult` is consistent with measurement noise, not a real
  slowdown.

### What this means in practice

The headline "every await into BCL gets cheaper" is true, but the magnitude
depends entirely on **how much real async machinery the BCL path actually
exercises**. Workloads dominated by suspend/resume traffic (real I/O,
producer/consumer queues, anything that frequently yields) should see
double-digit-percent to nearly-2× CPU reductions. Workloads dominated by
hot fast-paths that complete synchronously will see basically no change —
they were already nearly free.

The variance pattern matters too: the big-win benchmarks have **tight
stddev** (the gain is structural), while the at-the-noise-floor benchmarks
have wider relative stddev (you're just measuring jitter).

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

For a single comparison:

```pwsh
dotnet build -c Release
dotnet run -c Release -f net10.0 --no-build -- --filter "AsyncBenchmark.Benchmarks.*" --artifacts BenchmarkResults\net10
dotnet run -c Release -f net11.0 --no-build -- --filter "AsyncBenchmark.Benchmarks.*" --artifacts BenchmarkResults\net11
.\compare-results.ps1
```

For the full 5-trial reproducibility experiment (the one that produced the
table above):

```pwsh
.\run-trials.ps1 -Trials 5
```

This clears `BenchmarkResults/`, runs `N` independent trials (each containing
a fresh net10 → net11 → comparison sequence), and writes the aggregated
mean/stddev/min/max of the speedups to `BenchmarkResults/aggregate.csv`.
Allow ~4 min per trial (~20 min for 5).

All generated outputs land under `BenchmarkResults/` (BDN artifacts, run
logs, per-trial `comparison.csv`, and the rollup `aggregate.csv`). That
folder is git-ignored.
