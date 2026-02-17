using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace PathfinderApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class HealthController : ControllerBase
{
    private static readonly ActivitySource ActivitySource = new("PathfinderApi");

    [HttpGet]
    public IActionResult Get()
    {
        using var activity = ActivitySource.StartActivity("HealthCheck");
        activity?.SetTag("health.status", "ok");

        return Ok(new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow,
            traceId = Activity.Current?.TraceId.ToString()
        });
    }
}
