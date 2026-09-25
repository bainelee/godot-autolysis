$ErrorActionPreference = 'Stop'
$taskProject = 'D:\autolysis'
$taskEvidence = $PSScriptRoot
$taskManifest = Get-Content -Raw -LiteralPath (Join-Path $taskEvidence 'manifest-before.json') | ConvertFrom-Json
$taskResults = foreach ($entry in $taskManifest) {
    $currentHash = (Get-FileHash -LiteralPath (Join-Path $taskProject $entry.Path)).Hash
    [pscustomobject]@{路径=$entry.Path; 实施前摘要=$entry.SHA256; 实施后摘要=$currentHash; 保持一致=($entry.SHA256 -eq $currentHash)}
}
function Get-ProtectedShelfContent([string]$Path) {
    $content = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    $sections = [regex]::Split($content, '(?m)(?=^\[)')
    $kept = foreach ($section in $sections) {
        if ($section -match '^\[sub_resource type="BoxShape3D"' -or $section -match '^\[node name="[^"]+" type="CollisionShape3D"') { continue }
        [regex]::Replace($section, '(?m)^collision_layer = \d+\n', '').Trim()
    }
    return $kept -join "`n"
}
$shelfResults = foreach ($relative in @('main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn', 'main-autolysis/scenes/prefabs/prefab_furnitures/store_shelf_warehouse_0.tscn')) {
    $beforePath = Join-Path $taskEvidence ('baseline/' + $relative)
    $afterPath = Join-Path $taskProject $relative
    $protectedSame = (Get-ProtectedShelfContent $beforePath) -ceq (Get-ProtectedShelfContent $afterPath)
    $beforeText = [IO.File]::ReadAllText($beforePath)
    $afterText = [IO.File]::ReadAllText($afterPath)
    $mainShapeHeader = [regex]::Match($beforeText, '(?m)^\[node name="CollisionShape3D"[^\r\n]+').Value
    $mainShapeSame = $afterText.Contains($mainShapeHeader)
    [pscustomobject]@{路径=$relative; 非碰撞内容保持一致=$protectedSame; 主碰撞节点标识保持一致=$mainShapeSame; 当前碰撞形状数=[regex]::Matches($afterText, 'type="CollisionShape3D"').Count}
}
$protectedPaths = @(
    'main-autolysis\scenes\01-autolysis-test.tscn',
    'main-autolysis\player\components\autolysis_inventory_controller.gd',
    'main-autolysis\player\components\autolysis_held_item_presenter.gd',
    'main-autolysis\systems\item-system\autolysis_raw_material_shelf.gd',
    'main-autolysis\systems\item-system\autolysis_raw_material.gd',
    'main-autolysis\systems\item-system\autolysis_raw_material_group.gd'
)
$protected = @($taskResults | Where-Object { $protectedPaths -contains $_.路径 -or $_.路径 -like 'main-autolysis\ui\*' -or $_.路径 -like 'main-autolysis\systems\item-system\items\*' -or $_.路径 -like 'main-autolysis\scenes\prefabs\prefab_raw_materials\*' })
$passed = @($protected | Where-Object { -not $_.保持一致 }).Count -eq 0 -and @($shelfResults | Where-Object { -not $_.非碰撞内容保持一致 -or -not $_.主碰撞节点标识保持一致 -or $_.当前碰撞形状数 -ne 1 }).Count -eq 0
$report = [pscustomobject]@{时间=(Get-Date -Format o); 通过=$passed; 全部快照数量=@($taskResults).Count; 改动文件=@($taskResults | Where-Object { -not $_.保持一致 }); 保护对象=$protected; 架体保护=$shelfResults}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskEvidence 'preservation.json') -Encoding utf8
$report | Select-Object 时间,通过,全部快照数量
$shelfResults | Format-List
if (-not $passed) { throw '保护对象差异核对失败' }
