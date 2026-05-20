using AsyncBenchmark;
using BenchmarkDotNet.Running;

BenchmarkSwitcher
    .FromAssembly(typeof(BenchConfig).Assembly)
    .Run(args, new BenchConfig());
