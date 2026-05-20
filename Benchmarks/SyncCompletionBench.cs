using BenchmarkDotNet.Attributes;

namespace AsyncBenchmark.Benchmarks;

/// <summary>
/// Awaits that complete synchronously through BCL APIs. With state-machine async every
/// frame allocates a box on suspension-or-not; with runtime-async the BCL avoids the box
/// entirely on the sync-completion fast path. Expect the biggest allocation delta here.
/// </summary>
[MemoryDiagnoser]
public class SyncCompletionBench
{
    [Params(1000)]
    public int Iterations;

    private readonly byte[] _buffer = new byte[64];
    private MemoryStream _memoryStream = null!;

    [GlobalSetup]
    public void Setup()
    {
        _memoryStream = new MemoryStream(new byte[64 * 1024]);
    }

    // Task.CompletedTask is the cheapest possible await — only state machine overhead remains.
    [Benchmark]
    public async Task AwaitCompletedTask()
    {
        for (int i = 0; i < Iterations; i++)
        {
            await Task.CompletedTask;
        }
    }

    // Task.FromResult<int> caches a singleton for small ints; await goes through Task<T>.
    [Benchmark]
    public async Task<int> AwaitFromResult()
    {
        int sum = 0;
        for (int i = 0; i < Iterations; i++)
        {
            sum += await Task.FromResult(1);
        }
        return sum;
    }

    // ValueTask.CompletedTask sync-completion path — runtime-async should help most here.
    [Benchmark]
    public async ValueTask AwaitValueTaskCompleted()
    {
        for (int i = 0; i < Iterations; i++)
        {
            await ValueTask.CompletedTask;
        }
    }

    // MemoryStream.ReadAsync always completes synchronously and lives in the BCL.
    [Benchmark]
    public async Task<int> MemoryStreamReadAsync()
    {
        int total = 0;
        _memoryStream.Position = 0;
        for (int i = 0; i < Iterations; i++)
        {
            if (_memoryStream.Position + _buffer.Length > _memoryStream.Length)
                _memoryStream.Position = 0;
            total += await _memoryStream.ReadAsync(_buffer.AsMemory());
        }
        return total;
    }
}
