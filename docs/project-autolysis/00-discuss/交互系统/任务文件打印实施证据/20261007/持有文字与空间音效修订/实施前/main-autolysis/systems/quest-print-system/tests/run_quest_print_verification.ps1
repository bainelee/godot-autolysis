param(
    [string]$EvidenceRoot = '',
    [string[]]$Checks = @()
)

# 本入口只运行无图形检查；不会启动图形测试窗口或操作原生指针。
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$runner = Join-Path $projectRoot 'main-autolysis\systems\item-system\tests\run_item_check.ps1'
if (-not $EvidenceRoot) {
    $EvidenceRoot = Join-Path $projectRoot ('docs\project-autolysis\00-discuss\交互系统\任务文件打印实施证据\复验\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if ((Test-Path -LiteralPath $EvidenceRoot) -and @(Get-ChildItem -LiteralPath $EvidenceRoot -Force).Count -gt 0) {
    throw '证据目录已经包含文件，请指定新目录以保留历史运行。'
}
$cases = @(
    @{Name='导入解析'; Import=$true},
    @{Name='数据纸面'; Script='res://main-autolysis/systems/quest-print-system/tests/quest_paper_data_view_test.gd'},
    @{Name='打印时序'; Script='res://main-autolysis/systems/quest-print-system/tests/quest_machine_behavior_test.gd'},
    @{Name='主场景输入'; Script='res://main-autolysis/player/tests/quest_print_main_test.gd'},
    @{Name='聚焦取纸'; Script='res://main-autolysis/player/tests/quest_paper_inventory_test.gd'},
    @{Name='展示释放边界'; Script='res://main-autolysis/player/tests/quest_display_release_probe.gd'},
    @{Name='道具回归'; Script='res://main-autolysis/systems/item-system/tests/item_system_test.gd'},
    @{Name='直接交互回归'; Script='res://main-autolysis/player/tests/direct_interaction_test.gd'},
    @{Name='组件迁移回归'; Script='res://main-autolysis/player/tests/component_migration_test.gd'},
    @{Name='聚焦回归'; Script='res://main-autolysis/player/tests/focus_interaction_test.gd'},
    @{Name='电话持物互斥回归'; Script='res://main-autolysis/player/tests/telephone_device_test.gd'},
    @{Name='电话测试入口回归'; Script='res://main-autolysis/player/tests/telephone_call_entry_test.gd'}
)
$unknown = @($Checks | Where-Object { $_ -notin $cases.Name })
if ($unknown.Count -gt 0) { throw ('未知检查名称：' + ($unknown -join '、')) }
$selected = @($cases | Where-Object { $Checks.Count -eq 0 -or $_.Name -in $Checks })
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $EvidenceRoot '.gdignore'), '')
$results = @()
foreach ($case in $selected) {
    $details = Join-Path $EvidenceRoot $case.Name
    $parameters = @{
        CheckName = $case.Name
        EvidenceRoot = $EvidenceRoot
        FixedFps = 60
        TimeoutSeconds = 240
        UserArguments = @('--evidence-dir', $details.Replace('\','/'))
    }
    if ($case.Import) { $parameters.Import = $true }
    else { $parameters.ScriptPath = $case.Script }
    if ($case.Errors) { $parameters.ExpectedErrorPatterns = $case.Errors }
    Write-Output ('开始检查：' + $case.Name)
    & $runner @parameters
    $record = Get-Content -LiteralPath (Join-Path $EvidenceRoot ($case.Name + '.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
    $outputText = [IO.File]::ReadAllText((Join-Path $EvidenceRoot ($case.Name + '.stdout.log'))) + "`n" + [IO.File]::ReadAllText((Join-Path $EvidenceRoot ($case.Name + '.stderr.log')))
    $leakLines = @([regex]::Matches($outputText, '(?m)^(WARNING: ObjectDB instances leaked at exit[^\r\n]*|ERROR: [0-9]+ resources still in use at exit[^\r\n]*)') | ForEach-Object { $_.Value })
    if ($leakLines.Count -gt 0) {
        $record.通过 = $false
        $record.非预期错误 = @($record.非预期错误) + $leakLines
        $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceRoot ($case.Name + '.json')) -Encoding UTF8
    }
    $results += $record
    $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '检查汇总.json') -Encoding UTF8
    if (-not $record.通过) { throw ('检查失败，完整日志已保留：' + $case.Name) }
}
Write-Output ('全部选定无图形检查通过：' + $results.Count)
