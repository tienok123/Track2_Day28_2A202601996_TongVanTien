#!/usr/bin/env pwsh
# Apply a ``ports.<profile>`` file to the current PowerShell session.
#
# The lab ships ``ports.template`` (the default mapping) and lets you create a
# ``ports.local`` override to dodge port collisions on your machine. The env
# vars that file contains have to reach two consumers: ``docker compose``
# (which reads them through ``--env-file``) and the ``lab28`` CLI (which reads
# them through ``os.environ``). Running ``docker compose up --env-file ports.local``
# only covers the first consumer; the CLI still sees the original defaults and
# its ``/ready`` probe calls ``http://localhost:5000`` for MLflow even though
# the container is on 5100. This script does the dotenv-style source that
# Python's ``Settings.from_env`` expects, plus it derives the client-facing
# ``MLFLOW_TRACKING_URI`` / ``LAB28_VLLM_BASE_URL`` from the same port numbers.
#
# Usage (from any working directory inside the repo):
#
#     . .\scripts\apply_ports.ps1                # use ports.local if present, else ports.template
#     . .\scripts\apply_ports.ps1 -Profile dev   # force a specific profile
#
# Dot-source it so the assignments land in the caller's scope; running it as
# an external script would isolate them and they would be gone the moment the
# script returned.

[CmdletBinding()]
param(
    [string]$Profile = "",
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}

if (-not $Profile) {
    $local = Join-Path $RepoRoot "ports.local"
    if (Test-Path $local) {
        $Profile = "local"
    } else {
        $Profile = "template"
    }
}

$file = Join-Path $RepoRoot "ports.$Profile"
if (-not (Test-Path $file)) {
    throw "ports file not found: $file (looked for ports.local, ports.$Profile)"
}

Write-Host "[apply_ports] reading $file" -ForegroundColor Cyan

# Parse KEY=VALUE lines, ignoring blanks and ``#`` comments.
$envOverrides = @{}
foreach ($raw in Get-Content -LiteralPath $file) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) { continue }
    $key = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim()
    $envOverrides[$key] = $value
    Set-Item -Path "Env:$key" -Value $value
}

# Derive the client-facing URLs from the same port numbers so the CLI does not
# have to hard-code ``localhost:5000`` while the container is on 5100. Only the
# fields the readiness probe actually checks are filled in; adding more would
# silently override a student's intentional override.
if ($envOverrides.ContainsKey("LAB28_MLFLOW_PORT") -and -not $envOverrides.ContainsKey("MLFLOW_TRACKING_URI")) {
    $uri = "http://localhost:$($envOverrides['LAB28_MLFLOW_PORT'])"
    Set-Item -Path "Env:MLFLOW_TRACKING_URI" -Value $uri
    Write-Host "[apply_ports] MLFLOW_TRACKING_URI=$uri" -ForegroundColor DarkGray
}

if ($envOverrides.ContainsKey("LAB28_VLLM_PORT") -and -not $envOverrides.ContainsKey("LAB28_VLLM_BASE_URL")) {
    $base = "http://localhost:$($envOverrides['LAB28_VLLM_PORT'])/v1"
    Set-Item -Path "Env:LAB28_VLLM_BASE_URL" -Value $base
    Write-Host "[apply_ports] LAB28_VLLM_BASE_URL=$base" -ForegroundColor DarkGray
}

# Feast follows the same pattern: the compose file maps 6566/6570 from
# ``LAB28_FEAST_PORT`` / ``LAB28_FEAST_METRICS_PORT`` but only a URL lets the
# CLI reach the server from the host.
if ($envOverrides.ContainsKey("LAB28_FEAST_PORT") -and -not $envOverrides.ContainsKey("LAB28_FEAST_SERVER_URL")) {
    $url = "http://localhost:$($envOverrides['LAB28_FEAST_PORT'])"
    Set-Item -Path "Env:LAB28_FEAST_SERVER_URL" -Value $url
}

Write-Host "[apply_ports] applied $($envOverrides.Count) variable(s) from profile '$Profile'" -ForegroundColor Green
