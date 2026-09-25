param(
    [Parameter(Mandatory=$true)][string]$CheckName,
    [string]$ScriptPath = '',
    [string]$ScenePath = '',
    [int]$QuitAfter = 0,
    [int]$FixedFps = 0,
    [switch]$Rendered,
    [switch]$Import,
    [int]$TimeoutSeconds = 180,
    [string[]]$UserArguments = @()
)

# 必须在具备引擎用户目录访问权限的进程中运行，单项失败立即退出。
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$evidenceRoot = Join-Path $projectRoot 'docs\project-autolysis\00-discuss\道具系统\道具系统p1实施证据\checks'
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
$engineFile = 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe'
$engineArgs = @('--path', $projectRoot)
if (-not $Rendered) { $engineArgs += '--headless' }
if ($FixedFps -gt 0) { $engineArgs += @('--fixed-fps', "$FixedFps") }
if ($QuitAfter -gt 0) { $engineArgs += @('--quit-after', "$QuitAfter") }
if ($Import) { $engineArgs += @('--editor','--quit') }
elseif ($ScriptPath) { $engineArgs += @('--script', $ScriptPath) }
elseif ($ScenePath) { $engineArgs += $ScenePath }
if ($UserArguments.Count -gt 0) { $engineArgs += '--'; $engineArgs += $UserArguments }
$outputFile = Join-Path $evidenceRoot ($CheckName + '.stdout.log')
$errorFile = Join-Path $evidenceRoot ($CheckName + '.stderr.log')
$checkProcess = Start-Process -FilePath $engineFile -ArgumentList $engineArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile
if (-not $checkProcess.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $checkProcess.Id -Force
    throw "检查超时，已停止本次启动的进程：$CheckName"
}
$checkProcess.Refresh()
$allOutput = [IO.File]::ReadAllText($outputFile) + "`n" + [IO.File]::ReadAllText($errorFile)
$passed = $checkProcess.ExitCode -eq 0 -and $allOutput -notmatch '(?m)^(SCRIPT ERROR:|ERROR:|失败：)'
$record = [pscustomobject]@{检查=$CheckName; 时间=(Get-Date -Format o); 进程编号=$checkProcess.Id; 退出码=$checkProcess.ExitCode; 通过=$passed; 命令参数=$engineArgs; 通过断言数=([regex]::Matches($allOutput,'(?m)^通过：')).Count}
$record | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $evidenceRoot ($CheckName + '.json')) -Encoding utf8
$record | Format-List
if (-not $passed) { Write-Output $allOutput; exit 1 }
exit 0
