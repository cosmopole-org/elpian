#Requires -Version 5.1
<#
.SYNOPSIS
    Elpian vs WebView End-to-End Benchmark Runner
.USAGE
    cd e:\projects\elpian
    .\benchmarks\run_benchmarks.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Paths ────────────────────────────────────────────────────────────────────
$ROOT        = Split-Path $PSScriptRoot -Parent
$EXAMPLE_DIR = Join-Path $ROOT 'example'
$BENCH_DIR   = $PSScriptRoot
$REPORT_DIR  = Join-Path $BENCH_DIR 'reports'
$WEBVIEW_DIR = Join-Path $BENCH_DIR 'webview'
$CHROME      = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$ts          = Get-Date -Format 'yyyyMMdd_HHmmss'

# ─── Helpers ──────────────────────────────────────────────────────────────────
function Log-Info  { param($m) Write-Host "  [INFO]  $m" -ForegroundColor Cyan   }
function Log-Ok    { param($m) Write-Host "  [OK]    $m" -ForegroundColor Green  }
function Log-Warn  { param($m) Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Log-Head  { param($m) Write-Host "`n╔══  $m" -ForegroundColor Magenta   }
function Fmt {
    param($v, $d = 1)
    if ($null -eq $v -or $v -eq '' -or $v -eq 0) { '—' }
    else { [math]::Round([double]$v, $d).ToString() }
}

function Run-ChromeHeadless {
    param([string]$HtmlPath, [int]$VirtualTimeMs = 25000)
    $uri = 'file:///' + ($HtmlPath -replace '\\','/')
    $args = @(
        '--headless=old', '--disable-gpu', '--no-sandbox',
        '--disable-dev-shm-usage', '--enable-precise-memory-info',
        "--virtual-time-budget=$VirtualTimeMs", '--dump-dom', $uri
    )
    try {
        $out = & $CHROME @args 2>$null
        return ($out -join "`n")
    } catch {
        Log-Warn "Chrome headless failed for $HtmlPath`: $_"
        return ''
    }
}

function Extract-BenchmarkResults {
    param([string]$DomDump, [string]$Scenario)
    if ($DomDump -match '(?s)<pre[^>]*id="results"[^>]*>(.*?)</pre>') {
        $json = $Matches[1].Trim()
        $json = $json -replace '&amp;','&' -replace '&lt;','<' -replace '&gt;','>' `
                      -replace '&quot;','"' -replace '&#39;',"'"
        if ($json -and $json -ne 'RUNNING') {
            try { return $json | ConvertFrom-Json } catch { Log-Warn "JSON parse failed for $Scenario" }
        }
    }
    Log-Warn "No results found in DOM for $Scenario"
    return [PSCustomObject]@{ scenario = $Scenario; error = 'no_results_in_dom' }
}

function Parse-ElpianLog {
    param([string]$LogPath)
    if (-not (Test-Path $LogPath)) {
        return @{ error = 'log_not_found' }
    }

    # Prefer the JSON file written by the driver
    $rawJson = Join-Path $REPORT_DIR 'elpian_raw_results.json'
    if (Test-Path $rawJson) {
        try {
            $raw = Get-Content $rawJson -Raw | ConvertFrom-Json
            if ($raw.benchmarks) { return $raw }
        } catch {}
    }

    # Fallback: parse BENCH lines from stdout
    $lines = Get-Content $LogPath
    $scenarios = @{}
    $cur = $null

    foreach ($line in $lines) {
        if ($line -match '\[BENCH[^\]]*\].*Scenario\s*:\s*(\S+)') {
            $cur = $Matches[1]
            if (-not $scenarios.ContainsKey($cur)) { $scenarios[$cur] = @{ scenario = $cur } }
        }
        if ($cur) {
            if ($line -match 'FPS\s*:\s*([\d.]+)')                 { $scenarios[$cur].fps = [double]$Matches[1] }
            if ($line -match 'Avg build\s*:\s*([\d.]+)')           { $scenarios[$cur].avg_build_ms = [double]$Matches[1] }
            if ($line -match 'Avg raster\s*:\s*([\d.]+)')          { $scenarios[$cur].avg_raster_ms = [double]$Matches[1] }
            if ($line -match 'Jank rate\s*:\s*([\d.]+)')           { $scenarios[$cur].jank_rate_pct = [double]$Matches[1] }
            if ($line -match 'Worst frame\s*:\s*([\d.]+)')         { $scenarios[$cur].worst_frame_ms = [double]$Matches[1] }
            if ($line -match 'First frame\s*:\s*([\d.]+)')         { $scenarios[$cur].first_frame_ms = [double]$Matches[1] }
            if ($line -match 'Total frames\s*:\s*(\d+)')           { $scenarios[$cur].total_frames = [int]$Matches[1] }
            if ($line -match 'P50 / P90 / P99:\s*([\d.]+)\s*/\s*([\d.]+)\s*/\s*([\d.]+)') {
                $scenarios[$cur].p50_ms = [double]$Matches[1]
                $scenarios[$cur].p90_ms = [double]$Matches[2]
                $scenarios[$cur].p99_ms = [double]$Matches[3]
            }
        }
        # S6 throughput line
        if ($line -match 'Throughput\s*:\s*([\d.]+)\s*builds/sec') {
            if (-not $scenarios.ContainsKey('S6_BuildThroughput')) { $scenarios['S6_BuildThroughput'] = @{ scenario='S6_BuildThroughput' } }
            $scenarios['S6_BuildThroughput'].fps = [double]$Matches[1]
        }
    }

    return @{ benchmarks = @($scenarios.Values); parsed_from = 'stdout'; log_path = $LogPath }
}

function Generate-ElpianReport {
    param($Results, $OutputDir)
    $path = Join-Path $OutputDir "elpian_benchmark_report_$ts.md"
    $benchmarks = if ($Results.benchmarks) { $Results.benchmarks } else { @() }

    $flutterVer = (& flutter --version 2>&1 | Select-String 'Flutter \d') -replace 'Flutter (\S+).*','$1'

    $rows = ''
    foreach ($b in $benchmarks) {
        $rows += "| ``$($b.scenario)`` | $(Fmt $b.fps) | $(Fmt $b.avg_build_ms 2) | $(Fmt $b.avg_raster_ms 2) | $(Fmt $b.p50_ms 2) | $(Fmt $b.p90_ms 2) | $(Fmt $b.p99_ms 2) | $(Fmt $b.jank_rate_pct 1) | $(Fmt $b.worst_frame_ms 1) | $(Fmt $b.first_frame_ms 1) | $($b.total_frames) |`n"
    }

    Set-Content -Path $path -Encoding utf8 -Value @"
# Elpian UI Framework — Benchmark Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Flutter:** $flutterVer
**Renderer:** Flutter CanvasKit (Chrome)
**Test runner:** \`flutter drive\` (integration_test)

---

## Summary Table

| Scenario | FPS | Avg Build (ms) | Avg Raster (ms) | P50 (ms) | P90 (ms) | P99 (ms) | Jank % | Worst (ms) | 1st Frame (ms) | Frames |
|----------|----:|---------------:|----------------:|---------:|---------:|---------:|-------:|-----------:|---------------:|-------:|
$rows
---

## Scenario Descriptions

| # | Name | What it tests |
|---|------|---------------|
| S1 | Basic JSON Rendering | Simple Column/Text/Card/Button tree — minimal baseline |
| S2 | Complex Dashboard | 24-card dashboard — nested containers, header, section, footer |
| S3 | Animation Smoothness | 10 AnimatedContainer widgets driven at 60 Hz via sinusoidal updates |
| S4 | Canvas Drawing | 70 primitives/frame via Elpian Canvas API (arcs, lines, rects, curves, text) |
| S5 | Long List Scroll | 100-item list with 40 drag gestures (scroll down + scroll up) |
| S6 | Widget Build Throughput | 100 cold JSON→Widget builds, no rendering (pure parse speed) |
| S7 | Rapid Re-render Storm | 200 consecutive setState() calls at 8 ms intervals |

---

## KPI Thresholds

| KPI | Excellent | Good | Needs Work |
|-----|-----------|------|------------|
| FPS | ≥ 55 | 40–55 | < 40 |
| Avg frame build | ≤ 16.7 ms | 16.7–25 ms | > 25 ms |
| Jank rate (>16.7 ms) | ≤ 5 % | 5–15 % | > 15 % |
| First frame | ≤ 100 ms | 100–300 ms | > 300 ms |
| P99 frame | ≤ 33 ms | 33–66 ms | > 66 ms |

---

## Notes
- Frame timings collected via \`SchedulerBinding.addTimingsCallback\` (includes both build and raster phases).
- Tests run in Flutter profile mode on Chrome for representative performance.
- "Jank" defined as any frame exceeding the 60 FPS budget (16.67 ms total).
- FPS for S6 represents widget build throughput (builds per second), not display frames.
"@
    return $path
}

function Generate-WebViewReport {
    param($Results, $OutputDir)
    $path = Join-Path $OutputDir "webview_benchmark_report_$ts.md"

    $scenarioDescs = @{
        'WV01_BasicRendering' = '50 cold DOM builds of a 24-card dashboard; forced reflow measurement; FCP via PerformanceObserver'
        'WV02_CSSAnimations'  = '120 rAF frames with 10 JS-driven bar animations + 3 CSS keyframe animations (spin, bounce, colorshift)'
        'WV03_ComplexLayout'  = 'CSS Grid+Flex dashboard with sidebar, stats grid, data table; reflow, re-layout, LCP, CLS'
        'WV04_CanvasDrawing'  = '150 rAF frames × 70 primitives; + 200 raw throughput frames; circles/lines/rects/curves/gradient/text'
        'WV05_ListScroll'     = '200-item list; 120 scroll frames; 200 DOM content updates; build+scroll+update metrics'
    }

    $md = @"
# WebView (Native Browser) — Benchmark Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Engine:** Google Chrome (Blink layout / V8 JS / Skia GPU)
**Mode:** Headless (--headless=old) with --virtual-time-budget

---

## Executive Summary

Native HTML/CSS/JS benchmarks serve as the performance baseline against which Elpian's JSON-driven rendering is compared. All pages use only standard browser APIs — no frameworks, no transpilation.

---

## Results by Scenario

"@
    foreach ($key in ($Results.Keys | Sort-Object)) {
        $r = $Results[$key]
        $desc = if ($scenarioDescs.ContainsKey($key)) { $scenarioDescs[$key] } else { '' }
        $md += "### $key`n`n"
        if ($desc) { $md += "_$desc_`n`n" }
        if ($r.error) {
            $md += "> **Error:** $($r.error)`n`n"
            continue
        }
        $md += "| Metric | Value |`n|--------|------:|`n"
        foreach ($prop in $r.PSObject.Properties | Where-Object { $_.Name -notin @('scenario','timestamp','user_agent') }) {
            $md += "| ``$($prop.Name)`` | $($prop.Value) |`n"
        }
        $md += "`n"
    }

    $md += @"
---

## Measurement Notes
- **FPS**: Measured as \`1000 / avgFrameDeltaMs\` over real \`requestAnimationFrame\` timestamps.
- **Jank**: Any frame exceeding 16.67 ms between rAF callbacks.
- **Build time**: Pure JS DOM construction time (no paint) for one complete page tree.
- **Reflow**: Time to read \`getBoundingClientRect()\` after a layout-invalidating mutation.
- **LCP/CLS**: Collected via \`PerformanceObserver\` with \`buffered: true\`.
- **Memory**: \`performance.memory.usedJSHeapSize\` (Chrome only).
"@

    Set-Content -Path $path -Value $md -Encoding utf8
    return $path
}

function Generate-ComparisonReport {
    param($ElpianResults, $WebViewResults, $OutputDir)
    $path = Join-Path $OutputDir "comparison_report_$ts.md"

    $elpianBenchmarks = if ($ElpianResults.benchmarks) { $ElpianResults.benchmarks } else { @() }

    $pairs = @(
        @{ elpian='S1_BasicRendering';      webview='WV01_BasicRendering'; label='Basic Rendering'     },
        @{ elpian='S3_AnimationSmoothness'; webview='WV02_CSSAnimations';  label='Animation FPS'       },
        @{ elpian='S2_ComplexDashboard';    webview='WV03_ComplexLayout';  label='Complex Layout'      },
        @{ elpian='S4_CanvasDrawing';       webview='WV04_CanvasDrawing';  label='Canvas Drawing'      },
        @{ elpian='S5_ListScroll';          webview='WV05_ListScroll';     label='List Scroll'         }
    )

    $rows = ''
    $findings = [System.Collections.Generic.List[string]]::new()

    foreach ($pair in $pairs) {
        $e = $elpianBenchmarks | Where-Object { $_.scenario -eq $pair.elpian } | Select-Object -First 1
        $w = $WebViewResults[$pair.webview]

        $eFps  = if ($e.fps)                             { [double]$e.fps }               else { $null }
        $wFps  = if ($w.fps)                             { [double]$w.fps }
                 elseif ($w.scroll_fps)                  { [double]$w.scroll_fps }
                 elseif ($w.build_throughput_per_sec)    { [double]$w.build_throughput_per_sec }
                 else                                    { $null }

        $eAvg  = if ($e.avg_build_ms)                   { [double]$e.avg_build_ms }      else { $null }
        $wAvg  = if ($w.avg_frame_ms)                   { [double]$w.avg_frame_ms }
                 elseif ($w.scroll_avg_ms)               { [double]$w.scroll_avg_ms }
                 elseif ($w.build_avg_ms)                { [double]$w.build_avg_ms }
                 else                                    { $null }

        $eJank = if ($e.jank_rate_pct)                  { [double]$e.jank_rate_pct }     else { $null }
        $wJank = if ($w.jank_rate_pct)                  { [double]$w.jank_rate_pct }
                 elseif ($w.scroll_jank_pct)             { [double]$w.scroll_jank_pct }  else { $null }

        $ratio   = '—'
        $verdict = '—'
        if ($null -ne $eFps -and $null -ne $wFps -and $wFps -gt 0) {
            $r = [math]::Round($eFps / $wFps, 2)
            $ratio = "×$r"
            if ($r -ge 0.9)     { $verdict = '✅ Comparable' }
            elseif ($r -ge 0.6) { $verdict = '⚠️ ~Slower'   }
            else                { $verdict = '❌ Slower'     }

            if ($r -lt 0.9) {
                $findings.Add("- **$($pair.label)**: Elpian is ~$([math]::Round((1-$r)*100))% slower in FPS ($(Fmt $eFps) vs $(Fmt $wFps)). WebView's native layout engine and CSS compositor have inherent advantages here.")
            } else {
                $findings.Add("- **$($pair.label)**: Elpian is **comparable** to WebView ($(Fmt $eFps) vs $(Fmt $wFps) FPS). Flutter's CanvasKit compositor matches native browser rendering at this complexity level.")
            }
        }

        $rows += "| $($pair.label) | $(Fmt $eFps) | $(Fmt $wFps) | $ratio | $(Fmt $eAvg 2) | $(Fmt $wAvg 2) | $(Fmt $eJank 1)% | $(Fmt $wJank 1)% | $verdict |`n"
    }

    $findingsMd = if ($findings.Count -gt 0) { $findings -join "`n" } else { '_No data to compare. Check benchmark logs._' }

    Set-Content -Path $path -Encoding utf8 -Value @"
# Elpian vs WebView — Comparison Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

---

## Methodology

| Aspect | Elpian | WebView |
|--------|--------|---------|
| Framework | Flutter 3.x / CanvasKit | Chrome Blink + V8 |
| UI source | JSON → ElpianEngine → Flutter widgets | HTML/CSS/JS (no framework) |
| Animation | Flutter AnimatedContainer / SchedulerBinding | CSS keyframes + rAF |
| Canvas | Elpian Canvas API → CustomPaint | Native Canvas 2D |
| Test harness | \`flutter drive\` + \`integration_test\` | Chrome \`--headless=old\` + DOM dump |
| FPS source | \`SchedulerBinding.addTimingsCallback\` | \`requestAnimationFrame\` delta |

---

## Side-by-Side Results

| Scenario | Elpian FPS | WebView FPS | FPS Ratio | Elpian Avg ms | WebView Avg ms | Elpian Jank | WebView Jank | Verdict |
|----------|----------:|------------:|----------:|--------------:|---------------:|------------:|-------------:|---------|
$rows
---

## Findings

$findingsMd

---

## Architecture Trade-off Analysis

### Elpian Strengths
| Strength | Detail |
|----------|--------|
| Server-driven UI | One JSON payload renders identically on all platforms — zero per-platform code |
| Cross-platform parity | iOS, Android, desktop, and web share the same rendering pipeline |
| Sandboxed scripting | Rust VM + QuickJS run untrusted code without browser security model complexity |
| Widget richness | 60+ Flutter widgets + 70+ HTML elements available from JSON |
| Type-safe animation | Flutter's Tween/Curve system gives smooth, deterministic animation |
| Offline-first | Widget definitions are code; only data payloads need network |

### WebView Strengths
| Strength | Detail |
|----------|--------|
| Zero serialization | HTML parsed directly — no JSON→widget intermediary |
| CSS compositor thread | CSS keyframe animations bypass JS and run on GPU compositor |
| Mature layout engine | Blink's flexbox/grid layout is battle-tested across billions of pages |
| Incremental DOM | Browser diffs and patches the render tree with sub-element granularity |
| Web standards | Full access to Fetch, WebSockets, WebRTC, WebGL, Gamepad API, etc. |
| DevTools ecosystem | Chrome DevTools, Lighthouse, WebPageTest all target HTML natively |

### Recommendation Matrix

| Use case | Recommended |
|----------|-------------|
| Cross-platform app (iOS + Android + web) | **Elpian** |
| Web-only app requiring CSS animations | **WebView** |
| Server-driven dynamic UI | **Elpian** |
| Marketing/content pages with rich CSS | **WebView** |
| Sandboxed user scripting | **Elpian** |
| Complex data tables + grid layouts | **WebView** |
| Real-time canvas games | **WebView** (native Canvas 2D is faster) |
| Flutter team expanding to web | **Elpian** |

---

## Conclusion

Elpian and native WebView both achieve smooth rendering for typical app workloads. The performance gap, where it exists, reflects architectural differences rather than implementation quality: WebView's CSS compositor thread and native layout engine have inherent advantages for CSS-heavy and animation-heavy scenarios, while Elpian's JSON-driven pipeline trades some raw rendering throughput for **platform universality, sandboxed scripting, and server-driven UI flexibility**.

For most application workloads — dashboards, forms, content lists, navigation — both approaches deliver acceptable frame rates. The choice should be made on architectural grounds (platform scope, team expertise, server integration) rather than on FPS numbers alone.

---

*Reports generated by \`benchmarks/run_benchmarks.ps1\`. Raw data in \`benchmarks/reports/*.json\`.*
"@
    return $path
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║    ELPIAN vs WEBVIEW  —  Full Benchmark Suite                ║
║    Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                         ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta

New-Item -ItemType Directory -Force -Path $REPORT_DIR | Out-Null

# ── PHASE 1: Flutter / Elpian ─────────────────────────────────────────────────
Log-Head 'PHASE 1 — Flutter / Elpian Integration Benchmarks'

Log-Info 'Running flutter pub get in example/...'
Push-Location $EXAMPLE_DIR
try {
    & flutter pub get 2>&1 | Tee-Object (Join-Path $REPORT_DIR 'flutter_pub_get.log')
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    Log-Ok 'flutter pub get OK'
} finally { Pop-Location }

Log-Info 'Running flutter drive (Chrome will open briefly — do not close it)...'
$flutterLog = Join-Path $REPORT_DIR 'flutter_drive_raw.log'
Push-Location $EXAMPLE_DIR
$flutterExitCode = 0
try {
    & flutter drive `
        --driver=test_driver/integration_test_driver.dart `
        --target=integration_test/elpian_benchmark_test.dart `
        -d chrome `
        --no-pub 2>&1 | Tee-Object $flutterLog
    $flutterExitCode = $LASTEXITCODE
} catch {
    Log-Warn "flutter drive threw: $_"
    $flutterExitCode = 1
} finally { Pop-Location }

if ($flutterExitCode -eq 0) { Log-Ok 'flutter drive completed' }
else { Log-Warn "flutter drive exited $flutterExitCode — parsing available output" }

$elpianResults = Parse-ElpianLog -LogPath $flutterLog
$elpianResults | ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $REPORT_DIR 'elpian_results.json') -Encoding utf8
Log-Ok "Elpian results → $REPORT_DIR\elpian_results.json"

# ── PHASE 2: WebView HTML Benchmarks ─────────────────────────────────────────
Log-Head 'PHASE 2 — WebView HTML Benchmarks (Chrome Headless)'

$webviewPages = @(
    @{ file='01_basic_rendering.html'; scenario='WV01_BasicRendering' },
    @{ file='02_css_animations.html';  scenario='WV02_CSSAnimations'  },
    @{ file='03_complex_layout.html';  scenario='WV03_ComplexLayout'  },
    @{ file='04_canvas_drawing.html';  scenario='WV04_CanvasDrawing'  },
    @{ file='05_list_scroll.html';     scenario='WV05_ListScroll'     }
)

$webviewResults = @{}
foreach ($page in $webviewPages) {
    $htmlPath = Join-Path $WEBVIEW_DIR $page.file
    Log-Info "Running $($page.file)..."
    $dom    = Run-ChromeHeadless -HtmlPath $htmlPath -VirtualTimeMs 25000
    $parsed = Extract-BenchmarkResults -DomDump $dom -Scenario $page.scenario
    $webviewResults[$page.scenario] = $parsed

    $fps = if ($parsed.fps)            { $parsed.fps }
           elseif ($parsed.scroll_fps) { $parsed.scroll_fps }
           elseif ($parsed.build_throughput_per_sec) { $parsed.build_throughput_per_sec }
           else { '—' }
    Log-Ok "$($page.scenario): fps=$fps"
}

@{ suite='WebView Benchmark Suite'; timestamp=(Get-Date -Format 'o'); results=$webviewResults } |
    ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $REPORT_DIR 'webview_results.json') -Encoding utf8
Log-Ok "WebView results → $REPORT_DIR\webview_results.json"

# ── PHASE 3: Reports ──────────────────────────────────────────────────────────
Log-Head 'PHASE 3 — Generating Reports'

$rElpian  = Generate-ElpianReport  -Results $elpianResults      -OutputDir $REPORT_DIR
$rWebView = Generate-WebViewReport -Results $webviewResults      -OutputDir $REPORT_DIR
$rCompare = Generate-ComparisonReport -ElpianResults $elpianResults -WebViewResults $webviewResults -OutputDir $REPORT_DIR

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║  Done!  Reports written to benchmarks/reports/               ║
║                                                              ║
║  elpian_benchmark_report_$ts.md          ║
║  webview_benchmark_report_$ts.md         ║
║  comparison_report_$ts.md                ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
