using BenchmarkDotNet.Columns;
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Diagnosers;
using BenchmarkDotNet.Jobs;
using BenchmarkDotNet.Toolchains.InProcess.Emit;

namespace AsyncBenchmark;

internal sealed class BenchConfig : ManualConfig
{
    public BenchConfig()
    {
        // BenchmarkDotNet 0.15.x doesn't yet recognize net11.0 as a runtime moniker,
        // so the default CsProj toolchain's SDK validator throws on the unknown host.
        // We sidestep it with the InProcess toolchain — the host process IS the
        // runtime we want to measure, so no subprocess is needed.
        AddJob(Job.Default
            .WithToolchain(InProcessEmitToolchain.Instance)
            .WithWarmupCount(3)
            .WithIterationCount(8)
            .WithLaunchCount(1)
            .WithId("host-runtime"));
        AddDiagnoser(MemoryDiagnoser.Default);
        AddColumnProvider(DefaultColumnProviders.Instance);
        AddLogger(BenchmarkDotNet.Loggers.ConsoleLogger.Default);
        AddExporter(BenchmarkDotNet.Exporters.MarkdownExporter.GitHub);
        AddExporter(BenchmarkDotNet.Exporters.Csv.CsvExporter.Default);
    }
}
