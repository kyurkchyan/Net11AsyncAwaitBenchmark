using BenchmarkDotNet.Attributes;

namespace AsyncBenchmark.Benchmarks;

/// <summary>
/// Deep async call stacks that bottom out in a BCL sync-completing await. Without
/// runtime-async every frame allocates a state machine box on suspension and pays
/// dispatch overhead. With runtime-async the runtime can fold this work.
/// </summary>
[MemoryDiagnoser]
public class DeepCallStackBench
{
    [Params(1000)]
    public int Iterations;

    [Benchmark]
    public async Task<long> DeepStackBottomingInBcl()
    {
        long total = 0;
        for (int i = 0; i < Iterations; i++)
            total += await LevelA(i);
        return total;
    }

    private static async Task<long> LevelA(int x) => await LevelB(x) + 1;
    private static async Task<long> LevelB(int x) => await LevelC(x) + 1;
    private static async Task<long> LevelC(int x) => await LevelD(x) + 1;
    private static async Task<long> LevelD(int x) => await LevelE(x) + 1;
    private static async Task<long> LevelE(int x) => await Task.FromResult((long)x);

    [Benchmark]
    public async ValueTask<long> DeepStackValueTask()
    {
        long total = 0;
        for (int i = 0; i < Iterations; i++)
            total += await VLevelA(i);
        return total;
    }

    private static async ValueTask<long> VLevelA(int x) => await VLevelB(x) + 1;
    private static async ValueTask<long> VLevelB(int x) => await VLevelC(x) + 1;
    private static async ValueTask<long> VLevelC(int x) => await VLevelD(x) + 1;
    private static async ValueTask<long> VLevelD(int x) => await VLevelE(x) + 1;
    private static async ValueTask<long> VLevelE(int x) => await new ValueTask<long>((long)x);
}
