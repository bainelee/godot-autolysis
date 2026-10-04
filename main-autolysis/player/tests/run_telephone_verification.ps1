param(
    [string]$EvidenceRoot = '',
    [string[]]$Checks = @()
)

# 电话实施默认全程无图形；所有单项使用现有执行器保留参数、退出码及错误。
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$runner = Join-Path $projectRoot 'main-autolysis\systems\item-system\tests\run_item_check.ps1'
if (-not $EvidenceRoot) {
    $EvidenceRoot = Join-Path $projectRoot ('docs\project-autolysis\00-discuss\交互系统\电话聚焦交互复验\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if ((Test-Path -LiteralPath $EvidenceRoot) -and @(Get-ChildItem -LiteralPath $EvidenceRoot -Force).Count -gt 0) {
    throw '证据目录非空；请指定新目录以保留既有结果。'
}
$playerTests = 'res://main-autolysis/player/tests/'
$itemTests = 'res://main-autolysis/systems/item-system/tests/'
$cases = @(
    @{Name='import'; Import=$true},
    @{Name='telephone-device'; Script=$playerTests+'telephone_device_test.gd'},
    @{Name='telephone-input'; Script=$playerTests+'telephone_input_test.gd'},
    @{Name='telephone-handset-view'; Script=$playerTests+'telephone_handset_view_test.gd'},
    @{Name='telephone-movement'; Script=$playerTests+'telephone_movement_test.gd'},
    @{Name='handset-inventory'; Script=$playerTests+'handset_inventory_test.gd'},
    @{Name='handset-pose'; Script=$playerTests+'handset_pose_debug_test.gd'},
    @{Name='telephone-dependencies'; Script=$playerTests+'telephone_dependency_audit.gd'},
    @{Name='telephone-commit-observers'; Script=$playerTests+'telephone_commit_observer_audit.gd'},
    @{Name='telephone-display-entry'; Script=$playerTests+'telephone_display_entry_audit.gd'},
    @{Name='telephone-pose-observer-input'; Script=$playerTests+'telephone_pose_observer_input_audit.gd'},
    @{Name='telephone-focus-dependency'; Script=$playerTests+'telephone_focus_dependency_audit.gd'},
    @{Name='telephone-return-cancel-dependency'; Script=$playerTests+'telephone_return_cancel_dependency_audit.gd'},
    @{Name='direct'; Script=$playerTests+'direct_interaction_test.gd'},
    @{Name='migration'; Script=$playerTests+'component_migration_test.gd'},
    @{Name='focus'; Script=$playerTests+'focus_interaction_test.gd'},
    @{Name='items'; Script=$itemTests+'item_system_test.gd'},
    @{Name='blend-transfers'; Script=$itemTests+'blend_slot_transfer_test.gd'},
    @{Name='tank-transactions'; Script=$itemTests+'liquid_tank_transaction_test.gd'; Errors=@('事务故障候选2$','事务故障候选4$','事务故障候选6$')},
    @{Name='packing-business'; Script=$itemTests+'packing_machine_behavior_test.gd'; Errors=@('封装器批次1故障，保留来源并关闭入口：源内容原药顺序、相位或波形与启动快照不一致')},
    @{Name='packing-atomic'; Script=$itemTests+'packing_batch_atomic_test.gd'; Errors=@('封装器批次1故障，保留来源并关闭入口：本轮胶囊节点或槽位归属失效','封装器批次1故障，保留来源并关闭入口：本轮液体罐节点或槽位归属失效')},
    @{Name='waste'; Script=$itemTests+'waste_liquid_tank_behavior_test.gd'},
    @{Name='player'; Script=$playerTests+'player_smoke_test.gd'}
)
$unknown = @($Checks | Where-Object { $_ -notin $cases.Name })
if ($unknown.Count -gt 0) { throw ('未知检查：' + ($unknown -join '、')) }
$selected = @($cases | Where-Object { $Checks.Count -eq 0 -or $_.Name -in $Checks })
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$results = @()
foreach ($case in $selected) {
    $details = Join-Path $EvidenceRoot $case.Name
    New-Item -ItemType Directory -Force -Path $details | Out-Null
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
    Write-Output ('开始无图形检查：' + $case.Name)
    & $runner @parameters
    $record = Get-Content -LiteralPath (Join-Path $EvidenceRoot ($case.Name + '.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
    $results += $record
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '检查汇总.json') -Encoding UTF8
    if (-not $record.通过) { throw ('检查失败，已保存依据：' + $case.Name) }
}
Write-Output ('全部选定无图形检查通过：' + $results.Count)
