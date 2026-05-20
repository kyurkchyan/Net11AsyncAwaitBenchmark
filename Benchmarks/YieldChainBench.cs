using BenchmarkDotNet.Attributes;

namespace AsyncBenchmark.Benchmarks;

/// <summary>
/// True suspension paths via Task.Yield. Exercises the runtime's suspend/resume
/// machinery rather than the sync-completion fast path. Expected gain is smaller here
/// because suspension always pays an allocation, but the per-resume overhead changes.
/// </summary>
[MemoryDiagnoser]
public class YieldChainBench
{
    [Params(100)]
    public int Yields;

    [Benchmark]
    public async Task YieldLoop()
    {
        for (int i = 0; i < Yields; i++)
        {
            await Task.Yield();
        }
    }

    // Deep nested awaits where each frame yields once. Stresses per-frame state-machine
    // overhead — the area runtime-async restructures most.
    [Benchmark]
    public Task DeepNestedYield() => NestedAsync(Yields);

    private static async Task NestedAsync(int depth)
    {
        if (depth == 0) return;
        await Task.Yield();
        await NestedAsync(depth - 1);
    }
}
