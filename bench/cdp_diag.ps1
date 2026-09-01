#Requires -Version 5.1
# CDP diagnostic v4: test Wait(TimeSpan) vs AsyncWaitHandle.WaitOne(int) vs Task.Wait(int)
# with --no-proxy-server and Runtime.enable
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CHROME   = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$CDP_PORT = 9229
$SRV_PORT = 8772

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$SRV_PORT/")
$listener.Start()
$srvThread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
    while ($listener.IsListening) {
        try {
            $ctx = $listener.GetContext()
            $html = '<html><body><pre id="results">DONE</pre></body></html>'
            $b = [System.Text.Encoding]::UTF8.GetBytes($html)
            $ctx.Response.ContentType = 'text/html'
            $ctx.Response.ContentLength64 = $b.Length
            $ctx.Response.OutputStream.Write($b, 0, $b.Length)
        } catch {}
        try { $ctx.Response.Close() } catch {}
    }
})
$srvThread.IsBackground = $true
$srvThread.Start()
Write-Host "Server: http://localhost:$SRV_PORT/"

$udDir = Join-Path $env:TEMP ('cdp_diag4_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $udDir | Out-Null
$chromeProc = Start-Process $CHROME -ArgumentList @(
    '--headless','--no-sandbox','--disable-gpu','--no-proxy-server',
    "--remote-debugging-port=$CDP_PORT","--user-data-dir=$udDir",'about:blank'
) -PassThru -NoNewWindow

$recvBuf = [byte[]]::new(1048576)
$script:pendingTask = $null

# Three different wait implementations to test
function WaitTask-AsyncHandle([System.Threading.Tasks.Task]$t, [int]$ms) {
    return $t.AsyncWaitHandle.WaitOne($ms)
}
function WaitTask-TaskWaitInt([System.Threading.Tasks.Task]$t, [int]$ms) {
    return $t.Wait([int]$ms)
}
function WaitTask-TimeSpan([System.Threading.Tasks.Task]$t, [int]$ms) {
    return $t.Wait([System.TimeSpan]::FromMilliseconds($ms))
}

function RecvOne([int]$ms) {
    if ($null -eq $script:pendingTask) {
        $seg = [ArraySegment[byte]]::new($recvBuf)
        $script:pendingTask = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
    }
    # Use Task.Wait(TimeSpan) - most explicit form
    $ts  = [System.TimeSpan]::FromMilliseconds($ms)
    $got = $script:pendingTask.Wait($ts)
    if (-not $got) { return $null }
    $t = $script:pendingTask; $script:pendingTask = $null
    if ($t.IsFaulted) { return "(FAULT: $($t.Exception.InnerException.Message))" }
    $r = $t.Result
    if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return "(CLOSE)" }
    return [System.Text.Encoding]::UTF8.GetString($recvBuf, 0, $r.Count)
}

function Send([hashtable]$obj) {
    $j = $obj | ConvertTo-Json -Depth 5 -Compress
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    $t = $ws.SendAsync([ArraySegment[byte]]::new($b),
        [System.Net.WebSockets.WebSocketMessageType]::Text, $true,
        [System.Threading.CancellationToken]::None)
    $t.Wait([System.TimeSpan]::FromSeconds(5)) | Out-Null
    Write-Host "--> $j"
}

try {
    # Wait for Chrome
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        try { $null = Invoke-RestMethod "http://localhost:$CDP_PORT/json/version" -EA Stop; break } catch {}
    }
    $tab = (Invoke-RestMethod "http://localhost:$CDP_PORT/json/list") |
           Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    Write-Host "Tab: $($tab.id)"

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl,
        [System.Threading.CancellationToken]::None).Wait([System.TimeSpan]::FromSeconds(10)) | Out-Null
    Write-Host "WS: $($ws.State)"

    Send @{ id=1; method='Page.enable';    params=@{} }
    Send @{ id=2; method='Runtime.enable'; params=@{} }

    Write-Host "--- reading domain enable responses ---"
    $got1 = $false; $got2 = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not ($got1 -and $got2) -and ([DateTime]::UtcNow -lt $deadline)) {
        $t0 = [DateTime]::UtcNow
        $json = RecvOne 2000
        $elapsed = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
        if ($null -eq $json) {
            Write-Host "  (no msg in 2000ms, actually took ${elapsed}ms, WS=$($ws.State))"
            continue
        }
        Write-Host "<-- [${elapsed}ms] $($json.Substring(0, [math]::Min(120,$json.Length)))"
        $msg = $json | ConvertFrom-Json
        if ($msg.PSObject.Properties.Name -contains 'id') {
            if ($msg.id -eq 1) { $got1 = $true }
            if ($msg.id -eq 2) { $got2 = $true }
        }
    }
    Write-Host "--- enables: Page=$got1 Runtime=$got2 ---"

    Write-Host "--- quick drain (500ms) ---"
    $drain0 = [DateTime]::UtcNow
    $json = RecvOne 500
    $drainElapsed = [int]([DateTime]::UtcNow - $drain0).TotalMilliseconds
    Write-Host "  drain RecvOne(500) returned in ${drainElapsed}ms: $(if ($null -eq $json) { 'null' } else { $json.Substring(0,[math]::Min(80,$json.Length)) })"
    Write-Host "--- drain done ---"

    # Navigate
    Send @{ id=3; method='Page.navigate'; params=@{ url="http://127.0.0.1:$SRV_PORT/t.html" } }
    Write-Host "--- waiting for navigate response ---"
    $navDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $navDeadline) {
        $t0 = [DateTime]::UtcNow
        $json = RecvOne 3000
        $elapsed = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
        if ($null -eq $json) {
            Write-Host "  (no msg, ${elapsed}ms, WS=$($ws.State))"
            continue
        }
        Write-Host "<-- [${elapsed}ms] $($json.Substring(0, [math]::Min(150,$json.Length)))"
        $msg = $json | ConvertFrom-Json
        if ($msg.PSObject.Properties.Name -contains 'id' -and $msg.id -eq 3) {
            Write-Host "  ^^^ NAVIGATE RESPONSE RECEIVED!"
            break
        }
    }
    Write-Host "--- done ---"

} finally {
    try { if (-not $chromeProc.HasExited) { $chromeProc.Kill() } } catch {}
    Remove-Item $udDir -Recurse -Force -ErrorAction SilentlyContinue
    try { $listener.Stop() } catch {}
}
