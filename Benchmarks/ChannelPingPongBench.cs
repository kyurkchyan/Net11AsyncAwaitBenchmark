using System.Threading.Channels;
using BenchmarkDotNet.Attributes;

namespace AsyncBenchmark.Benchmarks;

/// <summary>
/// Realistic producer/consumer through System.Threading.Channels. Channel internals
/// are heavily-async BCL code; every WriteAsync / ReadAsync pair traverses several
/// frames. This is the closest stand-in for "real workloads" in this benchmark suite.
/// </summary>
[MemoryDiagnoser]
public class ChannelPingPongBench
{
    [Params(1000)]
    public int Messages;

    [Benchmark]
    public async Task UnboundedChannelRoundTrip()
    {
        var ch = Channel.CreateUnbounded<int>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = true,
            AllowSynchronousContinuations = true,
        });

        var producer = Task.Run(async () =>
        {
            for (int i = 0; i < Messages; i++)
                await ch.Writer.WriteAsync(i);
            ch.Writer.Complete();
        });

        long sum = 0;
        await foreach (var item in ch.Reader.ReadAllAsync())
            sum += item;

        await producer;
    }

    [Benchmark]
    public async Task BoundedChannelRoundTrip()
    {
        var ch = Channel.CreateBounded<int>(new BoundedChannelOptions(capacity: 16)
        {
            SingleReader = true,
            SingleWriter = true,
            FullMode = BoundedChannelFullMode.Wait,
            AllowSynchronousContinuations = true,
        });

        var producer = Task.Run(async () =>
        {
            for (int i = 0; i < Messages; i++)
                await ch.Writer.WriteAsync(i);
            ch.Writer.Complete();
        });

        long sum = 0;
        await foreach (var item in ch.Reader.ReadAllAsync())
            sum += item;

        await producer;
    }
}
