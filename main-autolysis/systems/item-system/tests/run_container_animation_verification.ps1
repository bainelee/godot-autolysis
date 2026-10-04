param(
    [string]$EvidenceRoot = '',
    [string[]]$Checks = @(),
    [switch]$HeadlessOnly,
    [switch]$IncludeRendered,
    [switch]$IncludeNativeMouse
)

# 默认只执行无图形检查；图形窗口及真实系统指针检查必须分别显式选择。
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$runner = Join-Path $PSScriptRoot 'run_item_check.ps1'
if (-not $EvidenceRoot) {
    $EvidenceRoot = Join-Path $projectRoot ('docs\project-autolysis\00-discuss\道具系统\容器开闭动画控制复验\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if ((Test-Path -LiteralPath $EvidenceRoot) -and @(Get-ChildItem -LiteralPath $EvidenceRoot -Force).Count -gt 0) {
    throw '证据目录已包含文件；请指定新目录，以保留既有检查记录。'
}
$itemTests = 'res://main-autolysis/systems/item-system/tests/'
$playerTests = 'res://main-autolysis/player/tests/'
$cases = @(
    @{Name='import'; Import=$true},
    @{Name='timing'; Script=$itemTests+'container_animation_timing_probe.gd'},
    @{Name='direct'; Script=$playerTests+'direct_interaction_test.gd'},
    @{Name='migration'; Script=$playerTests+'component_migration_test.gd'},
    @{Name='items'; Script=$itemTests+'item_system_test.gd'},
    @{Name='container-assets'; Script=$itemTests+'container_animation_asset_test.gd'},
    @{Name='waste'; Script=$itemTests+'waste_liquid_tank_behavior_test.gd'},
    @{Name='cabinet'; Script=$itemTests+'liquid_tank_cabinet_behavior_test.gd'},
    @{Name='tank-transactions'; Script=$itemTests+'liquid_tank_transaction_test.gd'; Errors=@('事务故障候选2$','事务故障候选4$','事务故障候选6$')},
    @{Name='packing-motion'; Script=$itemTests+'packing_motion_physics_test.gd'},
    @{Name='packing-isolation'; Script=$itemTests+'packing_asset_isolation_test.gd'},
    @{Name='packing-business'; Script=$itemTests+'packing_machine_behavior_test.gd'; Errors=@('封装器批次1故障，保留来源并关闭入口：源内容原药顺序、相位或波形与启动快照不一致')},
    @{Name='packing-atomic'; Script=$itemTests+'packing_batch_atomic_test.gd'; Errors=@('封装器批次1故障，保留来源并关闭入口：本轮胶囊节点或槽位归属失效','封装器批次1故障，保留来源并关闭入口：本轮液体罐节点或槽位归属失效')},
    @{Name='packing-indicator'; Script=$itemTests+'packing_indicator_test.gd'; Errors=@('封装器批次1故障，保留来源并关闭入口：已预检两件物品拒绝静默共同提交，保留输入')},
    @{Name='blend-assets'; Script=$itemTests+'blend_animation_variants_test.gd'},
    @{Name='blend-transfers'; Script=$itemTests+'blend_slot_transfer_test.gd'},
    @{Name='blend-business'; Script=$itemTests+'liquid_contents_blend_test.gd'; Errors=@('配药器批次1故障，保持交互关闭：本轮原药来源或实例失效：槽号3；/root/FocusInteractionDemo/MachineA$')},
    @{Name='blend-atomic'; Script=$itemTests+'machine_batch_atomic_test.gd'},
    @{Name='blend-indicator'; Script=$itemTests+'blend_indicator_test.gd'},
    @{Name='handle'; Script=$playerTests+'blend_handle_drag_test.gd'},
    @{Name='direct-rendered'; Script=$playerTests+'direct_interaction_test.gd'; Rendered=$true},
    @{Name='focus-rendered'; Script=$playerTests+'focus_interaction_test.gd'; Rendered=$true},
    @{Name='focus-local-rendered'; Script=$playerTests+'focus_interaction_test.gd'; Rendered=$true; Arguments=@('--local-only')},
    @{Name='waste-main-rendered'; Script=$itemTests+'waste_liquid_tank_behavior_test.gd'; Rendered=$true},
    @{Name='cabinet-main-rendered'; Script=$itemTests+'liquid_tank_cabinet_rendered_test.gd'; Rendered=$true},
    @{Name='packing-main-rendered'; Script=$itemTests+'packing_machine_behavior_test.gd'; Rendered=$true; Errors=@('封装器批次1故障，保留来源并关闭入口：源内容原药顺序、相位或波形与启动快照不一致')},
    @{Name='packing-switch-rendered'; Script=$itemTests+'packing_switch_repeat_test.gd'; Rendered=$true},
    @{Name='packing-indicator-rendered'; Script=$itemTests+'packing_indicator_test.gd'; Rendered=$true; Errors=@('封装器批次1故障，保留来源并关闭入口：已预检两件物品拒绝静默共同提交，保留输入')},
    @{Name='handle-rendered'; Script=$playerTests+'blend_handle_drag_test.gd'; Rendered=$true},
    @{Name='collision-rendered'; Script=$playerTests+'blend_collision_follow_test.gd'; Rendered=$true},
    @{Name='handle-native-mouse'; Script=$playerTests+'blend_handle_native_loop_test.gd'; Rendered=$true; Native=$true}
)
$unknown = @($Checks | Where-Object { $_ -notin $cases.Name })
if ($unknown.Count -gt 0) { throw ('未知检查名称：' + ($unknown -join '、')) }
$selected = @($cases | Where-Object {
    ($Checks.Count -eq 0 -or $_.Name -in $Checks) -and
    (-not $_.Rendered -or $IncludeRendered) -and
    (-not $HeadlessOnly -or -not $_.Rendered) -and
    (-not $_.Native -or $IncludeNativeMouse)
})
if ($selected.Count -eq 0) { throw '当前参数没有选择可执行检查。' }
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
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
    if ($case.Arguments) { $parameters.UserArguments += $case.Arguments }
    if ($case.Rendered) { $parameters.Rendered = $true }
    if ($case.Native) { $parameters.Visible = $true }
    if ($case.Errors) { $parameters.ExpectedErrorPatterns = $case.Errors }
    Write-Output ('开始检查：' + $case.Name)
    & $runner @parameters
    $record = Get-Content -LiteralPath (Join-Path $EvidenceRoot ($case.Name + '.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
    $results += $record
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '检查汇总.json') -Encoding UTF8
    if (-not $record.通过) { throw ('检查失败，已保留日志：' + $case.Name) }
}
Write-Output ('全部选定检查通过：' + $results.Count + '；证据目录：' + $EvidenceRoot)
