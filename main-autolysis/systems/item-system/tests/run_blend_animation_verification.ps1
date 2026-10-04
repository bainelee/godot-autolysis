param(
    [string]$EvidenceRoot = '',
    [string[]]$Only = @('variants', 'transfer', 'liquid', 'indicator', 'handle', 'collision'),
    [switch]$Rendered
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
if (-not $EvidenceRoot) {
    $EvidenceRoot = Join-Path $projectRoot 'docs\project-autolysis\00-discuss\道具系统\容器开闭动画控制实施证据\20261004\blend-checks'
}
$checks = @{
    variants = 'res://main-autolysis/systems/item-system/tests/blend_animation_variants_test.gd'
    transfer = 'res://main-autolysis/systems/item-system/tests/blend_slot_transfer_test.gd'
    liquid = 'res://main-autolysis/systems/item-system/tests/liquid_contents_blend_test.gd'
    indicator = 'res://main-autolysis/systems/item-system/tests/blend_indicator_test.gd'
    handle = 'res://main-autolysis/player/tests/blend_handle_drag_test.gd'
    collision = 'res://main-autolysis/player/tests/blend_collision_follow_test.gd'
}
foreach ($check in $Only) {
    if (-not $checks.ContainsKey($check)) { throw "不存在的配药检查编号：$check" }
    $expectedErrors = @()
    if ($check -eq 'liquid') {
        $expectedErrors = @('^ERROR: 配药器批次1故障，保持交互关闭：本轮原药来源或实例失效：槽号3')
    }
    $caseDirectory = Join-Path $EvidenceRoot $check
    $arguments = @('--evidence-dir', $caseDirectory.Replace('\', '/'))
    & (Join-Path $PSScriptRoot 'run_item_check.ps1') -CheckName ('blend-' + $check) -ScriptPath $checks[$check] -EvidenceRoot $EvidenceRoot -FixedFps 60 -TimeoutSeconds 240 -Rendered:$Rendered -ExpectedErrorPatterns $expectedErrors -UserArguments $arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
