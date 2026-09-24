param(
    [string]$EnginePath = 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe'
)

$ErrorActionPreference = 'Stop'
$projectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$evidencePath = Join-Path $projectPath '.godot\interaction-p1-evidence\final'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()

function Invoke-Verification([string]$name, [string[]]$engineArguments) {
    $stdoutPath = Join-Path $evidencePath ($name + '.stdout.log')
    $stderrPath = Join-Path $evidencePath ($name + '.stderr.log')
    $process = Start-Process -FilePath $EnginePath -ArgumentList $engineArguments -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $stdout = [IO.File]::ReadAllText($stdoutPath)
    $stderr = [IO.File]::ReadAllText($stderrPath)
    # 引擎脚本错误不一定改变进程退出码，必须同时检查实际错误输出。
    $hasEngineError = ($stdout + "`n" + $stderr) -match '(?m)^(SCRIPT ERROR:|ERROR:|失败：)'
    $passed = $process.ExitCode -eq 0 -and -not $hasEngineError
    $checkCount = ([regex]::Matches($stdout, '(?m)^通过：')).Count
    $result = [pscustomobject]@{Name=$name; ExitCode=$process.ExitCode; EngineError=$hasEngineError; Passed=$passed; Checks=$checkCount; Arguments=$engineArguments}
    $results.Add($result)
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidencePath 'results.json') -Encoding utf8
    Write-Output ("{0}：{1}，检查{2}项，进程退出码{3}" -f $(if ($passed) {'通过'} else {'失败'}), $name, $checkCount, $process.ExitCode)
    if (-not $passed) {
        Write-Output $stdout
        Write-Output $stderr
        throw "验证失败，完整日志已保存：$evidencePath"
    }
}

Invoke-Verification 'editor-import' @('--headless', '--path', $projectPath, '--editor', '--quit')
Invoke-Verification 'component-contracts' @('--headless', '--path', $projectPath, '--script', 'res://main-autolysis/player/tests/direct_interaction_test.gd')
Invoke-Verification 'component-migration' @('--headless', '--path', $projectPath, '--script', 'res://main-autolysis/player/tests/component_migration_test.gd')
Invoke-Verification 'player-smoke' @('--headless', '--path', $projectPath, '--script', 'res://main-autolysis/player/tests/player_smoke_test.gd')
Invoke-Verification 'footstep-smoke' @('--headless', '--fixed-fps', '60', '--path', $projectPath, '--script', 'res://main-autolysis/player/tests/footstep_smoke_test.gd')
Invoke-Verification 'direct-rendered' @('--path', $projectPath, '--script', 'res://main-autolysis/player/tests/direct_interaction_test.gd')
Write-Output '全部自动验收完成；完整交互使用实际图形后端。'
