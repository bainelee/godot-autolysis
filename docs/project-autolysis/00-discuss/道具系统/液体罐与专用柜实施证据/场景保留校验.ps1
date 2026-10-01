# 逐段比较实施前快照与当前资源，保存实际比较结果。
$projectPath = 'D:\autolysis'
$baselineRoot = Join-Path $PSScriptRoot 'baseline'
$tankRelative = 'main-autolysis\scenes\prefabs\prefab_machines\luquid_tank_0.tscn'
$cabinetRelative = 'main-autolysis\scenes\prefabs\prefab_place_shelf\cabinet_workroom_0.tscn'
$visualRelative = 'main-autolysis\scenes\prefabs\prefab_machines\visuals\liquid_tank_visual.tscn'
$tankBefore = [IO.File]::ReadAllText((Join-Path $baselineRoot $tankRelative))
$tankAfter = [IO.File]::ReadAllText((Join-Path $projectPath $tankRelative))
$cabinetBefore = [IO.File]::ReadAllText((Join-Path $baselineRoot $cabinetRelative))
$cabinetAfter = [IO.File]::ReadAllText((Join-Path $projectPath $cabinetRelative))
$visualAfter = [IO.File]::ReadAllText((Join-Path $projectPath $visualRelative))
$records = [Collections.Generic.List[object]]::new()

function Get-Section([string]$source, [string]$prefix) {
    $sections = [regex]::Split($source.Replace("`r`n", "`n"), '(?m)(?=^\[(?:gd_scene|ext_resource|sub_resource|node)\b)')
    foreach ($section in $sections) { if ($section.StartsWith($prefix)) { return $section.Trim() } }
    throw ('缺少所需资源段：' + $prefix)
}

function Record-Equality([string]$label, [string]$before, [string]$after) {
    $records.Add([pscustomobject]@{项目=$label; 通过=($before -ceq $after); 比较前=$before; 比较后=$after})
}

foreach ($pair in @(@('液体罐',$tankBefore,$tankAfter), @('专用柜',$cabinetBefore,$cabinetAfter))) {
    $beforeUid = [regex]::Match($pair[1], '^\[gd_scene[^\r\n]* uid="([^"]+)"').Groups[1].Value
    $afterUid = [regex]::Match($pair[2], '^\[gd_scene[^\r\n]* uid="([^"]+)"').Groups[1].Value
    Record-Equality ($pair[0] + '场景唯一标识') $beforeUid $afterUid
}

Record-Equality '液体罐碰撞形状资源' (Get-Section $tankBefore '[sub_resource type="BoxShape3D"') (Get-Section $tankAfter '[sub_resource type="BoxShape3D"')
Record-Equality '液体罐碰撞节点与局部偏移' (Get-Section $tankBefore '[node name="CollisionShape3D"') (Get-Section $tankAfter '[node name="CollisionShape3D"')
foreach ($prefix in @('[sub_resource type="Animation" id="Animation_cabinet_door_left_reset"', '[sub_resource type="Animation" id="Animation_cabinet_door_left_open"', '[sub_resource type="AnimationLibrary"', '[sub_resource type="ConcavePolygonShape3D"', '[sub_resource type="BoxShape3D" id="BoxShape3D_o063d"', '[node name="CollisionShape3D" type="CollisionShape3D" parent="."', '[node name="CollisionShape3D" type="CollisionShape3D" parent="cabinet_door_left_root"', '[node name="luquid_tank_slot_0"', '[node name="luquid_tank_slot_1"')) {
    Record-Equality '专用柜已有动画、形状或锚点资源段' (Get-Section $cabinetBefore $prefix) (Get-Section $cabinetAfter $prefix)
}

$tankSections = [regex]::Split($tankBefore.Replace("`r`n", "`n"), '(?m)(?=^\[(?:ext_resource|sub_resource|node)\b)')
foreach ($section in $tankSections) {
    if ($section.StartsWith('[sub_resource type="BoxMesh"') -or $section.StartsWith('[sub_resource type="StandardMaterial3D"')) {
        $prefix = $section.Substring(0, $section.IndexOf("`n")).TrimEnd(']')
        Record-Equality '纯显示保留罐的网格或材质资源' $section.Trim() (Get-Section $visualAfter $prefix)
    }
    if ($section.StartsWith('[node name="MeshInstance3D')) {
        $prefix = [regex]::Match($section, '^\[node name="[^"]+" type="[^"]+"').Value
        $beforeBody = $section.Substring($section.IndexOf("`n") + 1).Trim()
        $afterSection = Get-Section $visualAfter $prefix
        $afterBody = $afterSection.Substring($afterSection.IndexOf("`n") + 1).Trim()
        Record-Equality '纯显示保留罐的网格节点局部变换与材质引用' $beforeBody $afterBody
    }
}

$failures = @($records | Where-Object { -not $_.通过 }).Count
$report = [pscustomobject]@{检查数=$records.Count; 失败数=$failures; 记录=$records}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '场景保留校验.json') -Encoding utf8
Write-Output ('场景保留比较数：' + $records.Count + '；失败：' + $failures)
if ($failures -gt 0) { $records | Where-Object { -not $_.通过 } | Format-List; exit 1 }
