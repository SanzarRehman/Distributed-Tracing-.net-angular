using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;
using System.Text.Json;

namespace PathfinderApi.Controllers;

[ApiController]
[Route("api/errors")]
public class ErrorSimulationController : ControllerBase
{
    private static readonly ActivitySource ActivitySource = new("PathfinderApi");
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<ErrorSimulationController> _logger;

    public ErrorSimulationController(IHttpClientFactory httpClientFactory, ILogger<ErrorSimulationController> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    // ── 1. Unhandled Exception ──────────────────────────────────────
    [HttpGet("unhandled-exception")]
    public IActionResult UnhandledException()
    {
        using var activity = ActivitySource.StartActivity("SimulateUnhandledException");

        _logger.LogInformation("Triggering unhandled NullReferenceException");

        string? value = null;
        _ = value!.Length; // throws NullReferenceException

        return Ok(); // never reached
    }

    // ── 2. Handled Exception ────────────────────────────────────────
    [HttpGet("handled-exception")]
    public IActionResult HandledException()
    {
        using var activity = ActivitySource.StartActivity("SimulateHandledException");

        try
        {
            throw new InvalidOperationException("Simulated handled exception");
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
            {
                { "exception.type", ex.GetType().FullName },
                { "exception.message", ex.Message },
                { "exception.stacktrace", ex.StackTrace ?? "" }
            }));
            _logger.LogError(ex, "Handled exception occurred");

            return StatusCode(500, new
            {
                error = "HandledException",
                message = ex.Message,
                traceId = Activity.Current?.TraceId.ToString()
            });
        }
    }

    // ── 3. SQL / Database Error ─────────────────────────────────────
    [HttpGet("sql-error")]
    public IActionResult SqlError()
    {
        using var activity = ActivitySource.StartActivity("SimulateSqlError");

        try
        {
            // Simulate a database connection failure
            throw new Exception("Database connection failed: Unable to connect to server 'db-server:5432'. Connection refused.");
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
            {
                { "exception.type", ex.GetType().FullName },
                { "exception.message", ex.Message },
                { "exception.stacktrace", ex.StackTrace ?? "" }
            }));
            activity?.SetTag("db.system", "postgresql");
            activity?.SetTag("db.statement", "SELECT * FROM users WHERE id = @id");
            _logger.LogError(ex, "Database error occurred");

            return StatusCode(500, new
            {
                error = "DatabaseError",
                message = ex.Message,
                traceId = Activity.Current?.TraceId.ToString()
            });
        }
    }

    // ── 4. Timeout (long delay) ─────────────────────────────────────
    [HttpGet("timeout")]
    public async Task<IActionResult> Timeout()
    {
        using var activity = ActivitySource.StartActivity("SimulateTimeout");
        activity?.SetTag("timeout.duration_ms", 30000);

        _logger.LogWarning("Starting 30-second timeout simulation");

        await Task.Delay(30000); // 30 seconds

        return Ok(new { message = "Completed after timeout delay" });
    }

    // ── 5. CPU Spike ────────────────────────────────────────────────
    [HttpGet("cpu-spike")]
    public IActionResult CpuSpike()
    {
        using var activity = ActivitySource.StartActivity("SimulateCpuSpike");
        activity?.SetTag("cpu.duration_seconds", 3);

        _logger.LogWarning("Starting CPU spike simulation (3 seconds)");

        var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < 3)
        {
            // Busy-wait to consume CPU
            _ = Math.Sqrt(Random.Shared.NextDouble());
        }

        activity?.SetTag("cpu.actual_duration_ms", sw.ElapsedMilliseconds);
        _logger.LogInformation("CPU spike completed after {Duration}ms", sw.ElapsedMilliseconds);

        return Ok(new
        {
            message = "CPU spike simulation completed",
            durationMs = sw.ElapsedMilliseconds,
            traceId = Activity.Current?.TraceId.ToString()
        });
    }

    // ── 6. Memory Spike ─────────────────────────────────────────────
    [HttpGet("memory-spike")]
    public IActionResult MemorySpike()
    {
        using var activity = ActivitySource.StartActivity("SimulateMemorySpike");

        _logger.LogWarning("Starting memory spike simulation");

        var data = new List<byte[]>();
        try
        {
            for (int i = 0; i < 50; i++)
            {
                data.Add(new byte[10 * 1024 * 1024]); // 10MB each → 500MB total
            }

            activity?.SetTag("memory.allocated_mb", data.Count * 10);
            _logger.LogInformation("Allocated {Count}MB", data.Count * 10);
        }
        finally
        {
            data.Clear();
            GC.Collect();
        }

        return Ok(new
        {
            message = "Memory spike simulation completed",
            allocatedMb = 500,
            traceId = Activity.Current?.TraceId.ToString()
        });
    }

    // ── 7. Dependency Failure ───────────────────────────────────────
    [HttpGet("dependency-failure")]
    public async Task<IActionResult> DependencyFailure()
    {
        using var activity = ActivitySource.StartActivity("SimulateDependencyFailure");
        activity?.SetTag("dependency.url", "http://unreachable-service.local:9999/api/data");

        _logger.LogWarning("Calling unreachable dependency");

        try
        {
            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(5);
            var response = await client.GetAsync("http://unreachable-service.local:9999/api/data");
            return Ok(); // never reached
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
            {
                { "exception.type", ex.GetType().FullName },
                { "exception.message", ex.Message },
                { "exception.stacktrace", ex.StackTrace ?? "" }
            }));
            _logger.LogError(ex, "Dependency call failed");

            return StatusCode(502, new
            {
                error = "DependencyFailure",
                message = ex.Message,
                traceId = Activity.Current?.TraceId.ToString()
            });
        }
    }

    // ── 8. Serialization Error ──────────────────────────────────────
    [HttpGet("serialization-error")]
    public IActionResult SerializationError()
    {
        using var activity = ActivitySource.StartActivity("SimulateSerializationError");

        _logger.LogWarning("Triggering serialization error with circular reference");

        try
        {
            var a = new CircularRef { Name = "A" };
            var b = new CircularRef { Name = "B", Ref = a };
            a.Ref = b;

            // This will throw due to circular reference
            var json = JsonSerializer.Serialize(a);
            return Ok(json); // never reached
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
            {
                { "exception.type", ex.GetType().FullName },
                { "exception.message", ex.Message },
                { "exception.stacktrace", ex.StackTrace ?? "" }
            }));
            _logger.LogError(ex, "Serialization failed");

            return StatusCode(500, new
            {
                error = "SerializationError",
                message = ex.Message,
                traceId = Activity.Current?.TraceId.ToString()
            });
        }
    }

    // ── 9. Auth Failure (401) ───────────────────────────────────────
    [HttpGet("auth-failure")]
    public IActionResult AuthFailure()
    {
        using var activity = ActivitySource.StartActivity("SimulateAuthFailure");
        activity?.SetTag("auth.type", "Bearer");
        activity?.SetStatus(ActivityStatusCode.Error, "Unauthorized");

        _logger.LogWarning("Simulating authentication failure (401)");

        return Unauthorized(new
        {
            error = "Unauthorized",
            message = "Invalid or missing authentication token",
            traceId = Activity.Current?.TraceId.ToString()
        });
    }

    // ── 10. Forbidden (403) ─────────────────────────────────────────
    [HttpGet("forbidden")]
    public IActionResult Forbidden()
    {
        using var activity = ActivitySource.StartActivity("SimulateForbidden");
        activity?.SetTag("auth.type", "Bearer");
        activity?.SetTag("auth.required_role", "Admin");
        activity?.SetStatus(ActivityStatusCode.Error, "Forbidden");

        _logger.LogWarning("Simulating authorization failure (403)");

        return StatusCode(403, new
        {
            error = "Forbidden",
            message = "You do not have permission to access this resource. Required role: Admin",
            traceId = Activity.Current?.TraceId.ToString()
        });
    }

    // ── 11. Slow Response ───────────────────────────────────────────
    [HttpGet("slow-response")]
    public async Task<IActionResult> SlowResponse()
    {
        using var activity = ActivitySource.StartActivity("SimulateSlowResponse");
        activity?.SetTag("delay.duration_ms", 5000);

        _logger.LogInformation("Starting slow response (5-second delay)");

        await Task.Delay(5000);

        _logger.LogInformation("Slow response completed");

        return Ok(new
        {
            message = "Slow response completed after 5 seconds",
            delayMs = 5000,
            traceId = Activity.Current?.TraceId.ToString()
        });
    }

    // ── Helper class for circular reference ─────────────────────────
    private class CircularRef
    {
        public string Name { get; set; } = "";
        public CircularRef? Ref { get; set; }
    }
}
