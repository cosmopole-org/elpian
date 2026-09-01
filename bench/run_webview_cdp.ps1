#Requires -Version 5.1
# WebView HTML Benchmark Runner using Chrome DevTools Protocol (CDP) v7
# Fix: use Task.Wait(TimeSpan) -- AsyncWaitHandle.WaitOne(int) blocks forever in PS 5.1.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CHROME   = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$WEBVIEW  = Join-Path $PSScriptRoot 'webview'
$REPORT   = Join-Path $PSScriptRoot 'reports'
$CDP_PORT = 9225
New-Item -ItemType Directory -Force $REPORT | Out-Null

function Start-BenchServer {
    param([string]$Root, [int]$Port = 8768)
    # Create listener in the calling scope so we can stop it from here
    $hl = [System.Net.HttpListener]::new()
    $hl.Prefixes.Add("http://localhost:$Port/")
    $hl.Prefixes.Add("http://127.0.0.1:$Port/")
    $hl.Start()
    Write-Host "  [server] http://localhost:$Port/ | http://127.0.0.1:$Port/" -ForegroundColor DarkGray

    # Run request loop in a Runspace — SetVariable passes references explicitly
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
                } else {
                    $ctx.Response.StatusCode = 404
                }
            } catch {}
            try { $ctx.Response.Close() } catch {}
        }
    })
    $null = $srvPs.BeginInvoke()

    # Return a small object with Stop() that cleans up everything
    return [PSCustomObject]@{
        Listener = $hl
        PS       = $srvPs
        RS       = $rs
    }
}

# Pending-task receive state (one ReceiveAsync in flight, never cancelled)
$script:RecvTask = $null
$script:RecvBuf  = [byte[]]::new(4194304)

function Read-OneMsg {
    param($Ws, [int]$TimeoutMs = 5000)
    if ($null -eq $script:RecvTask) {
        $seg = [ArraySegment[byte]]::new($script:RecvBuf)
        $script:RecvTask = $Ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
    }
    # Task.Wait(TimeSpan) is the only reliable timeout in PS 5.1
    $ts = [System.TimeSpan]::FromMilliseconds($TimeoutMs)
    if (-not $script:RecvTask.Wait($ts)) { return $null }

    $task = $script:RecvTask; $script:RecvTask = $null
    if ($task.IsFaulted -or $task.IsCanceled) { return $null }
    $r = $task.Result
    if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }

    $ms = [System.IO.MemoryStream]::new()
    $ms.Write($script:RecvBuf, 0, $r.Count)
    while (-not $r.EndOfMessage) {
        $seg2 = [ArraySegment[byte]]::new($script:RecvBuf)
        $t2 = $Ws.ReceiveAsync($seg2, [System.Threading.CancellationToken]::None)
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
        $rem = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if ($rem -le 0) { break }
        $json = Read-OneMsg -Ws $Ws -TimeoutMs ([math]::Min($rem, 2000))
        if (-not $json) { continue }
        try {
            $msg = $json | ConvertFrom-Json
            # Use PSObject check to avoid strict-mode throwing on missing 'id'
            if ($msg.PSObject.Properties.Name -contains 'id' -and $msg.id -eq $Id) {
                return $msg
            }
        } catch {}
    }
    return $null
}

function Skip-Events {
    param($Ws, [int]$DrainMs = 400)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($DrainMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $rem = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if ($rem -le 0) { break }
        $json = Read-OneMsg -Ws $Ws -TimeoutMs ([math]::Min($rem, 200))
        if (-not $json) { break }
    }
}

# --- MAIN ---------------------------------------------------------------------
Write-Host "`n+=== WebView HTML Benchmark Runner (CDP v7) ===+" -ForegroundColor Magenta

$server = Start-BenchServer -Root $WEBVIEW -Port 8768

# Verify HTTP server is accessible before starting Chrome
Start-Sleep -Milliseconds 300
try {
    $testResp = Invoke-WebRequest "http://127.0.0.1:8768/01_basic_rendering.html" -UseBasicParsing -TimeoutSec 3 -EA Stop
    Write-Host "  [server] OK (HTTP $($testResp.StatusCode), $($testResp.RawContentLength) bytes)" -ForegroundColor DarkGray
} catch {
    Write-Host "  [server] WARN: self-test failed - $_" -ForegroundColor Yellow
}

$udDir = Join-Path $env:TEMP ('chrome_cdp_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $udDir | Out-Null

$chromeArgs = @(
    '--headless', '--no-sandbox', '--disable-gpu', '--no-proxy-server',
    '--disable-dev-shm-usage', '--enable-precise-memory-info',
    "--remote-debugging-port=$CDP_PORT",
    "--user-data-dir=$udDir", 'about:blank'
)

Write-Host "  [cdp] Starting Chrome on port $CDP_PORT..." -ForegroundColor DarkGray
$chromeProc = Start-Process -FilePath $CHROME -ArgumentList $chromeArgs -PassThru -NoNewWindow

$allResults = [ordered]@{}
try {
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        try { $null = Invoke-RestMethod "http://localhost:$CDP_PORT/json/version" -EA Stop; $ready = $true; break } catch {}
    }
    if (-not $ready) { throw "Chrome not ready" }

    $ver  = Invoke-RestMethod "http://localhost:$CDP_PORT/json/version"
    $tab  = (Invoke-RestMethod "http://localhost:$CDP_PORT/json/list") |
            Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    if (-not $tab) { throw "No page target" }
    Write-Host "  [cdp] $($ver.Browser)  tab=$($tab.id.Substring(0,8))..." -ForegroundColor DarkGray

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
    $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl,
        [System.Threading.CancellationToken]::None).Wait(
        [System.TimeSpan]::FromSeconds(10)) | Out-Null
    Write-Host "  [cdp] WS=$($ws.State)" -ForegroundColor DarkGray

    $msgId = 1

    Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Page.enable';    params=@{} }
    $r = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 8000
    Write-Host "  [cdp] Page.enable:    $(if ($r) { 'OK' } else { 'TIMEOUT' })" -ForegroundColor DarkGray
    $msgId++

    Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Runtime.enable'; params=@{} }
    $r = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 8000
    Write-Host "  [cdp] Runtime.enable: $(if ($r) { 'OK' } else { 'TIMEOUT' })" -ForegroundColor DarkGray
    $msgId++

    Skip-Events -Ws $ws -DrainMs 600

    $pages = [ordered]@{
        'WV01_BasicRendering' = 'http://localhost:8768/01_basic_rendering.html'
        'WV02_CSSAnimations'  = 'http://localhost:8768/02_css_animations.html'
        'WV03_ComplexLayout'  = 'http://localhost:8768/03_complex_layout.html'
        'WV04_CanvasDrawing'  = 'http://localhost:8768/04_canvas_drawing.html'
        'WV05_ListScroll'     = 'http://localhost:8768/05_list_scroll.html'
    }

    foreach ($scenario in $pages.Keys) {
        $url = $pages[$scenario]
        Write-Host "  [bench] $scenario" -ForegroundColor Cyan

        Skip-Events -Ws $ws -DrainMs 300

        Send-CDPMsg -Ws $ws -Obj @{ id=$msgId; method='Page.navigate'; params=@{ url=$url } }
        $navResp = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 10000
        $msgId++

        if ($null -eq $navResp) {
            Write-Host "    TIMEOUT: navigation  WS=$($ws.State)" -ForegroundColor Red
            $allResults[$scenario] = @{ error='nav_timeout' }
            continue
        }
        $errTxt = if ($navResp.result.PSObject.Properties.Name -contains 'errorText') { $navResp.result.errorText } else { '' }
        Write-Host "    navigated$(if ($errTxt) { " ERR=$errTxt" }), waiting 8s for JS..." -ForegroundColor DarkGray

        # Drain events during JS execution window
        $waitUntil = [DateTime]::UtcNow.AddSeconds(8)
        while ([DateTime]::UtcNow -lt $waitUntil) {
            $rem = [int](($waitUntil - [DateTime]::UtcNow).TotalMilliseconds)
            if ($rem -le 0) { break }
            $null = Read-OneMsg -Ws $ws -TimeoutMs ([math]::Min($rem, 500))
        }

        $expr = '(function(){ var e=document.getElementById("results"); return e ? e.textContent : "NO_ELEMENT"; })()'
        Send-CDPMsg -Ws $ws -Obj @{
            id=$msgId; method='Runtime.evaluate'
            params=@{ expression=$expr; returnByValue=$true; timeout=10000 }
        }
        $evalResp = Wait-CDPResponse -Ws $ws -Id $msgId -TimeoutMs 15000
        $msgId++

        if ($null -eq $evalResp) {
            Write-Host "    TIMEOUT: eval  WS=$($ws.State)" -ForegroundColor Red
            $allResults[$scenario] = @{ error='eval_timeout' }
            continue
        }

        $text = $evalResp.result.result.value
        if (-not $text -or $text -eq 'NO_ELEMENT' -or $text -eq 'RUNNING') {
            Write-Host "    FAIL: result='$text'" -ForegroundColor Red
            $allResults[$scenario] = @{ error="result_state:$text" }
            continue
        }

        try {
            $parsed = $text | ConvertFrom-Json
            $fps = if ($parsed.PSObject.Properties.Name -contains 'fps') { $parsed.fps } elseif ($parsed.PSObject.Properties.Name -contains 'scroll_fps') { $parsed.scroll_fps } elseif ($parsed.PSObject.Properties.Name -contains 'build_throughput_per_sec') { $parsed.build_throughput_per_sec } else { 'na' }
            $avg = if ($parsed.PSObject.Properties.Name -contains 'avg_frame_ms') { $parsed.avg_frame_ms } elseif ($parsed.PSObject.Properties.Name -contains 'build_avg_ms') { $parsed.build_avg_ms } elseif ($parsed.PSObject.Properties.Name -contains 'scroll_avg_ms') { $parsed.scroll_avg_ms } elseif ($parsed.PSObject.Properties.Name -contains 'anim_frame_avg_ms') { $parsed.anim_frame_avg_ms } else { 'na' }
            Write-Host "    OK  fps=$fps  avg=${avg}ms" -ForegroundColor Green
            $allResults[$scenario] = $parsed
        } catch {
            $preview = $text.Substring(0, [math]::Min(120, $text.Length))
            Write-Host "    WARN: JSON parse error. Raw: $preview" -ForegroundColor Yellow
            $allResults[$scenario] = @{ error='json_parse'; raw=$preview }
        }
    }

    try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, '',
        [System.Threading.CancellationToken]::None).Wait(
        [System.TimeSpan]::FromSeconds(3)) } catch {}

} finally {
    try { if (-not $chromeProc.HasExited) { $chromeProc.Kill() } } catch {}
    Start-Sleep -Milliseconds 500
    Remove-Item $udDir -Recurse -Force -ErrorAction SilentlyContinue
    try { $server.Listener.Stop(); $server.Listener.Close() } catch {}
    try { $server.PS.Stop(); $server.PS.Dispose() }  catch {}
    try { $server.RS.Close(); $server.RS.Dispose() } catch {}
    Write-Host "  [server] Stopped." -ForegroundColor DarkGray
}

$out = @{
    suite     = 'WebView Benchmark Suite (CDP v7)'
    timestamp = (Get-Date -Format 'o')
    results   = $allResults
}
$outPath = "$REPORT\webview_results.json"
$out | ConvertTo-Json -Depth 10 | Set-Content $outPath -Encoding utf8
Write-Host "`n[OK] -> $outPath" -ForegroundColor Green

Write-Host "`n+=== WebView Benchmark Summary ===+" -ForegroundColor Cyan
foreach ($key in $allResults.Keys) {
    $r = $allResults[$key]
    if ($r.PSObject.Properties.Name -contains 'error') {
        Write-Host ("  " + $key.PadRight(28) + " ERROR: " + $r.error) -ForegroundColor Red
    } else {
        $fps = if ($r.PSObject.Properties.Name -contains 'fps') { $r.fps } elseif ($r.PSObject.Properties.Name -contains 'scroll_fps') { $r.scroll_fps } elseif ($r.PSObject.Properties.Name -contains 'build_throughput_per_sec') { $r.build_throughput_per_sec } else { 'na' }
        $avg = if ($r.PSObject.Properties.Name -contains 'avg_frame_ms') { $r.avg_frame_ms } elseif ($r.PSObject.Properties.Name -contains 'build_avg_ms') { $r.build_avg_ms } elseif ($r.PSObject.Properties.Name -contains 'scroll_avg_ms') { $r.scroll_avg_ms } elseif ($r.PSObject.Properties.Name -contains 'anim_frame_avg_ms') { $r.anim_frame_avg_ms } else { 'na' }
        Write-Host ("  " + $key.PadRight(28) + " fps=$fps  avg=${avg}ms") -ForegroundColor White
    }
}
