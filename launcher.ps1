# WorkBuddy 启动动画 · 启动器
#
# 流程：全屏播动画并置顶 → 动画先跑 2.6s → 后台拉起 WorkBuddy（启动耗时藏在动画里）
#       → 动画播完（页面把标题改成 WB_READY）且程序窗口就绪 → 关掉动画，前置程序
#
# 便携：浏览器和 WorkBuddy 全部自动探测，换电脑不用改任何路径。
#       同目录 config.ini 可手动指定 AppPath= / BrowserPath=。

param(
    [string]$Browser = "",
    [string]$App = "",
    [string]$SplashPath = "",
    [string]$ProfileDir = "",
    [int]$AppStartDelayMs = 2600,
    [int]$DeepScanMs = 4500,
    [int]$MaxWaitMs = 30000,
    [switch]$DetectOnly
)

$ErrorActionPreference = 'SilentlyContinue'

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $PSCommandPath }
if (-not $root) { $root = (Get-Location).Path }
if (-not $SplashPath) { $SplashPath = Join-Path $root 'index.html' }
if (-not $ProfileDir) { $ProfileDir = Join-Path $env:TEMP 'WB_Splash_Profile' }

$cfgPath = Join-Path $root 'config.ini'

# ── 小工具 ────────────────────────────────────────────
$script:wf = $false
function Load-WinForms {
    if (-not $script:wf) { Add-Type -AssemblyName System.Windows.Forms; $script:wf = $true }
}
function Show-Info {
    param([string]$Text, [string]$Title = 'WorkBuddy 启动动画')
    Load-WinForms
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title)
}

function Read-Config {
    param([string]$Path)
    $h = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $h }
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $t = "$line".Trim()
        if (-not $t) { continue }
        if ($t.StartsWith('#') -or $t.StartsWith(';') -or $t.StartsWith('[')) { continue }
        $i = $t.IndexOf('=')
        if ($i -le 0) { continue }
        $k = $t.Substring(0, $i).Trim().ToLower()
        $v = $t.Substring($i + 1).Trim().Trim('"')
        if ($v) { $h[$k] = $v }
    }
    return $h
}

function Set-ConfigValue {
    param([string]$Path, [string]$Key, [string]$Value)
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8) }
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) { $lines[$i] = "$Key=$Value"; $done = $true }
    }
    if (-not $done) { $lines += "$Key=$Value" }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# ── 探测浏览器（Edge 几乎每台 Win10/11 都有，优先） ──
function Find-Browser {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    )
    foreach ($exe in @('msedge.exe', 'chrome.exe')) {
        foreach ($r in $roots) {
            $v = (Get-ItemProperty -LiteralPath "$r\$exe").'(default)'
            if ($v -and (Test-Path -LiteralPath $v)) { return $v }
        }
    }
    $cands = @(
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return ''
}

# ── 探测 WorkBuddy（运行实例 / App Paths / 卸载表 / 快捷方式 / 常见目录） ──
function Find-App {
    $cands = New-Object 'System.Collections.Generic.List[string]'

    $p = Get-Process WorkBuddy | Where-Object { $_.Path } | Select-Object -First 1
    if ($p) { $cands.Add($p.Path) }

    foreach ($r in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths')) {
        $v = (Get-ItemProperty -LiteralPath "$r\WorkBuddy.exe").'(default)'
        if ($v) { $cands.Add($v) }
    }

    foreach ($u in @(Get-ItemProperty `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', `
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', `
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            Where-Object { $_.DisplayName -like '*WorkBuddy*' })) {
        if ($u.InstallLocation) { $cands.Add((Join-Path $u.InstallLocation 'WorkBuddy.exe')) }
        if ($u.DisplayIcon) {
            $icon = (($u.DisplayIcon.Trim('"') -split ',')[0]).Trim('"')
            if ($icon -like '*.exe') {
                $cands.Add($icon)
                $cands.Add((Join-Path (Split-Path -Parent $icon) 'WorkBuddy.exe'))
            }
        }
    }

    $wsh = New-Object -ComObject WScript.Shell
    foreach ($r in @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'))) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($lnk in @(Get-ChildItem -LiteralPath $r -Filter '*.lnk' -Recurse)) {
            if ($lnk.BaseName -notlike '*WorkBuddy*') { continue }
            $t = $wsh.CreateShortcut($lnk.FullName).TargetPath
            if ($t) { $cands.Add($t) }
        }
    }

    foreach ($b in @($env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) {
        if (-not $b) { continue }
        $cands.Add((Join-Path $b 'WorkBuddy\WorkBuddy.exe'))
        $cands.Add((Join-Path $b 'Programs\WorkBuddy\WorkBuddy.exe'))
        $cands.Add((Join-Path $b 'WorkBuddy\bin\WorkBuddy.exe'))
    }

    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return ''
}

# ── 兜底：按盘符浅扫（深度 3，带时间预算） ──
function Find-AppDeep {
    param([int]$BudgetMs = 4500)
    $t0 = Get-Date
    $skip = @('Windows', '$Recycle.Bin', 'System Volume Information', 'ProgramData', 'Recovery', 'PerfLogs', 'node_modules')
    foreach ($drv in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        foreach ($d in @(Get-ChildItem -LiteralPath $drv.Root -Directory)) {
            if ($skip -contains $d.Name) { continue }
            if (((Get-Date) - $t0).TotalMilliseconds -gt $BudgetMs) { return '' }
            $hit = Get-ChildItem -LiteralPath $d.FullName -Filter 'WorkBuddy.exe' -Recurse -Depth 3 -File | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return ''
}

function Select-AppFile {
    Load-WinForms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = '找不到 WorkBuddy，请手动选择 WorkBuddy.exe'
    $dlg.Filter = 'WorkBuddy.exe|WorkBuddy.exe|可执行文件 (*.exe)|*.exe'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return ''
}

# ── 窗口相关 ──────────────────────────────────────────
$sig = @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
'@
Add-Type -MemberDefinition $sig -Name U32 -Namespace W32 | Out-Null

$SWP_NOSIZE_NOMOVE_SHOW = 0x0043
$TOPMOST   = [IntPtr](-1)
$NOTOPMOST = [IntPtr](-2)

function Find-Splash {
    param([string]$Tag, [int]$KnownPid = 0)
    if ($KnownPid) {
        $p = Get-Process -Id $KnownPid
        if ($p -and $p.MainWindowHandle -ne 0) { return $p }
    }
    $ids = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
             Where-Object { $_.CommandLine -like "*$Tag*" } |
             Select-Object -ExpandProperty ProcessId)
    foreach ($procId in $ids) {
        $p = Get-Process -Id $procId
        if ($p -and $p.MainWindowHandle -ne 0) { return $p }
    }
    return $null
}

function Get-AppWindow {
    $p = Get-Process WorkBuddy | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { return $p.MainWindowHandle }
    return [IntPtr]::Zero
}

function Pin-Splash {
    param($Proc)
    if ($Proc) {
        [W32.U32]::SetWindowPos($Proc.MainWindowHandle, $TOPMOST, 0, 0, 0, 0, $SWP_NOSIZE_NOMOVE_SHOW) | Out-Null
    }
}

# ── 0. 前置检查 + config ──────────────────────────────
if (-not (Test-Path -LiteralPath $SplashPath)) {
    Show-Info "缺少 index.html，请把整个文件夹一起复制过去。`n`n当前：$root"
    exit 1
}

$cfg = Read-Config -Path $cfgPath
if (-not $Browser -and $cfg['browserpath']) { $Browser = $cfg['browserpath'] }
if (-not $App -and $cfg['apppath']) { $App = $cfg['apppath'] }

if (-not $Browser -or -not (Test-Path -LiteralPath $Browser)) { $Browser = Find-Browser }
if (-not $Browser) {
    Show-Info "没有找到 Chrome 或 Edge。`n`n这个启动动画需要其中一个浏览器来播放，装上任意一个再试。"
    exit 1
}
if (-not $App -or -not (Test-Path -LiteralPath $App)) { $App = Find-App }

# 便携自检：powershell -File launcher.ps1 -DetectOnly 只打印探测结果，不播动画
if ($DetectOnly) {
    Write-Host "配置文件 : $cfgPath"
    if ($Browser) { Write-Host "浏览器   : $Browser" } else { Write-Host "浏览器   : (未找到)" }
    if ($App) {
        Write-Host "WorkBuddy: $App"
    } else {
        Write-Host "WorkBuddy: 快速探测未找到，深层扫描中…"
        $deep = Find-AppDeep -BudgetMs $DeepScanMs
        if ($deep) { Write-Host "深层结果 : $deep" } else { Write-Host "深层结果 : (未找到)" }
    }
    exit 0
}

# ── 1. 动画先上，并强制置顶 ───────────────────────────
$SplashUrl = ([System.Uri]$SplashPath).AbsoluteUri + '?launcher=1'
$tag = Split-Path -Leaf $ProfileDir

Start-Process $Browser -ArgumentList @(
    "--app=$SplashUrl",
    "--user-data-dir=$ProfileDir",
    "--start-fullscreen",
    "--no-first-run",
    "--no-default-browser-check",
    "--autoplay-policy=no-user-gesture-required",
    "--hide-crash-restore-bubble",
    "--noerrdialogs",
    "--window-size=1600,900"
)

$t0 = Get-Date
$elapsed = 0
$splash = $null
$splashPid = 0
while ($elapsed -lt 6000) {
    $splash = Find-Splash -Tag $tag -KnownPid $splashPid
    if ($splash) { $splashPid = $splash.Id; break }
    Start-Sleep -Milliseconds 100
    $elapsed = ((Get-Date) - $t0).TotalMilliseconds
}
Pin-Splash $splash
if ($splash) { [W32.U32]::SetForegroundWindow($splash.MainWindowHandle) | Out-Null }

# ── 2. 让动画先独占一会儿 ─────────────────────────────
while ($elapsed -lt $AppStartDelayMs) {
    Start-Sleep -Milliseconds 100
    $elapsed = ((Get-Date) - $t0).TotalMilliseconds
}

# ── 3. 还没找到程序：趁动画在播，后台深扫 + 手动兜底 ──
if (-not $App) { $App = Find-AppDeep -BudgetMs $DeepScanMs }
if (-not $App) {
    if ($splash) { [W32.U32]::SetWindowPos($splash.MainWindowHandle, $NOTOPMOST, 0, 0, 0, 0, 0x0010) | Out-Null }
    $picked = Select-AppFile
    if ($picked) {
        $App = $picked
        Set-ConfigValue -Path $cfgPath -Key 'AppPath' -Value $picked
    }
}
if (-not $App) {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
        Where-Object { $_.CommandLine -like "*$tag*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Show-Info "没有找到 WorkBuddy.exe。`n`n可以在 config.ini 里写一行：`nAppPath=你的完整路径\WorkBuddy.exe"
    exit 1
}

# ── 4. 启动程序（已有窗口就不重启） ──────────────────
$hadWindow = @(Get-Process WorkBuddy | Where-Object { $_.MainWindowHandle -ne 0 }).Count -gt 0
if (-not $hadWindow) { Start-Process $App }
Pin-Splash $splash

# ── 5. 等「动画播完」+「程序窗口就绪」 ───────────────
$ready = $false
while ($elapsed -lt $MaxWaitMs) {
    Pin-Splash $splash
    if (-not $splash) { $ready = $true }

    if (-not $ready) {
        $p = Get-Process -Id $splashPid
        if ($p -and ($p.MainWindowTitle -like '*WB_READY*' -or $p.MainWindowTitle -like '*SKIP_WB*')) { $ready = $true }
    }

    if ($ready) {
        if ($hadWindow) { break }
        if (Get-AppWindow) { break }
    }

    Start-Sleep -Milliseconds 120
    $elapsed = ((Get-Date) - $t0).TotalMilliseconds
}

# ── 6. 收场 ───────────────────────────────────────────
if ($splash) { [W32.U32]::SetWindowPos($splash.MainWindowHandle, $NOTOPMOST, 0, 0, 0, 0, 0x0010) | Out-Null }
Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like "*$tag*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Sleep -Milliseconds 260
$aw = Get-AppWindow
if ($aw -ne [IntPtr]::Zero) {
    if ([W32.U32]::IsIconic($aw)) { [W32.U32]::ShowWindow($aw, 9) | Out-Null }
    [W32.U32]::SetForegroundWindow($aw) | Out-Null
}
