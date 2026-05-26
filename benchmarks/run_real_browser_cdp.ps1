#Requires -Version 5.1
# Real-Browser WebView Benchmark Runner (CDP v8)
# Chrome runs visible (GPU on, real V-Sync) - no --headless, no --disable-gpu.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CHROME   = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$WEBVIEW  = Join-Path $PSScriptRoot 'webview'
$REPORT   = Join-Path $PSScriptRoot 'reports'
$CDP_PORT = 9226
New-Item -ItemType Directory -Force $REPORT | Out-Null

# --- HTTP server (Runspace-based) -------------------------------------------
function Start-BenchServer {
    param([string]$Root, [int]$Port = 8769)
    $hl = [System.Net.HttpListener]::new()
    $hl.Prefixes.Add("http://localhost:$Port/")
    $hl.Prefixes.Add("http://127.0.0.1:$Port/")
    $hl.Start()
    Write-Host "  [server] http://localhost:$Port/" -ForegroundColor DarkGray
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('hl',   $hl)
    $rs.SessionStateProxy.SetVariable('root', $Root)
    $srvPs = [System.Management.Automation.PowerShell]::Create()
    $srvPs.Runspace = $rs
    $null = $srvPs.AddScript({
        while ($hl.IsListening) {
            try {
                $ctx  = $hl.GetContext()
                $path = $ctx.Request.Url.LocalPath.TrimStart('/')
                if (-not $path) { $path = 'index.html' }
                $file = Join-Path $root $path
                if (Test-Path $file) {
                    $bytes = [System.IO.File]::ReadAllBytes($file)
                    $ctx.Response.ContentType = 'text/html; charset=utf-8'
                    $ctx.Response.ContentLength64 = $bytes.Length
                    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else { $ctx.Response.StatusCode = 404 }
            } catch {}
            try { $ctx.Response.Close() } catch {}
        }
    })
    $null = $srvPs.BeginInvoke()
    return [PSCustomObject]@{ Listener = $hl; PS = $srvPs; RS = $rs }
}

# --- CDP helpers -------------------------------------------------------------
$script:RecvTask = $null
$script:RecvBuf  = [byte[]]::new(8388608)

function Read-OneMsg {
    param($Ws, [int]$TimeoutMs = 5000)
    if ($null -eq $script:RecvTask) {
        $seg = [ArraySegment[byte]]::new($script:RecvBuf)
        $script:RecvTask = $Ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
    }
    if (-not $script:RecvTask.Wait([System.TimeSpan]::FromMilliseconds($TimeoutMs))) { return $null }
    $task = $script:RecvTask; $script:RecvTask = $null
    if ($task.IsFaulted -or $task.IsCanceled) { return $null }
    $r = $task.Result
    if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
    $ms = [System.IO.MemoryStream]::new()
    $ms.Write($script:RecvBuf, 0, $r.Count)
    while (-not $r.EndOfMessage) {
        $seg2 = [ArraySegment[byte]]::new($script:RecvBuf)
        $t2   = $Ws.ReceiveAsync($seg2, [System.Threading.CancellationToken]::None)
        $t2.Wait([System.TimeSpan]::FromSeconds(30)) | Out-Null
        if ($t2.IsFaulted) { return $null }
        $r = $t2.Result
        $ms.Write($script:RecvBuf, 0, $r.Count)
    }
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Send-CDPMsg {
    param($Ws, [hashtable]$Obj)
    $json  = $Obj | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Ws.SendAsync([ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text, $true,
        [System.Threading.CancellationToken]::None).Wait(
        [System.TimeSpan]::FromSeconds(10)) | Out-Null
}

function Wait-CDPResponse {
    param($Ws, [int]$Id, [int]$TimeoutMs = 15000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $rem  = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if ($rem -le 0) { break }
        $json = Read-OneMsg -Ws $Ws -TimeoutMs ([math]::Min($rem, 2000))
        if (-not $json) { continue }
        try {
            $msg = $json | ConvertFrom-Json
            if ($msg.PSObject.Properties.Name -contains 'id' -and $msg.id -eq $Id) { return $msg }
        } catch {}
    }
    return $null
}

function Drain-Events {
    param($Ws, [int]$DrainMs = 500)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($DrainMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $rem  = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if ($rem -le 0) { break }
        $json = Read-OneMsg -Ws $Ws -TimeoutMs ([math]::Min($rem, 200))
        if (-not $json) { break }
    }
}

function Get-BestFps { param($r)
    foreach ($fp in @('fps','raf_fps_avg','scroll_fps','build_throughput_per_sec','build_fps_equiv')) {
        if ($r.PSObject.Properties.Name -contains $fp -and $null -ne $r.$fp) { return $r.$fp }
    }
    return 'na'
}

function Get-BestAvg { param($r)
    foreach ($ap in @('avg_frame_ms','build_avg_ms','raf_avg_frame_interval_ms','click_avg_ms','anim_frame_avg_ms')) {
        if ($r.PSObject.Properties.Name -contains $ap -and $null -ne $r.$ap) { return $r.$ap }
    }
    return 'na'
}

# --- Main -------------------------------------------------------------------
Write-Host "`n+=== Real-Browser WebView Benchmark Runner (CDP v8) ===+" -ForegroundColor Magenta
Write-Host "  Mode: GPU-accelerated Chrome (visible window, V-Sync active)" -ForegroundColor DarkGray

$server = Start-BenchServer -Root $WEBVIEW -Port 8769
Start-Sleep -Milliseconds 400
try {
    $ping = Invoke-WebRequest 'http://127.0.0.1:8769/01_basic_rendering.html' -UseBasicParsing -TimeoutSec 3 -EA Stop
    Write-Host ("  [server] OK (HTTP " + $ping.StatusCode + ", " + $ping.RawContentLength + " bytes)") -ForegroundColor DarkGray
} catch {
    Write-Host ("  [server] WARN: " + $_.Exception.Message) -ForegroundColor Yellow
}

$udDir = Join-Path $env:TEMP ('chrome_real_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $udDir | Out-Null

# Real Chrome - no --headless, no --disable-gpu
$chromeArgs = @(
    '--no-sandbox', '--no-proxy-server', '--disable-dev-shm-usage',
    '--enable-precise-memory-info', '--window-size=1280,900',
    ("--remote-debugging-port=" + $CDP_PORT),
    ("--user-data-dir=" + $udDir),
    'about:blank'
)

Write-Host ("  [cdp] Launching real Chrome (GPU on, port " + $CDP_PORT + ")...") -ForegroundColor DarkGray
$chromeProc = Start-Process -FilePath $CHROME -ArgumentList $chromeArgs -PassThru -NoNewWindow

$allResults = [ordered]@{}
try {
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        try { $null = Invoke-RestMethod ("http://localhost:" + $CDP_PORT + "/json/version") -EA Stop; $ready = $true; break } catch {}
    }
    if (-not $ready) { throw "Chrome not ready within 30s" }

    $ver = Invoke-RestMethod ("http://localhost:" + $CDP_PORT + "/json/version")
    $tab = (Invoke-RestMethod ("http://localhost:" + $CDP_PORT + "/json/list")) |
           Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    if (-not $tab) { throw "No page target" }
    Write-Host ("  [cdp] " + $ver.Browser + "  tab=" + $tab.id.Substring(0,8) + "...") -ForegroundColor DarkGray

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
    $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl,
        [System.Threading.CancellationToken]::None).Wait(
        [System.TimeSpan]::FromSeconds(10)) | Out-Null
    Write-Host ("  [cdp] WS=" + $ws.State) -ForegroundColor DarkGray

    $msgId = 1
    Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Page.enable';    params=@{} }
    $r = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 8000
    Write-Host ("  [cdp] Page.enable:    " + $(if ($r) { 'OK' } else { 'TIMEOUT' })) -ForegroundColor DarkGray
    $msgId++

    Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Runtime.enable'; params=@{} }
    $r = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 8000
    Write-Host ("  [cdp] Runtime.enable: " + $(if ($r) { 'OK' } else { 'TIMEOUT' })) -ForegroundColor DarkGray
    $msgId++

    Drain-Events -Ws $ws -DrainMs 800

    # Scenario list with per-page wait times (WV07 runs 5s rAF loop)
    $scenarios = [ordered]@{
        'WV01_BasicRendering'            = @{ url='http://localhost:8769/01_basic_rendering.html';        wait=10 }
        'WV02_CSSAnimations'             = @{ url='http://localhost:8769/02_css_animations.html';         wait=10 }
        'WV03_ComplexLayout'             = @{ url='http://localhost:8769/03_complex_layout.html';         wait=10 }
        'WV04_CanvasDrawing'             = @{ url='http://localhost:8769/04_canvas_drawing.html';         wait=10 }
        'WV05_ListScroll'                = @{ url='http://localhost:8769/05_list_scroll.html';            wait=10 }
        'WV06_ComplexDashboard'          = @{ url='http://localhost:8769/06_complex_dashboard.html';      wait=10 }
        'WV07_SmoothAnimations'          = @{ url='http://localhost:8769/07_smooth_animations.html';      wait=14 }
        'WV08_InteractiveResponsiveness' = @{ url='http://localhost:8769/08_interactive_responsiveness.html'; wait=12 }
    }

    foreach ($scenKey in $scenarios.Keys) {
        $cfg     = $scenarios[$scenKey]
        $url     = $cfg.url
        $waitSec = $cfg.wait
        Write-Host ("  [bench] " + $scenKey) -ForegroundColor Cyan

        Drain-Events -Ws $ws -DrainMs 400

        # Bring tab to front (required for LCP/paint timing in real browser)
        Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Page.bringToFront'; params=@{} }
        Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 3000 | Out-Null
        $msgId++

        Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Page.navigate'; params=@{ url=$url } }
        $navResp = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 12000
        $msgId++

        if ($null -eq $navResp) {
            Write-Host ("    TIMEOUT: navigation  WS=" + $ws.State) -ForegroundColor Red
            $allResults[$scenKey] = @{ error='nav_timeout' }
            continue
        }

        $errTxt = if ($navResp.result.PSObject.Properties.Name -contains 'errorText') { $navResp.result.errorText } else { '' }
        Write-Host ("    navigated" + $(if ($errTxt) { " ERR=$errTxt" } else { '' }) + ", waiting " + $waitSec + "s...") -ForegroundColor DarkGray

        $waitUntil = [DateTime]::UtcNow.AddSeconds($waitSec)
        while ([DateTime]::UtcNow -lt $waitUntil) {
            $rem = [int](($waitUntil - [DateTime]::UtcNow).TotalMilliseconds)
            if ($rem -le 0) { break }
            $null = Read-OneMsg -Ws $ws -TimeoutMs ([math]::Min($rem, 600))
        }

        $expr = '(function(){ var e=document.getElementById("results"); return e ? e.textContent : "NO_ELEMENT"; })()'
        Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Runtime.evaluate'; params=@{ expression=$expr; returnByValue=$true; timeout=12000 } }
        $evalResp = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 18000
        $msgId++

        if ($null -eq $evalResp) {
            Write-Host ("    TIMEOUT: eval  WS=" + $ws.State) -ForegroundColor Red
            $allResults[$scenKey] = @{ error='eval_timeout' }
            continue
        }

        $text = $evalResp.result.result.value
        if (-not $text -or $text -eq 'NO_ELEMENT' -or $text -like 'RUNNING*') {
            $preview = if ($text) { $text.Substring(0, [math]::Min(80,$text.Length)) } else { '(null)' }
            Write-Host ("    FAIL: result=" + $preview) -ForegroundColor Red
            $allResults[$scenKey] = @{ error=("result_state:" + $preview) }
            continue
        }

        try {
            $parsed = $text | ConvertFrom-Json
            $fps = Get-BestFps $parsed
            $avg = Get-BestAvg $parsed
            Write-Host ("    OK  fps=" + $fps + "  avg=" + $avg + "ms") -ForegroundColor Green
            $allResults[$scenKey] = $parsed
        } catch {
            $preview = $text.Substring(0, [math]::Min(120,$text.Length))
            Write-Host ("    WARN: JSON parse error. Raw: " + $preview) -ForegroundColor Yellow
            $allResults[$scenKey] = @{ error='json_parse'; raw=$preview }
        }
    }

    try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, '',
        [System.Threading.CancellationToken]::None).Wait(
        [System.TimeSpan]::FromSeconds(3)) } catch {}

} finally {
    try { if (-not $chromeProc.HasExited) { $chromeProc.Kill() } } catch {}
    Start-Sleep -Milliseconds 600
    Remove-Item $udDir -Recurse -Force -ErrorAction SilentlyContinue
    try { $server.Listener.Stop(); $server.Listener.Close() } catch {}
    try { $server.PS.Stop();       $server.PS.Dispose()    } catch {}
    try { $server.RS.Close();      $server.RS.Dispose()    } catch {}
    Write-Host "  [server] Stopped." -ForegroundColor DarkGray
}

$out = @{
    suite     = 'WebView Real-Browser Benchmark Suite (CDP v8, GPU-on)'
    timestamp = (Get-Date -Format 'o')
    results   = $allResults
}
$outPath = Join-Path $REPORT 'webview_real_results.json'
$out | ConvertTo-Json -Depth 10 | Set-Content $outPath -Encoding utf8
Write-Host ("`n[OK] -> " + $outPath) -ForegroundColor Green

Write-Host "`n+=== Real-Browser Benchmark Summary ===+" -ForegroundColor Cyan
foreach ($k in $allResults.Keys) {
    $rv = $allResults[$k]
    if ($rv.PSObject.Properties.Name -contains 'error') {
        Write-Host ("  " + $k.PadRight(32) + " ERROR: " + $rv.error) -ForegroundColor Red
    } else {
        $fps = Get-BestFps $rv
        $avg = Get-BestAvg $rv
        Write-Host ("  " + $k.PadRight(32) + " fps=" + $fps + "  avg=" + $avg + "ms") -ForegroundColor White
    }
}
