$ErrorActionPreference = 'Stop'
$workspacePath = 'D:\autolysis'
$evidencePath = Join-Path $workspacePath 'docs\project-autolysis\00-discuss\道具系统\道具系统p1实施证据'
$baselinePath = Join-Path $evidencePath 'baseline'
$reportPath = Join-Path $evidencePath 'checks\preservation.json'
$checks = [System.Collections.Generic.List[object]]::new()

function Read-Scene([string]$path) {
    $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Trim()
    $sections = [System.Collections.Generic.List[object]]::new()
    foreach ($chunk in [regex]::Split($text, '(?m)(?=^\[)')) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
        $block = $chunk.Trim()
        $header = $block.Split("`n")[0]
        $kind = [regex]::Match($header, '^\[(\w+)').Groups[1].Value
        $sections.Add([pscustomobject]@{ Kind = $kind; Header = $header; Text = $block })
    }
    return $sections.ToArray()
}

function Get-Attribute([object]$section, [string]$name) {
    $match = [regex]::Match($section.Header, '\b' + [regex]::Escape($name) + '="([^"]*)"')
    if ($match.Success) { return $match.Groups[1].Value }
    $match = [regex]::Match($section.Header, '\b' + [regex]::Escape($name) + '=(\d+)')
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}

function Get-Property([object]$section, [string]$name) {
    return [regex]::Match($section.Text, '(?m)^' + [regex]::Escape($name) + ' = (.+)$').Groups[1].Value
}

function Add-Check([string]$name, [bool]$passed, [object]$sources, [object]$details) {
    $checks.Add([ordered]@{ '项目' = $name; '通过' = $passed; '实际源路径' = @($sources); '数据' = $details })
}

function Same-Sections([object[]]$left, [object[]]$right) {
    return (($left | ForEach-Object Text) -join "`n`n") -ceq (($right | ForEach-Object Text) -join "`n`n")
}

function Get-NodeIdentity([object[]]$scene) {
    $rootNode = @($scene | Where-Object { $_.Kind -eq 'node' })[0]
    $sceneHeader = @($scene | Where-Object { $_.Kind -eq 'gd_scene' })[0]
    return [ordered]@{
        '场景唯一标识' = Get-Attribute $sceneHeader 'uid'
        '根节点名称' = Get-Attribute $rootNode 'name'
        '根节点类型' = Get-Attribute $rootNode 'type'
        '根节点唯一标识' = Get-Attribute $rootNode 'unique_id'
        '根节点变换' = Get-Property $rootNode 'transform'
    }
}

$changedFiles = [System.Collections.Generic.List[object]]::new()
$missingFiles = [System.Collections.Generic.List[object]]::new()
$unchangedFiles = [System.Collections.Generic.List[object]]::new()
$baselineRecords = [System.Collections.Generic.List[object]]::new()
$manifestPath = Join-Path $evidencePath 'baseline-hashes.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifestMap = @{}
foreach ($entry in $manifest) { $manifestMap[$entry.Path] = $entry.Hash }
$baselineSnapshotIntact = $true
foreach ($file in Get-ChildItem -LiteralPath $baselinePath -Recurse -File | Sort-Object FullName) {
    $relativePath = $file.FullName.Substring($baselinePath.Length + 1)
    $currentPath = Join-Path $workspacePath $relativePath
    $baselineHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $recordedHash = $manifestMap[$currentPath]
    $matchesManifest = $null -ne $recordedHash -and $baselineHash -ceq $recordedHash
    if (-not $matchesManifest) { $baselineSnapshotIntact = $false }
    $baselineRecords.Add([ordered]@{
        '基线源路径' = $file.FullName; '当前源路径' = $currentPath
        '基线实际校验值' = $baselineHash; '先前登记校验值' = $recordedHash; '基线副本未变' = $matchesManifest
    })
    if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
        $missingFiles.Add([ordered]@{ '基线源路径' = $file.FullName; '缺失路径' = $currentPath })
        continue
    }
    $currentHash = (Get-FileHash -LiteralPath $currentPath -Algorithm SHA256).Hash
    $record = [ordered]@{
        '相对路径' = $relativePath; '基线源路径' = $file.FullName; '当前源路径' = $currentPath
        '基线校验值' = $baselineHash; '当前校验值' = $currentHash
    }
    if ($baselineHash -ceq $currentHash) { $unchangedFiles.Add($record) } else { $changedFiles.Add($record) }
}
Add-Check '基线副本与实施前已登记校验值一致' $baselineSnapshotIntact @($baselinePath, $manifestPath) $baselineRecords.ToArray()
Add-Check '实施前已有文件未缺失' ($missingFiles.Count -eq 0) @($baselinePath, $workspacePath) @{ '缺失数量' = $missingFiles.Count }

$mainRelativePath = 'main-autolysis\scenes\01-autolysis-test.tscn'
$oldMainPath = Join-Path $baselinePath $mainRelativePath
$newMainPath = Join-Path $workspacePath $mainRelativePath
$oldMain = [IO.File]::ReadAllText($oldMainPath).Replace("`r`n", "`n")
$newMain = [IO.File]::ReadAllText($newMainPath).Replace("`r`n", "`n")
$oldUpperShelf = 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -4.2000003, 1.2, 11.999999)'
$newUpperShelf = 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -4.2000003, 1.3, 11.999999)'
$upperShelfMatchCount = [regex]::Matches($oldMain, [regex]::Escape($oldUpperShelf)).Count
Add-Check '主场景仅上架高度由1.2改为1.3' ($upperShelfMatchCount -eq 1 -and $oldMain.Replace($oldUpperShelf, $newUpperShelf) -ceq $newMain) @($oldMainPath, $newMainPath) @{
    '节点路径' = 'interaction_prefabs/item_groups/place_shelf_workroom_rm_0'; '原行号' = 1307
    '原变换' = $oldUpperShelf; '现变换' = $newUpperShelf; '精确替换出现次数' = $upperShelfMatchCount
}

foreach ($materialName in @('caffeine', 'sodium_benzoate')) {
    $materialLabel = if ($materialName -eq 'caffeine') { '咖啡因' } else { '苯甲酸钠' }
    $worldRelativePath = "main-autolysis\scenes\prefabs\prefab_raw_materials\rm_${materialName}_0.tscn"
    $oldWorldPath = Join-Path $baselinePath $worldRelativePath
    $newWorldPath = Join-Path $workspacePath $worldRelativePath
    $visualPath = Join-Path $workspacePath "main-autolysis\scenes\prefabs\prefab_raw_materials\visuals\rm_${materialName}_visual.tscn"
    $oldWorld = @(Read-Scene $oldWorldPath)
    $newWorld = @(Read-Scene $newWorldPath)
    $visual = @(Read-Scene $visualPath)
    $oldMeshNodes = @($oldWorld | Where-Object { $_.Kind -eq 'node' -and ((Get-Attribute $_ 'name') -eq 'mesh' -or (Get-Attribute $_ 'parent') -eq 'mesh' -or (Get-Attribute $_ 'parent').StartsWith('mesh/')) })
    $normalizedOldNodes = @($oldMeshNodes | ForEach-Object {
        $text = $_.Text
        if ((Get-Attribute $_ 'name') -eq 'mesh' -and (Get-Attribute $_ 'parent') -eq '.') {
            $text = $text.Replace(' parent="."', '')
        } else {
            $text = $text.Replace(' parent="mesh"', ' parent="."').Replace(' parent="mesh/', ' parent="')
        }
        [pscustomobject]@{ Text = $text }
    })
    $visualNodes = @($visual | Where-Object Kind -eq 'node')
    $oldMeshResources = @($oldWorld | Where-Object { $_.Kind -eq 'sub_resource' -and (Get-Attribute $_ 'type').EndsWith('Mesh') })
    $newMeshResources = @($visual | Where-Object Kind -eq 'sub_resource')
    $oldMaterialReferences = @($oldWorld | Where-Object { $_.Kind -eq 'ext_resource' -and (Get-Attribute $_ 'type') -eq 'Material' })
    $newMaterialReferences = @($visual | Where-Object Kind -eq 'ext_resource')
    $geometryPreserved = (Same-Sections $normalizedOldNodes $visualNodes) -and (Same-Sections $oldMeshResources $newMeshResources) -and (Same-Sections $oldMaterialReferences $newMaterialReferences)
    Add-Check "${materialLabel}：纯显示场景与旧模型子树等价" $geometryPreserved @($oldWorldPath, $visualPath) @{
        '旧模型节点数' = $oldMeshNodes.Count; '新模型节点数' = $visualNodes.Count
        '旧网格资源数' = $oldMeshResources.Count; '新网格资源数' = $newMeshResources.Count
        '节点变换材质引用及唯一标识逐段一致' = Same-Sections $normalizedOldNodes $visualNodes
        '网格几何全部属性逐段一致' = Same-Sections $oldMeshResources $newMeshResources
        '外部材质资源路径及唯一标识逐段一致' = Same-Sections $oldMaterialReferences $newMaterialReferences
        '唯一结构归一化' = '旧模型根从物理体子节点提升为纯显示场景根；原子节点父路径随此前缀变化。没有改写数值或材质。'
        '旧节点文本' = @($oldMeshNodes | ForEach-Object Text); '新节点文本' = @($visualNodes | ForEach-Object Text)
    }
    $oldIdentity = Get-NodeIdentity $oldWorld
    $newIdentity = Get-NodeIdentity $newWorld
    $oldCollision = @($oldWorld | Where-Object { (Get-Attribute $_ 'type') -in @('BoxShape3D', 'CollisionShape3D') })
    $newCollision = @($newWorld | Where-Object { (Get-Attribute $_ 'type') -in @('BoxShape3D', 'CollisionShape3D') })
    $oldMeshRoot = @($oldMeshNodes | Where-Object { (Get-Attribute $_ 'name') -eq 'mesh' })[0]
    $newMeshRoot = @($newWorld | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'name') -eq 'mesh' })[0]
    $worldVisualReference = @($newWorld | Where-Object { $_.Kind -eq 'ext_resource' -and (Get-Attribute $_ 'path') -eq "res://main-autolysis/scenes/prefabs/prefab_raw_materials/visuals/rm_${materialName}_visual.tscn" })
    $worldVisualBindingValid = $worldVisualReference.Count -eq 1 -and (Get-Attribute $worldVisualReference[0] 'uid') -eq '' -and $newMeshRoot.Header.Contains(('instance=ExtResource("{0}")' -f (Get-Attribute $worldVisualReference[0] 'id')))
    $worldMeshPlacementPreserved = (Get-Attribute $oldMeshRoot 'unique_id') -eq (Get-Attribute $newMeshRoot 'unique_id') -and (Get-Property $oldMeshRoot 'transform') -ceq (Get-Property $newMeshRoot 'transform') -and (Get-Attribute $newMeshRoot 'parent') -eq '.'
    Add-Check "${materialLabel}：世界单体根身份与碰撞保持原样" (($oldIdentity | ConvertTo-Json -Compress) -ceq ($newIdentity | ConvertTo-Json -Compress) -and (Same-Sections $oldCollision $newCollision) -and $worldVisualBindingValid -and $worldMeshPlacementPreserved) @($oldWorldPath, $newWorldPath) @{
        '原身份' = $oldIdentity; '现身份' = $newIdentity; '碰撞逐段一致' = Same-Sections $oldCollision $newCollision
        '共享模型绑定实际路径正确且无旧世界唯一标识' = $worldVisualBindingValid
        '模型挂点变换父路径及唯一标识原样' = $worldMeshPlacementPreserved
        '现模型挂点原文' = $newMeshRoot.Text
    }
    $groupRelativePath = "main-autolysis\scenes\prefabs\prefab_raw_materials\rm_${materialName}_group_0.tscn"
    $oldGroupPath = Join-Path $baselinePath $groupRelativePath
    $newGroupPath = Join-Path $workspacePath $groupRelativePath
    $oldGroup = @(Read-Scene $oldGroupPath)
    $newGroup = @(Read-Scene $newGroupPath)
    $oldTrayNodes = @($oldGroup | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'type') -eq 'MeshInstance3D' })
    $trayName = Get-Attribute $oldTrayNodes[0] 'name'
    $oldBottles = @($oldGroup | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'parent') -eq $trayName })
    $newBottles = @($newGroup | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'parent') -eq $trayName })
    $oldTray = @($oldGroup | Where-Object { $_.Kind -eq 'sub_resource' -or ($_.Kind -eq 'node' -and (Get-Attribute $_ 'name') -eq $trayName) -or ($_.Kind -eq 'ext_resource' -and (Get-Attribute $_ 'type') -eq 'Material') })
    $newTray = @($newGroup | Where-Object { $_.Kind -eq 'sub_resource' -or ($_.Kind -eq 'node' -and (Get-Attribute $_ 'name') -eq $trayName) -or ($_.Kind -eq 'ext_resource' -and (Get-Attribute $_ 'type') -eq 'Material') })
    $oldGroupIdentity = Get-NodeIdentity $oldGroup
    $newGroupIdentity = Get-NodeIdentity $newGroup
    $visualReference = @($newGroup | Where-Object { $_.Kind -eq 'ext_resource' -and (Get-Attribute $_ 'path') -eq "res://main-autolysis/scenes/prefabs/prefab_raw_materials/visuals/rm_${materialName}_visual.tscn" })
    Add-Check "${materialLabel}：组内四瓶及托盘外观保持原样" ($oldBottles.Count -eq 4 -and $newBottles.Count -eq 4 -and (Same-Sections $oldBottles $newBottles) -and (Same-Sections $oldTray $newTray) -and ($oldGroupIdentity | ConvertTo-Json -Compress) -ceq ($newGroupIdentity | ConvertTo-Json -Compress) -and $visualReference.Count -eq 1 -and (Get-Attribute $visualReference[0] 'uid') -eq '') @($oldGroupPath, $newGroupPath, $visualPath) @{
        '旧四瓶节点' = @($oldBottles | ForEach-Object Text); '现四瓶节点' = @($newBottles | ForEach-Object Text)
        '四瓶变换名称父路径唯一标识均逐段一致' = Same-Sections $oldBottles $newBottles
        '托盘节点与内嵌资源逐段一致' = Same-Sections $oldTray $newTray
        '原身份' = $oldGroupIdentity; '现身份' = $newGroupIdentity
        '共享纯显示资源引用' = @($visualReference | ForEach-Object Text)
        '旧世界场景唯一标识已从替换后的纯显示引用清除' = $visualReference.Count -eq 1 -and (Get-Attribute $visualReference[0] 'uid') -eq ''
    }
}

$shelfRelativePath = 'main-autolysis\scenes\prefabs\prefab_place_shelf\place_shelf_workroom_rm_0.tscn'
$oldShelfPath = Join-Path $baselinePath $shelfRelativePath
$newShelfPath = Join-Path $workspacePath $shelfRelativePath
$oldShelf = @(Read-Scene $oldShelfPath)
$newShelf = @(Read-Scene $newShelfPath)
$oldSlots = @($oldShelf | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'parent') -eq 'rm_place_shelf_slots' })
$newSlots = @($newShelf | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'parent') -eq 'rm_place_shelf_slots' })
$oldShelfVisual = @($oldShelf | Where-Object { (($_.Kind -eq 'ext_resource') -and (Get-Attribute $_ 'type') -eq 'Material') -or ($_.Kind -eq 'sub_resource' -and (Get-Attribute $_ 'type') -ne 'BoxShape3D') -or ($_.Kind -eq 'node' -and ((Get-Attribute $_ 'name') -in @('mesh', 'rm_place_shelf_slots') -or (Get-Attribute $_ 'parent') -eq 'mesh')) })
$newShelfVisual = @($newShelf | Where-Object { (($_.Kind -eq 'ext_resource') -and (Get-Attribute $_ 'type') -eq 'Material') -or ($_.Kind -eq 'sub_resource' -and (Get-Attribute $_ 'type') -ne 'BoxShape3D') -or ($_.Kind -eq 'node' -and ((Get-Attribute $_ 'name') -in @('mesh', 'rm_place_shelf_slots') -or (Get-Attribute $_ 'parent') -eq 'mesh')) })
$oldShelfIdentity = Get-NodeIdentity $oldShelf
$newShelfIdentity = Get-NodeIdentity $newShelf
Add-Check '原药架36槽位及视觉根变换保持原样' ($oldSlots.Count -eq 36 -and $newSlots.Count -eq 36 -and (Same-Sections $oldSlots $newSlots) -and (Same-Sections $oldShelfVisual $newShelfVisual) -and ($oldShelfIdentity | ConvertTo-Json -Compress) -ceq ($newShelfIdentity | ConvertTo-Json -Compress)) @($oldShelfPath, $newShelfPath) @{
    '旧槽位数' = $oldSlots.Count; '现槽位数' = $newSlots.Count; '所有槽位全文逐段一致' = Same-Sections $oldSlots $newSlots
    '模型材质几何及槽位容器全文一致' = Same-Sections $oldShelfVisual $newShelfVisual
    '原身份' = $oldShelfIdentity; '现身份' = $newShelfIdentity
    '槽位实际文本' = @($newSlots | ForEach-Object Text)
}

$warehouseRelativePath = 'main-autolysis\scenes\prefabs\prefab_furnitures\store_shelf_warehouse_0.tscn'
$oldWarehousePath = Join-Path $baselinePath $warehouseRelativePath
$newWarehousePath = Join-Path $workspacePath $warehouseRelativePath
$oldWarehouse = @(Read-Scene $oldWarehousePath)
$newWarehouse = @(Read-Scene $newWarehousePath)
$oldNonCollision = @($oldWarehouse | Where-Object { (Get-Attribute $_ 'type') -notin @('BoxShape3D', 'CollisionShape3D') })
$newNonCollision = @($newWarehouse | Where-Object { (Get-Attribute $_ 'type') -notin @('BoxShape3D', 'CollisionShape3D') })
$oldWarehouseCollisions = @($oldWarehouse | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'type') -eq 'CollisionShape3D' })
$newWarehouseCollisions = @($newWarehouse | Where-Object { $_.Kind -eq 'node' -and (Get-Attribute $_ 'type') -eq 'CollisionShape3D' })
$oldCollisionIdentity = Get-Attribute $oldWarehouseCollisions[0] 'unique_id'
$retainedCollision = @($newWarehouseCollisions | Where-Object { (Get-Attribute $_ 'name') -eq (Get-Attribute $oldWarehouseCollisions[0] 'name') })
Add-Check '仓库架仅将整体碰撞拆成8个结构碰撞其余全部原样' ($oldWarehouseCollisions.Count -eq 1 -and $newWarehouseCollisions.Count -eq 8 -and (Same-Sections $oldNonCollision $newNonCollision) -and $retainedCollision.Count -eq 1 -and (Get-Attribute $retainedCollision[0] 'unique_id') -eq $oldCollisionIdentity) @($oldWarehousePath, $newWarehousePath) @{
    '旧碰撞节点数' = $oldWarehouseCollisions.Count; '现碰撞节点数' = $newWarehouseCollisions.Count
    '新增碰撞节点数' = $newWarehouseCollisions.Count - $oldWarehouseCollisions.Count
    '非碰撞全部场景段含场景根身份视觉与材质逐段一致' = Same-Sections $oldNonCollision $newNonCollision
    '原碰撞节点唯一标识保留' = $oldCollisionIdentity
    '当前8碰撞实际文本' = @($newWarehouseCollisions | ForEach-Object Text)
}

foreach ($assetPair in @(
    @('D:\cogito\assets\textures\ui\inventory\degauss_inventory_slot_border.png', 'D:\autolysis\main-autolysis\assets\ui\inventory\degauss_inventory_slot_border.png'),
    @('D:\cogito\addons\cogito\Assets\Audio\Kenney\UiAudio\mouseclick1.ogg', 'D:\autolysis\main-autolysis\assets\ui\inventory\mouseclick1.ogg')
)) {
    $sourceHash = (Get-FileHash -LiteralPath $assetPair[0] -Algorithm SHA256).Hash
    $copiedHash = (Get-FileHash -LiteralPath $assetPair[1] -Algorithm SHA256).Hash
    Add-Check '参考资产复制前后字节内容一致' ($sourceHash -ceq $copiedHash) $assetPair @{
        '原资产校验值' = $sourceHash; '迁入资产校验值' = $copiedHash
    }
}

$failedChecks = @($checks | Where-Object { -not $_['通过'] })
$report = [ordered]@{
    '说明' = '仅文件与场景文本审计；未运行引擎，未修改生产代码。校验算法为安全散列算法256位。'
    '生成时间' = [DateTimeOffset]::Now.ToString('o')
    '工作区精确路径' = $workspacePath; '基线精确路径' = $baselinePath; '检查脚本精确路径' = $PSCommandPath
    '覆盖边界' = '已有文件保护范围以实施前实际保存的基线副本为准；模型审计比较场景全部网格属性、材质引用与节点变换，不替代实际渲染验收。'
    '基线文件总数' = $baselineRecords.Count; '变化文件数' = $changedFiles.Count; '缺失文件数' = $missingFiles.Count; '保持原样文件数' = $unchangedFiles.Count
    '变化文件' = $changedFiles.ToArray(); '缺失文件' = $missingFiles.ToArray(); '保持原样文件' = $unchangedFiles.ToArray()
    '检查数量' = $checks.Count; '失败数量' = $failedChecks.Count; '检查' = $checks.ToArray()
}
$report | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Output ('基线文件={0}；变化={1}；缺失={2}；原样={3}；检查={4}；失败={5}' -f $baselineRecords.Count, $changedFiles.Count, $missingFiles.Count, $unchangedFiles.Count, $checks.Count, $failedChecks.Count)
foreach ($failedCheck in $failedChecks) { Write-Output ('失败：' + $failedCheck['项目']) }
if ($failedChecks.Count -gt 0) { exit 1 }
