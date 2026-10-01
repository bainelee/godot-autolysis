param(
    [string]$Label = 'baseline-phases',
    [switch]$DisableSync,
    [switch]$PhysicsVerdict
)

$ErrorActionPreference = 'Stop'
$stdoutPath = Join-Path $PSScriptRoot ($Label + '.stdout.log')
$stderrPath = Join-Path $PSScriptRoot ($Label + '.stderr.log')
$engineArguments = @('--headless', '--path', 'D:\autolysis', '--quit-after', '180', '--script', 'res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/door-diagnostic/door_sync_diagnostic.gd', '--', $Label)
if ($DisableSync) { $engineArguments += 'disable-sync' }
if ($PhysicsVerdict) { $engineArguments += 'physics-check' }
$diagnosticRun = Start-Process -FilePath 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe' -ArgumentList $engineArguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
if (-not $diagnosticRun.WaitForExit(15000)) {
    Stop-Process -Id $diagnosticRun.Id
    throw '门诊断超过十五秒限制，已终止本次启动的进程'
}
$stdout = [IO.File]::ReadAllText($stdoutPath)
$stderr = [IO.File]::ReadAllText($stderrPath)
$result = [ordered]@{
    '退出码' = $diagnosticRun.ExitCode
    '引擎错误' = ($stdout + $stderr) -match '(?m)^(SCRIPT ERROR:|ERROR:)'
    '参数' = $engineArguments
    '关闭同步对照' = [bool]$DisableSync
    '按物理回调判定' = [bool]$PhysicsVerdict
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot ($Label + '.run.json')) -Encoding utf8
Write-Output $stdout
Write-Output $stderr
exit $diagnosticRun.ExitCode
