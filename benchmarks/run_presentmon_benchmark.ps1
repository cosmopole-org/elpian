#Requires -Version 5.1
# PresentMon GPU Benchmark Runner v3
# Per-scenario real GPU capture: Elpian (5 screens) + WebView (8 pages)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PRESENTMON  = 'C:\Program Files\Intel\PresentMon\PresentMonConsoleApplication\PresentMon-2.4.1-x64.exe'
$ELPIAN_EXE  = 'E:\projects\elpian\build\elpian_windows\elpian_ui_example.exe'
$CHROME      = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$WEBVIEW     = 'E:\projects\elpian\benchmarks\webview'
$REPORTS     = 'E:\projects\elpian\benchmarks\reports\presentmon'
$EL_CAPTURE  = 15   # seconds per Elpian scenario
$WV_CAPTURE  = 20   # seconds per WebView scenario
$EL_WARMUP   = 3    # seconds after app launch before first scenario
$WV_WARMUP   = 4    # seconds after Chrome open before capture

New-Item -ItemType Directory -Force $REPORTS | Out-Null

# -- Win32 / Mouse automation --------------------------------------------------
# Logical coordinates are for Flutter's 1280x720 layout (win32_window.cpp).
# ClickAt / ScrollAt / Wiggle scale automatically to the real physical client rect.
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;

public class MouseSim {
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, System.Text.StringBuilder sb, int n);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    const uint MD = 0x0002, MU = 0x0004, MW = 0x0800;
    // Client area is 1264x681 (window 1280x720 minus 8px borders + 31px title bar).
    // Flutter at 100% DPI uses logical px == physical px, so coordinates are direct
    // client pixels -- no scaling distortion.
    const int LW = 1264, LH = 681;

    public static IntPtr FindFlutterWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, _) => {
            if (!IsWindowVisible(h)) return true;
            var sb = new System.Text.StringBuilder(256);
            if (GetClassName(h, sb, 256) > 0 &&
                sb.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") {
                found = h; return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    static POINT LogToScreen(IntPtr hwnd, int lx, int ly) {
        RECT cr; GetClientRect(hwnd, out cr);
        int pw = cr.Right - cr.Left, ph = cr.Bottom - cr.Top;
        POINT p;
        p.X = (pw > 0) ? lx * pw / LW : lx;
        p.Y = (ph > 0) ? ly * ph / LH : ly;
        ClientToScreen(hwnd, ref p);
        return p;
    }

    // Click at a logical position within the Flutter window
    public static void ClickAt(IntPtr hwnd, int lx, int ly) {
        ShowWindow(hwnd, 9);
        SetForegroundWindow(hwnd);
        System.Threading.Thread.Sleep(80);
        POINT s = LogToScreen(hwnd, lx, ly);
        SetCursorPos(s.X, s.Y);
        System.Threading.Thread.Sleep(50);
        mouse_event(MD, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        mouse_event(MU, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(50);
    }

    // Scroll wheel at a logical position (delta > 0 = up, < 0 = down)
    public static void ScrollAt(IntPtr hwnd, int lx, int ly, int delta) {
        POINT s = LogToScreen(hwnd, lx, ly);
        SetCursorPos(s.X, s.Y);
        System.Threading.Thread.Sleep(30);
        mouse_event(MW, 0, 0, (uint)delta, IntPtr.Zero);
        System.Threading.Thread.Sleep(30);
    }

    // Circular mouse wiggle at logical position to drive Flutter redraws
    public static void Wiggle(IntPtr hwnd, int lx, int ly, int durationMs, int intervalMs) {
        ShowWindow(hwnd, 9);
        SetForegroundWindow(hwnd);
        RECT cr; GetClientRect(hwnd, out cr);
        int pw = cr.Right - cr.Left, ph = cr.Bottom - cr.Top;
        POINT o; o.X = 0; o.Y = 0; ClientToScreen(hwnd, ref o);
        int cx = o.X + (pw > 0 ? lx * pw / LW : lx);
        int cy = o.Y + (ph > 0 ? ly * ph / LH : ly);
        var sw = Stopwatch.StartNew();
        int r = 45, step = 0;
        while (sw.ElapsedMilliseconds < durationMs) {
            double a = step * 0.12;
            SetCursorPos(cx + (int)(r * Math.Cos(a)), cy + (int)(r * Math.Sin(a)));
            System.Threading.Thread.Sleep(intervalMs);
            step++;
        }
    }

    // Legacy method for Chrome (absolute screen coordinates)
    public static void FocusAndWiggle(int pid, int cx, int cy, int durationMs, int intervalMs) {
        try {
            var p = Process.GetProcessById(pid);
            if (p.MainWindowHandle != IntPtr.Zero) {
                ShowWindow(p.MainWindowHandle, 9);
                SetForegroundWindow(p.MainWindowHandle);
            }
        } catch {}
        var sw = Stopwatch.StartNew();
        int r = 30, step = 0;
        while (sw.ElapsedMilliseconds < durationMs) {
            double a = step * 0.15;
            SetCursorPos(cx + (int)(r * Math.Cos(a)), cy + (int)(r * Math.Sin(a)));
            System.Threading.Thread.Sleep(intervalMs);
            step++;
        }
    }
}
"@

# -- HTTP server for WebView pages ---------------------------------------------
function Start-BenchServer {
    param([string]$Root, [int]$Port = 8781)
    $hl = [System.Net.HttpListener]::new()
    $hl.Prefixes.Add("http://localhost:$Port/")
    $hl.Prefixes.Add("http://127.0.0.1:$Port/")
    $hl.Start()
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('hl',   $hl)
    $rs.SessionStateProxy.SetVariable('root', $Root)
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript({
        while ($hl.IsListening) {
            try {
                $ctx  = $hl.GetContext()
                $path = $ctx.Request.Url.LocalPath.TrimStart('/')
                if (-not $path) { $path = 'index.html' }
                $file = Join-Path $root $path
                if (Test-Path $file) {
                    $bytes = [IO.File]::ReadAllBytes($file)
                    $ctx.Response.ContentType = switch ([IO.Path]::GetExtension($file)) {
                        '.js'  { 'application/javascript' }
                        '.css' { 'text/css' }
                        default { 'text/html; charset=utf-8' }
                    }
                    $ctx.Response.ContentLength64 = $bytes.Length
                    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else { $ctx.Response.StatusCode = 404 }
            } catch {}
            try { $ctx.Response.Close() } catch {}
        }
    })
    $null = $ps.BeginInvoke()
    return [PSCustomObject]@{ Listener=$hl; PS=$ps; RS=$rs }
}
function Stop-BenchServer { param($srv)
    try { $srv.Listener.Stop(); $srv.Listener.Close() } catch {}
    try { $srv.PS.Stop(); $srv.PS.Dispose() } catch {}
    try { $srv.RS.Close(); $srv.RS.Dispose() } catch {}
}

# -- PresentMon helpers --------------------------------------------------------
function Start-PmCapture {
    param([string]$ProcName, [string]$Csv, [int]$Secs)
    Remove-Item $Csv -ErrorAction SilentlyContinue
    Start-Process $PRESENTMON -ArgumentList @(
        '--process_name', $ProcName,
        '--output_file',  $Csv,
        '--v2_metrics',
        '--timed',                 $Secs,
        '--terminate_after_timed',
        '--stop_existing_session'
    ) -PassThru -NoNewWindow
}
function Wait-PmCapture { param($pm, [int]$Secs)
    $pm.WaitForExit(($Secs + 20) * 1000) | Out-Null
    if (-not $pm.HasExited) { try { $pm.Kill() } catch {} }
}

# -- CSV parser ----------------------------------------------------------------
function Read-PmCsv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    [array]$rows = @(try { Import-Csv $Path } catch { @() })
    if ($rows.Count -lt 3) { return $null }

    $cols = $rows[0].PSObject.Properties.Name

    $ftCol = @('FrameTime','msBetweenPresents','MsInPresentAPI') |
             Where-Object { $cols -contains $_ } | Select-Object -First 1
    if (-not $ftCol) { return $null }

    [array]$ft = @($rows | ForEach-Object {
        $v = [double]0
        if ([double]::TryParse($_.$ftCol, [Globalization.NumberStyles]::Any,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0.5 -and $v -lt 2000) { $v }
    } | Where-Object { $null -ne $_ })
    if ($ft.Count -lt 3) { return $null }

    $gpuCol = @('GPUBusy','msGPUBusy','GPUTime','msGPUActive') |
              Where-Object { $cols -contains $_ } | Select-Object -First 1
    [array]$gpu = if ($gpuCol) {
        @($rows | ForEach-Object {
            $v = [double]0
            if ([double]::TryParse($_.$gpuCol, [Globalization.NumberStyles]::Any,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -ge 0) { $v }
        } | Where-Object { $null -ne $_ })
    } else { @() }

    $latCol = @('DisplayLatency','msDisplayLatency') |
              Where-Object { $cols -contains $_ } | Select-Object -First 1
    [array]$lat = if ($latCol) {
        @($rows | ForEach-Object {
            $v = [double]0
            if ([double]::TryParse($_.$latCol, [Globalization.NumberStyles]::Any,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0 -and $v -lt 5000) { $v }
        } | Where-Object { $null -ne $_ })
    } else { @() }

    $cpuCol = @('CPUBusy','msInPresentAPI') |
              Where-Object { $cols -contains $_ } | Select-Object -First 1
    [array]$cpuT = if ($cpuCol) {
        @($rows | ForEach-Object {
            $v = [double]0
            if ([double]::TryParse($_.$cpuCol, [Globalization.NumberStyles]::Any,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -ge 0) { $v }
        } | Where-Object { $null -ne $_ })
    } else { @() }

    $rtCol   = @('PresentRuntime','Runtime') | Where-Object { $cols -contains $_ } | Select-Object -First 1
    $runtime = if ($rtCol) { $rows[0].$rtCol } else { 'Unknown' }
    $pmCol   = @('PresentMode') | Where-Object { $cols -contains $_ } | Select-Object -First 1
    $pmode   = if ($pmCol) { $rows[0].$pmCol } else { 'Unknown' }

    [array]$s = @($ft | Sort-Object)
    $n = $s.Count

    function Pct($arr, $p) {
        $i = [int][math]::Floor($p / 100.0 * ($arr.Count - 1))
        if ($i -lt 0) { $i = 0 }
        if ($i -ge $arr.Count) { $i = $arr.Count - 1 }
        $arr[$i]
    }

    $avg    = ($ft | Measure-Object -Average).Average
    $fps    = [math]::Round(1000.0 / $avg, 1)
    $p50    = [math]::Round((Pct $s 50), 2)
    $p90    = [math]::Round((Pct $s 90), 2)
    $p99    = [math]::Round((Pct $s 99), 2)
    $p999   = [math]::Round((Pct $s 99.9), 2)
    $worst  = [math]::Round($s[-1], 2)

    $low1n   = [math]::Max(1, [int]($n * 0.01))
    $low1fps = [math]::Round(1000.0 / (($s | Select-Object -Last $low1n | Measure-Object -Average).Average), 1)
    $low01n  = [math]::Max(1, [int]($n * 0.001))
    $low01fps= [math]::Round(1000.0 / (($s | Select-Object -Last $low01n | Measure-Object -Average).Average), 1)

    [array]$jankF = @($ft | Where-Object { $_ -gt 16.667 })
    $jank    = $jankF.Count
    $jankPct = [math]::Round($jank / $n * 100, 1)

    function SafeAvg($arr) {
        if ($arr.Count -eq 0) { return $null }
        $m = ($arr | Measure-Object -Average).Average
        if ($null -eq $m) { return $null }
        [math]::Round($m, 2)
    }
    [array]$latPos = @($lat | Where-Object { $_ -gt 0 })
    $avgGpu = SafeAvg $gpu
    $avgLat = SafeAvg $latPos
    $avgCpu = SafeAvg $cpuT

    return [PSCustomObject]@{
        Frames=      $n
        AvgFPS=      $fps
        FPS1Low=     $low1fps
        FPS01Low=    $low01fps
        AvgMs=       [math]::Round($avg, 2)
        P50=         $p50
        P90=         $p90
        P99=         $p99
        P999=        $p999
        Worst=       $worst
        JankPct=     $jankPct
        AvgGPUMs=    $avgGpu
        AvgLatMs=    $avgLat
        AvgCPUMs=    $avgCpu
        Runtime=     $runtime
        PresentMode= $pmode
    }
}

function FmtVal { param($v, $suf = '')
    if ($null -eq $v -or $v -eq '') { return 'n/a' }
    return "$v$suf"
}

# ===============================================================================
Write-Host "`n+=== PresentMon GPU Benchmark Suite v3 ===+" -ForegroundColor Magenta
Write-Host ("  PresentMon 2.4.1  |  el={0}s  wv={1}s  |  {2}" -f `
    $EL_CAPTURE, $WV_CAPTURE, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray

Get-Process -Name 'elpian_ui_example', 'chrome' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# ===============================================================================
# ELPIAN -- 5 real scenarios with navigation and content interaction
# ===============================================================================
#
# Home screen list layout (client area 1264x681, AppBar=56px, padding=16px):
#   Item i center-Y = 108 + i * 82   (72px card + 10px separator per slot)
#   Item 0  QuickJS Calculator  y=108   (fully visible)
#   Item 1  QuickJS Whiteboard  y=190   (fully visible)
#   Item 2  QuickJS Runtime     y=272   (fully visible)
#   Item 3  AST VM              y=354   (fully visible)
#   Item 4  DOM+Canvas Logic    y=436   (fully visible)
#   Item 5  Ordinary UI         y=518   (fully visible)
#   Item 6  Enhanced UI         y=600   (fully visible)
#   Item 7  Canvas API          y=682   (card top y=646, only top 35px visible -- click at y=663)
#   Item 12 Landing Page        center at y=629 when list scrolled to max
#             (content=1088px, viewport=625px, max-scroll=463px: 1036-463+56=629)
#
# AppBar back button (child screens):  x=40, y=28

Write-Host "`n--- Launching Elpian Windows app ---" -ForegroundColor Cyan
$eProc = Start-Process $ELPIAN_EXE -PassThru
Write-Host ("  PID={0}  waiting {1}s for first frame..." -f $eProc.Id, $EL_WARMUP) -ForegroundColor DarkGray
Start-Sleep -Seconds $EL_WARMUP

$eHwnd = [MouseSim]::FindFlutterWindow()
if ($eHwnd -eq [IntPtr]::Zero) {
    Write-Host "  WARN: Flutter window not found -- click positions may miss" -ForegroundColor Yellow
}
Write-Host ("  HWND=0x{0:X}  ready" -f $eHwnd.ToInt64()) -ForegroundColor DarkGray

$elStats = [ordered]@{}

# -- E01: Home List Scroll -----------------------------------------------------
Write-Host "`n[E01/5] HomeListScroll" -ForegroundColor Cyan
$csv = Join-Path $REPORTS 'elpian_E01_HomeListScroll.csv'
$pm  = Start-PmCapture 'elpian_ui_example.exe' $csv $EL_CAPTURE

# Hover over first few items (triggers hover redraws), then scroll down and up
[MouseSim]::Wiggle($eHwnd, 640, 300, 1500, 16)
1..5 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 640, 400, -120); Start-Sleep -Milliseconds 350 }
[MouseSim]::Wiggle($eHwnd, 640, 400, 3000, 16)
1..5 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 640, 400, -120); Start-Sleep -Milliseconds 350 }
[MouseSim]::Wiggle($eHwnd, 640, 400, 2000, 16)
1..10 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 640, 400, 120); Start-Sleep -Milliseconds 300 }
[MouseSim]::Wiggle($eHwnd, 640, 300, 2000, 16)

Wait-PmCapture $pm $EL_CAPTURE
$elStats['E01_HomeListScroll'] = Read-PmCsv $csv
$s = $elStats['E01_HomeListScroll']
if ($s) { Write-Host ("  fps={0}  p99={1}ms  gpu={2}ms  frames={3}" -f $s.AvgFPS,$s.P99,$s.AvgGPUMs,$s.Frames) -ForegroundColor Green }
else    { Write-Host "  WARN: no frame data" -ForegroundColor Yellow }

# -- E02: QuickJS Calculator (item 0, y=108) -----------------------------------
Write-Host "`n[E02/5] QuickJSCalculator" -ForegroundColor Cyan
$csv = Join-Path $REPORTS 'elpian_E02_QuickJSCalc.csv'
$pm  = Start-PmCapture 'elpian_ui_example.exe' $csv $EL_CAPTURE

# Navigate into the screen (captures the push transition animation)
[MouseSim]::ClickAt($eHwnd, 640, 108)
Start-Sleep -Milliseconds 1500  # let transition + content load settle

# Hover around the calculator buttons area and wiggle for the rest of capture
[MouseSim]::Wiggle($eHwnd, 640, 420, ($EL_CAPTURE * 1000 - 2000), 16)

Wait-PmCapture $pm $EL_CAPTURE

# Navigate back before next scenario
[MouseSim]::ClickAt($eHwnd, 40, 28)
Start-Sleep -Milliseconds 700

$elStats['E02_QuickJSCalc'] = Read-PmCsv $csv
$s = $elStats['E02_QuickJSCalc']
if ($s) { Write-Host ("  fps={0}  p99={1}ms  gpu={2}ms  frames={3}" -f $s.AvgFPS,$s.P99,$s.AvgGPUMs,$s.Frames) -ForegroundColor Green }
else    { Write-Host "  WARN: no frame data" -ForegroundColor Yellow }

# -- E03: Ordinary UI -- JSON rendering baseline (item 5, y=518) ---------------
Write-Host "`n[E03/5] OrdinaryUI" -ForegroundColor Cyan
$csv = Join-Path $REPORTS 'elpian_E03_OrdinaryUI.csv'
$pm  = Start-PmCapture 'elpian_ui_example.exe' $csv $EL_CAPTURE

[MouseSim]::ClickAt($eHwnd, 640, 518)
Start-Sleep -Milliseconds 1500

# Scroll through the JSON-rendered examples panel and wiggle
1..3 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 900, 400, -120); Start-Sleep -Milliseconds 500 }
[MouseSim]::Wiggle($eHwnd, 900, 400, 5000, 16)
1..3 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 900, 400, 120); Start-Sleep -Milliseconds 500 }
[MouseSim]::Wiggle($eHwnd, 900, 400, ($EL_CAPTURE * 1000 - 6500), 16)

Wait-PmCapture $pm $EL_CAPTURE

[MouseSim]::ClickAt($eHwnd, 40, 28)
Start-Sleep -Milliseconds 700

$elStats['E03_OrdinaryUI'] = Read-PmCsv $csv
$s = $elStats['E03_OrdinaryUI']
if ($s) { Write-Host ("  fps={0}  p99={1}ms  gpu={2}ms  frames={3}" -f $s.AvgFPS,$s.P99,$s.AvgGPUMs,$s.Frames) -ForegroundColor Green }
else    { Write-Host "  WARN: no frame data" -ForegroundColor Yellow }

# -- E04: Canvas API -- 5-tab NavigationRail (item 7, card top y=646, click at y=663) ---
Write-Host "`n[E04/5] CanvasAPI" -ForegroundColor Cyan
$csv = Join-Path $REPORTS 'elpian_E04_CanvasAPI.csv'
$pm  = Start-PmCapture 'elpian_ui_example.exe' $csv $EL_CAPTURE

# Item 7 center (y=682) is 1px below the client bottom (681). The card top is at
# y=646 and the visible strip is y=646-681 (35px). Click at the center of that strip.
[MouseSim]::ClickAt($eHwnd, 640, 663)
Start-Sleep -Milliseconds 1500

# Cycle through NavigationRail tabs: Shapes(y~=120) Paths(~=192) Text(~=264) Gradients(~=336) Transforms(~=408)
# Each tab switch triggers a full content redraw
$railYs = @(120, 192, 264, 336, 408, 120, 192, 264, 336, 408)
foreach ($ry in $railYs) {
    [MouseSim]::ClickAt($eHwnd, 36, $ry)
    Start-Sleep -Milliseconds 800
    [MouseSim]::Wiggle($eHwnd, 700, 400, 500, 16)
}
[MouseSim]::Wiggle($eHwnd, 700, 400, ($EL_CAPTURE * 1000 - 14000), 16)

Wait-PmCapture $pm $EL_CAPTURE

[MouseSim]::ClickAt($eHwnd, 40, 28)
Start-Sleep -Milliseconds 700

$elStats['E04_CanvasAPI'] = Read-PmCsv $csv
$s = $elStats['E04_CanvasAPI']
if ($s) { Write-Host ("  fps={0}  p99={1}ms  gpu={2}ms  frames={3}" -f $s.AvgFPS,$s.P99,$s.AvgGPUMs,$s.Frames) -ForegroundColor Green }
else    { Write-Host "  WARN: no frame data" -ForegroundColor Yellow }

# -- E05: Landing Page -- large JSON layout (item 12, requires list scroll) -----
Write-Host "`n[E05/5] LandingPage" -ForegroundColor Cyan
$csv = Join-Path $REPORTS 'elpian_E05_LandingPage.csv'

# Scroll to end of list. List content = 1088px, viewport = 625px, max-scroll = 463px.
# 4 notches of any typical scroll speed (>120px/notch) reaches the max-scroll end.
# At max-scroll, item 12 center sits at client y = 1036 - 463 + 56 = 629.
Write-Host "  Scrolling home list to reveal Landing Page..." -ForegroundColor DarkGray
1..4 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 640, 400, -120); Start-Sleep -Milliseconds 400 }
Start-Sleep -Milliseconds 400

$pm = Start-PmCapture 'elpian_ui_example.exe' $csv $EL_CAPTURE

# Item 12 center is at y~=629 when list is at max scroll -- click there.
[MouseSim]::ClickAt($eHwnd, 640, 620)
Start-Sleep -Milliseconds 2000  # large JSON page may take longer to render

# Scroll through the landing page content and wiggle
1..4 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 640, 400, -120); Start-Sleep -Milliseconds 600 }
[MouseSim]::Wiggle($eHwnd, 640, 400, 4000, 16)
1..4 | ForEach-Object { [MouseSim]::ScrollAt($eHwnd, 640, 400, 120); Start-Sleep -Milliseconds 600 }
[MouseSim]::Wiggle($eHwnd, 640, 400, ($EL_CAPTURE * 1000 - 9000), 16)

Wait-PmCapture $pm $EL_CAPTURE

[MouseSim]::ClickAt($eHwnd, 40, 28)
Start-Sleep -Milliseconds 700

$elStats['E05_LandingPage'] = Read-PmCsv $csv
$s = $elStats['E05_LandingPage']
if ($s) { Write-Host ("  fps={0}  p99={1}ms  gpu={2}ms  frames={3}" -f $s.AvgFPS,$s.P99,$s.AvgGPUMs,$s.Frames) -ForegroundColor Green }
else    { Write-Host "  WARN: no frame data" -ForegroundColor Yellow }

# Done with Elpian
try { if (-not $eProc.HasExited) { $eProc.Kill() } } catch {}
Start-Sleep -Milliseconds 600

# ===============================================================================
# WEBVIEW -- 8 Chrome scenarios
# ===============================================================================
$server = Start-BenchServer -Root $WEBVIEW -Port 8781
Start-Sleep -Milliseconds 500
try {
    $ping = Invoke-WebRequest 'http://127.0.0.1:8781/01_basic_rendering.html' -UseBasicParsing -TimeoutSec 3 -EA Stop
    Write-Host ("`n  HTTP server OK ({0} bytes)" -f $ping.RawContentLength) -ForegroundColor DarkGray
} catch { Write-Host "`n  HTTP server WARN: $_" -ForegroundColor Yellow }

$wvScenarios = [ordered]@{
    'WV01_BasicRendering'            = '01_basic_rendering.html'
    'WV02_CSSAnimations'             = '02_css_animations.html'
    'WV03_ComplexLayout'             = '03_complex_layout.html'
    'WV04_CanvasDrawing'             = '04_canvas_drawing.html'
    'WV05_ListScroll'                = '05_list_scroll.html'
    'WV06_ComplexDashboard'          = '06_complex_dashboard.html'
    'WV07_SmoothAnimations'          = '07_smooth_animations.html'
    'WV08_InteractiveResponsiveness' = '08_interactive_responsiveness.html'
}

$wvStats = [ordered]@{}
$idx = 1
foreach ($key in $wvScenarios.Keys) {
    Write-Host ("`n[WV{0:D2}/8] {1}" -f $idx, $key) -ForegroundColor Cyan
    $idx++
    $csv   = Join-Path $REPORTS ("webview_{0}.csv" -f $key)
    $url   = "http://localhost:8781/" + $wvScenarios[$key]
    $udDir = Join-Path $env:TEMP ("pmb_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $udDir | Out-Null

    $chromeArgs = @(
        '--no-sandbox', '--no-proxy-server', '--disable-dev-shm-usage',
        '--enable-precise-memory-info', '--window-size=1280,900',
        ("--user-data-dir=" + $udDir), $url
    )
    $cProc = Start-Process $CHROME -ArgumentList $chromeArgs -PassThru
    Write-Host ("  PID={0}  warming up {1}s..." -f $cProc.Id, $WV_WARMUP) -ForegroundColor DarkGray
    Start-Sleep -Seconds $WV_WARMUP

    $pm = Start-PmCapture 'chrome.exe' $csv $WV_CAPTURE
    $pm.WaitForExit(($WV_CAPTURE + 20) * 1000) | Out-Null
    if (-not $pm.HasExited) { try { $pm.Kill() } catch {} }

    try { if (-not $cProc.HasExited) { $cProc.Kill() } } catch {}
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    Remove-Item $udDir -Recurse -Force -ErrorAction SilentlyContinue

    $wvStats[$key] = Read-PmCsv $csv
    $s = $wvStats[$key]
    if ($s) {
        Write-Host ("  fps={0}  1%low={1}  p99={2}ms  gpu={3}ms  frames={4}" -f `
            $s.AvgFPS, $s.FPS1Low, $s.P99, $s.AvgGPUMs, $s.Frames) -ForegroundColor Green
    } else { Write-Host "  WARN: no frame data" -ForegroundColor Yellow }
}

Stop-BenchServer $server

# ===============================================================================
# Build JSON
# ===============================================================================
function ConvertTo-StatHash { param($s)
    if ($null -eq $s) { return @{ error = 'no_data' } }
    [ordered]@{
        frames=$s.Frames; avg_fps=$s.AvgFPS; fps_1pct_low=$s.FPS1Low; fps_01pct_low=$s.FPS01Low
        avg_frame_ms=$s.AvgMs; p50_ms=$s.P50; p90_ms=$s.P90; p99_ms=$s.P99
        p999_ms=$s.P999; worst_ms=$s.Worst; jank_pct=$s.JankPct
        avg_gpu_ms=$s.AvgGPUMs; avg_latency_ms=$s.AvgLatMs; avg_cpu_ms=$s.AvgCPUMs
        runtime=$s.Runtime; present_mode=$s.PresentMode
    }
}

$elJson  = [ordered]@{}
foreach ($k in $elStats.Keys)  { $elJson[$k]  = ConvertTo-StatHash $elStats[$k] }
$wvJson  = [ordered]@{}
foreach ($k in $wvStats.Keys)  { $wvJson[$k]  = ConvertTo-StatHash $wvStats[$k] }

$allJson = [ordered]@{
    suite        = 'PresentMon GPU Benchmark Suite v3'
    tool         = 'Intel PresentMon 2.4.1'
    timestamp    = (Get-Date -Format 'o')
    elpian       = $elJson
    webview      = $wvJson
}
$allJson | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $REPORTS 'presentmon_results.json') -Encoding utf8

# ===============================================================================
# Report helpers
# ===============================================================================
function Get-AggStat {
    param([System.Collections.Specialized.OrderedDictionary]$dict, [string]$prop)
    [array]$vals = @($dict.Values | Where-Object { $null -ne $_ -and $_.Frames -gt 5 } |
                     ForEach-Object { $_.$prop } | Where-Object { $null -ne $_ })
    if ($vals.Count -eq 0) { return 'n/a' }
    [math]::Round(($vals | Measure-Object -Average).Average, 1)
}

function Write-ScenarioMdRows {
    param([System.Collections.Specialized.OrderedDictionary]$dict)
    $out = ''
    foreach ($k in $dict.Keys) {
        $s = $dict[$k]
        if (-not $s -or $s.Frames -lt 3) {
            $out += "| $k | n/a | n/a | n/a | n/a | n/a | n/a | n/a |`n"
        } else {
            $out += "| $k | $(FmtVal $s.AvgFPS) | $(FmtVal $s.FPS1Low) | $(FmtVal $s.P99 'ms') | $(FmtVal $s.JankPct '%') | $(FmtVal $s.AvgGPUMs 'ms') | $(FmtVal $s.AvgLatMs 'ms') | $(FmtVal $s.Frames) |`n"
        }
    }
    $out
}

function Write-ScenarioMdDetail {
    param([System.Collections.Specialized.OrderedDictionary]$dict)
    $out = ''
    foreach ($k in $dict.Keys) {
        $s = $dict[$k]
        if (-not $s) { $out += "`n### $k`n*No frame data captured.*`n"; continue }
        $out += @"

### $k
| Metric | Value |
|---|---|
| Avg FPS | $(FmtVal $s.AvgFPS ' fps') |
| 1% Low FPS | $(FmtVal $s.FPS1Low ' fps') |
| 0.1% Low FPS | $(FmtVal $s.FPS01Low ' fps') |
| Avg Frame Time | $(FmtVal $s.AvgMs 'ms') |
| P50 | $(FmtVal $s.P50 'ms') |
| P90 | $(FmtVal $s.P90 'ms') |
| P99 | $(FmtVal $s.P99 'ms') |
| P99.9 | $(FmtVal $s.P999 'ms') |
| Worst Frame | $(FmtVal $s.Worst 'ms') |
| Jank Rate | $(FmtVal $s.JankPct '%') |
| Avg GPU Busy | $(FmtVal $s.AvgGPUMs 'ms') |
| Avg Display Latency | $(FmtVal $s.AvgLatMs 'ms') |
| Frames | $(FmtVal $s.Frames) |
| Runtime | $(FmtVal $s.Runtime) |
| Present Mode | $(FmtVal $s.PresentMode) |

"@
    }
    $out
}

# ===============================================================================
# Elpian report
# ===============================================================================
$elSummaryRows = Write-ScenarioMdRows  $elStats
$elDetailRows  = Write-ScenarioMdDetail $elStats

$elAvgFPS  = Get-AggStat $elStats 'AvgFPS'
$elAvgP99  = Get-AggStat $elStats 'P99'
$elAvgJank = Get-AggStat $elStats 'JankPct'
$elAvgGPU  = Get-AggStat $elStats 'AvgGPUMs'
$elAvgLat  = Get-AggStat $elStats 'AvgLatMs'

$elpianMd = @"
# Elpian Windows -- PresentMon Real GPU Report
**Tool:** Intel PresentMon 2.4.1 (ETW kernel-level capture)
**Target:** ``elpian_ui_example.exe`` -- Flutter Windows release build
**Scenarios:** 5 real screens with navigation, scrolling, and content interaction
**Date:** $(Get-Date -Format 'yyyy-MM-dd')

---

## Aggregate (all 5 scenarios)
| Metric | Value |
|---|---|
| Avg FPS | $elAvgFPS fps |
| Avg P99 Frame Time | $elAvgP99 ms |
| Avg Jank Rate | $elAvgJank % |
| Avg GPU Busy | $elAvgGPU ms |
| Avg Display Latency | $elAvgLat ms |

---

## Per-Scenario Summary
| Scenario | Avg FPS | 1% Low | P99 | Jank | GPU Avg | Latency | Frames |
|---|---|---|---|---|---|---|---|
$elSummaryRows
---

## Per-Scenario Detail
$elDetailRows
---
*Intel PresentMon 2.4.1 | $(Get-Date -Format 'yyyy-MM-dd HH:mm')*
"@
$elpianMd | Set-Content (Join-Path $REPORTS 'elpian_presentmon_report.md') -Encoding utf8

# ===============================================================================
# WebView report
# ===============================================================================
$wvSummaryRows = Write-ScenarioMdRows  $wvStats
$wvDetailRows  = Write-ScenarioMdDetail $wvStats

$webviewMd = @"
# WebView (Chrome) -- PresentMon Real GPU Report
**Tool:** Intel PresentMon 2.4.1 (ETW kernel-level capture)
**Target:** ``chrome.exe`` rendering benchmark HTML pages
**Capture:** ${WV_CAPTURE}s per scenario after ${WV_WARMUP}s warmup
**Date:** $(Get-Date -Format 'yyyy-MM-dd')

---

## Per-Scenario Summary
| Scenario | Avg FPS | 1% Low | P99 | Jank | GPU Avg | Latency | Frames |
|---|---|---|---|---|---|---|---|
$wvSummaryRows
---

## Per-Scenario Detail
$wvDetailRows
---
*Intel PresentMon 2.4.1 | $(Get-Date -Format 'yyyy-MM-dd HH:mm')*
"@
$webviewMd | Set-Content (Join-Path $REPORTS 'webview_presentmon_report.md') -Encoding utf8

# ===============================================================================
# Comparison report
# ===============================================================================
$wvAvgFPS  = Get-AggStat $wvStats 'AvgFPS'
$wvAvg1Low = Get-AggStat $wvStats 'FPS1Low'
$wvAvgP99  = Get-AggStat $wvStats 'P99'
$wvAvgJank = Get-AggStat $wvStats 'JankPct'
$wvAvgGPU  = Get-AggStat $wvStats 'AvgGPUMs'
$wvAvgLat  = Get-AggStat $wvStats 'AvgLatMs'
$elAvg1Low = Get-AggStat $elStats 'FPS1Low'

$elPerScenario = ''
foreach ($k in $elStats.Keys) {
    $s = $elStats[$k]
    if (-not $s -or $s.Frames -lt 3) { $elPerScenario += "| $k | n/a | n/a | n/a | n/a |`n"; continue }
    $elPerScenario += "| $k | $(FmtVal $s.AvgFPS ' fps') | $(FmtVal $s.FPS1Low ' fps') | $(FmtVal $s.P99 'ms') | $(FmtVal $s.AvgGPUMs 'ms') |`n"
}
$wvPerScenario = ''
foreach ($k in $wvStats.Keys) {
    $s = $wvStats[$k]
    if (-not $s -or $s.Frames -lt 3) { $wvPerScenario += "| $k | n/a | n/a | n/a | n/a |`n"; continue }
    $wvPerScenario += "| $k | $(FmtVal $s.AvgFPS ' fps') | $(FmtVal $s.FPS1Low ' fps') | $(FmtVal $s.P99 'ms') | $(FmtVal $s.AvgGPUMs 'ms') |`n"
}

# Best/worst helpers
function BestWorst {
    param([System.Collections.Specialized.OrderedDictionary]$dict, [string]$prop, [bool]$bestIsHigh)
    [array]$good = @($dict.Values | Where-Object { $null -ne $_ -and $_.Frames -gt 5 -and $null -ne $_.$prop })
    if ($good.Count -eq 0) { return @('n/a','n/a') }
    [array]$sorted = @($good | Sort-Object { $_.$prop })
    $lo = $sorted[0].$prop
    $hi = $sorted[-1].$prop
    if ($bestIsHigh) { return @("$hi", "$lo") } else { return @("$lo", "$hi") }
}
[array]$elP99BW  = BestWorst $elStats 'P99'  $false
[array]$wvP99BW  = BestWorst $wvStats 'P99'  $false
[array]$elWoBW   = BestWorst $elStats 'Worst' $false
[array]$wvWoBW   = BestWorst $wvStats 'Worst' $false

$compMd = @"
# Elpian vs WebView -- PresentMon Real GPU Comparison
**Tool:** Intel PresentMon 2.4.1 (ETW driver-level capture)
**Platform:** Windows 11 Enterprise, real GPU hardware
**Elpian:** 5 scenarios (navigation, scroll, tab-switch, large JSON page)
**WebView:** 8 scenarios (Chrome rendering benchmark HTML pages)
**Date:** $(Get-Date -Format 'yyyy-MM-dd')

> All metrics come from hardware-level ETW swap-chain events.
> Values are averages across all scenarios within each platform.

---

## Head-to-Head (average across all scenarios)
| Metric | Elpian (Flutter) | WebView (Chrome) |
|---|---|---|
| Average FPS | $elAvgFPS fps | $wvAvgFPS fps |
| 1% Low FPS | $elAvg1Low fps | $wvAvg1Low fps |
| P99 Frame Time | $elAvgP99 ms | $wvAvgP99 ms |
| Jank Rate (>16.67ms) | $elAvgJank % | $wvAvgJank % |
| Avg GPU Busy | $elAvgGPU ms | $wvAvgGPU ms |
| Avg Display Latency | $elAvgLat ms | $wvAvgLat ms |

---

## P99 & Worst-Frame Range
| Platform | Best P99 | Worst P99 | Best Worst | Worst Worst |
|---|---|---|---|---|
| Elpian | $($elP99BW[0]) ms | $($elP99BW[1]) ms | $($elWoBW[0]) ms | $($elWoBW[1]) ms |
| WebView | $($wvP99BW[0]) ms | $($wvP99BW[1]) ms | $($wvWoBW[0]) ms | $($wvWoBW[1]) ms |

---

## Elpian -- Per-Scenario
| Scenario | Avg FPS | 1% Low | P99 | GPU Avg |
|---|---|---|---|---|
$elPerScenario
## WebView -- Per-Scenario
| Scenario | Avg FPS | 1% Low | P99 | GPU Avg |
|---|---|---|---|---|
$wvPerScenario
---

## Architecture Notes
- **Elpian** renders via Flutter Skia/Impeller -> ANGLE -> D3D11 -> DWM
- **Chrome** renders via Blink/Skia -> ANGLE -> D3D11 -> DWM (same downstream pipeline)
- Elpian redraws are demand-driven; benchmark drives them via mouse movement + navigation
- Flutter uses ``Composed: Copy with GPU GDI``; Chrome uses ``Composed: Flip``
- Elpian benchmarked across 5 distinct demo screens with real navigation and interaction
- WebView benchmarked across 8 HTML pages with CSS animation, canvas, and JS workloads

---
*Intel PresentMon 2.4.1 GPU Benchmark Suite v3 | $(Get-Date -Format 'yyyy-MM-dd HH:mm')*
"@
$compMd | Set-Content (Join-Path $REPORTS 'presentmon_comparison_report.md') -Encoding utf8

# ===============================================================================
# Console summary
# ===============================================================================
Write-Host "`n+=== Results Summary ===+" -ForegroundColor Magenta
Write-Host "  --- Elpian ---" -ForegroundColor Cyan
foreach ($k in $elStats.Keys) {
    $s = $elStats[$k]
    if ($s) { Write-Host ("  {0,-28} fps={1,-7} 1%low={2,-7} p99={3}ms" -f $k,$s.AvgFPS,$s.FPS1Low,$s.P99) -ForegroundColor White }
    else    { Write-Host ("  {0,-28} NO DATA" -f $k) -ForegroundColor Yellow }
}
Write-Host "  --- WebView ---" -ForegroundColor Cyan
foreach ($k in $wvStats.Keys) {
    $s = $wvStats[$k]
    if ($s) { Write-Host ("  {0,-36} fps={1,-7} 1%low={2,-7} p99={3}ms" -f $k,$s.AvgFPS,$s.FPS1Low,$s.P99) -ForegroundColor White }
    else    { Write-Host ("  {0,-36} NO DATA" -f $k) -ForegroundColor Yellow }
}
Write-Host ("`n[OK] Reports -> " + $REPORTS) -ForegroundColor Green
