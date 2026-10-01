param(
    [ValidateSet('import', 'transactions', 'behavior', 'mouse-capability', 'input', 'rendered', 'items', 'shelf-layers', 'shelf-clearance', 'blend-transfer', 'direct', 'direct-rendered', 'focus', 'focus-rendered', 'main')]
    [string]$Check = 'import'
)

# 隐藏启动指定引擎；只管理本次创建的进程，逐项保存运行参数和结果。
$enginePath = 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe'
$projectPath = 'D:\autolysis'
$evidenceRoot = Join-Path $projectPath 'docs\project-autolysis\00-discuss\道具系统\液体罐与专用柜实施证据\checks'
$outputDirectory = Join-Path $evidenceRoot $Check
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$argumentList = @('--path', $projectPath)
$scriptPath = ''

switch ($Check) {
    'import' { $argumentList += @('--headless', '--editor', '--import') }
    'transactions' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/liquid_tank_transaction_test.gd' }
    'behavior' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/liquid_tank_cabinet_behavior_test.gd' }
    'mouse-capability' { $scriptPath = 'res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/鼠标捕获诊断.gd' }
    'input' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/liquid_tank_cabinet_rendered_test.gd' }
    'rendered' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/liquid_tank_cabinet_rendered_test.gd' }
    'items' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/item_system_test.gd' }
    'shelf-layers' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/shelf_layers_test.gd' }
    'shelf-clearance' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/shelf_clearance_test.gd' }
    'blend-transfer' { $scriptPath = 'res://main-autolysis/systems/item-system/tests/blend_slot_transfer_test.gd' }
    'direct' { $scriptPath = 'res://main-autolysis/player/tests/direct_interaction_test.gd' }
    'direct-rendered' { $scriptPath = 'res://main-autolysis/player/tests/direct_interaction_test.gd' }
    'focus' { $scriptPath = 'res://main-autolysis/player/tests/focus_interaction_test.gd' }
    'focus-rendered' { $scriptPath = 'res://main-autolysis/player/tests/focus_interaction_test.gd' }
    'main' { $argumentList += @('--headless', '--quit-after', '120') }
}

# 既有聚焦时序判据要求普通帧和物理帧均为每秒六十帧。
if ($Check -in @('focus', 'focus-rendered')) { $argumentList += @('--fixed-fps', '60') }

if ($scriptPath) {
    if ($Check -in @('input', 'rendered', 'direct-rendered', 'focus-rendered')) {
        $argumentList += @('--resolution', '1280x720')
    } else {
        $argumentList += '--headless'
    }
    $argumentList += @('--script', $scriptPath, '--', '--evidence-dir', $outputDirectory)
    if ($Check -in @('input', 'rendered')) { $argumentList += '--require-rendered' }
}

$stdoutPath = Join-Path $outputDirectory '标准输出.log'
$stderrPath = Join-Path $outputDirectory '错误输出.log'
$quotedArguments = foreach ($argument in $argumentList) {
    if ($argument -match '\s') { '"' + $argument + '"' } else { $argument }
}
$startedAt = [DateTimeOffset]::Now
$process = Start-Process -FilePath $enginePath -ArgumentList $quotedArguments -WorkingDirectory $projectPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$completed = $process.WaitForExit(240000)
if (-not $completed) {
    Stop-Process -Id $process.Id -Force
    $process.WaitForExit()
}
$process.Refresh()
$hasScriptError = ([IO.File]::ReadAllText($stdoutPath) + [IO.File]::ReadAllText($stderrPath)) -match '(?m)^SCRIPT ERROR:'
$hasEngineError = ([IO.File]::ReadAllText($stdoutPath) + [IO.File]::ReadAllText($stderrPath)) -match '(?m)^ERROR:'
$report = [pscustomobject]@{
    检查 = $Check
    引擎 = $enginePath
    工程 = $projectPath
    参数 = $argumentList
    开始时间 = $startedAt.ToString('o')
    用时秒 = ([DateTimeOffset]::Now - $startedAt).TotalSeconds
    本次进程编号 = $process.Id
    超时 = -not $completed
    退出码 = $process.ExitCode
    脚本异常 = $hasScriptError
    引擎错误 = $hasEngineError
    标准输出 = $stdoutPath
    错误输出 = $stderrPath
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDirectory '执行结果.json') -Encoding utf8
$report | ConvertTo-Json -Depth 4
Get-Content -LiteralPath $stdoutPath -Tail 12
Get-Content -LiteralPath $stderrPath -Tail 30
if (-not $completed) { exit 124 }
if ($hasScriptError -or $hasEngineError) { exit 1 }
exit $process.ExitCode
