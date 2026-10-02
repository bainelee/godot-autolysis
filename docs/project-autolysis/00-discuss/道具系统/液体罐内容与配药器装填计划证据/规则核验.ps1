$ErrorActionPreference = 'Stop'
$taskProjectRoot = 'D:\autolysis'
$taskEvidenceRoot = $PSScriptRoot
$taskCulture = [Globalization.CultureInfo]::InvariantCulture
$taskHandleSource = Get-Content -LiteralPath (Join-Path $taskProjectRoot 'main-autolysis\scenes\prefabs\prefab_machines\scripts\autolysis_blend_handle.gd') -Raw
$taskSceneSource = Get-Content -LiteralPath (Join-Path $taskProjectRoot 'main-autolysis\scenes\prefabs\prefab_machines\machine_blend_0.tscn') -Raw
$taskRecords = [Collections.Generic.List[string]]::new()

function Read-SourceNumber([string]$source, [string]$pattern) {
    $match = [regex]::Match($source, $pattern)
    if (-not $match.Success) { throw '正式文件参数读取失败。' }
    return [decimal]::Parse($match.Groups[1].Value, $taskCulture)
}

function Assert-Near([decimal]$actual, [decimal]$expected, [decimal]$tolerance, [string]$label) {
    if ([Math]::Abs($actual - $expected) -gt $tolerance) { throw "$label 核验失败。" }
    $taskRecords.Add("通过：$label；实际值=$($actual.ToString($taskCulture))")
}

function Format-RawMaterials([string[]]$slotIds) {
    $orderedIds = [Collections.Generic.List[string]]::new()
    $counts = @{}
    $names = @{ caffeine = '咖啡因'; sodium_benzoate = '苯甲酸钠' }
    foreach ($rawId in $slotIds) {
        if ([string]::IsNullOrEmpty($rawId)) { continue }
        if (-not $names.ContainsKey($rawId)) { throw '示例存在未知原药。' }
        if (-not $counts.ContainsKey($rawId)) {
            $orderedIds.Add($rawId)
            $counts[$rawId] = 0
        }
        $counts[$rawId] += 1
    }
    $labels = foreach ($rawId in $orderedIds) {
        if ($counts[$rawId] -gt 1) { "$($names[$rawId])*$($counts[$rawId])" } else { $names[$rawId] }
    }
    return $labels -join '、'
}

$taskRecords.Add('液体罐内容与配药器装填计划规则核验')
$taskRecords.Add('性质：正式参数读取、算术核验与文档显示示例；未运行引擎。')
$taskRecords.Add('源文件：正式配药器场景与正式拉杆脚本。')
$taskTop = Read-SourceNumber $taskHandleSource 'const\s+TOP_Y:\s+float\s*=\s*([-\d.]+)'
$taskBottom = Read-SourceNumber $taskHandleSource 'const\s+BOTTOM_Y:\s+float\s*=\s*([-\d.]+)'
$taskReturnSeconds = Read-SourceNumber $taskHandleSource 'const\s+RETURN_SECONDS:\s+float\s*=\s*([-\d.]+)'
$taskRatio = Read-SourceNumber $taskSceneSource '(?m)^mouse_to_handle_ratio\s*=\s*([-\d.]+)'
$taskRestrictedBottom = [decimal]'0.08'
$taskRestrictedRatio = $taskRatio / 2
$taskRestrictedTravel = $taskTop - $taskRestrictedBottom
$taskReturnSpeed = ($taskTop - $taskBottom) / $taskReturnSeconds
$taskRestrictedMouseTravel = $taskRestrictedTravel / $taskRestrictedRatio
$taskRestrictedReturnSeconds = $taskRestrictedTravel / $taskReturnSpeed

Assert-Near $taskTop ([decimal]'0.12') ([decimal]'0.000000000001') '当前顶部'
Assert-Near $taskBottom ([decimal]'-0.12') ([decimal]'0.000000000001') '当前正常底部'
Assert-Near $taskRatio ([decimal]'0.001') ([decimal]'0.000000000001') '场景当前正常比例'
Assert-Near $taskRestrictedRatio ([decimal]'0.0005') ([decimal]'0.000000000001') '受限半比例'
Assert-Near $taskRestrictedTravel ([decimal]'0.04') ([decimal]'0.000000000001') '受限行程'
Assert-Near $taskReturnSpeed ([decimal]'1.2') ([decimal]'0.000000000001') '保留当前返回速度'
Assert-Near $taskRestrictedMouseTravel ([decimal]'80') ([decimal]'0.000000001') '到达受限下限累计有效鼠标位移'
Assert-Near $taskRestrictedReturnSeconds ([decimal]'0.0333333333333333333333333333') ([decimal]'0.000000000001') '受限满行程理论返回秒数'

$taskCases = @(
    @{ slots = @('caffeine', '', '', ''); expected = '咖啡因'; count = 1 },
    @{ slots = @('', 'sodium_benzoate', '', 'caffeine'); expected = '苯甲酸钠、咖啡因'; count = 2 },
    @{ slots = @('caffeine', 'sodium_benzoate', 'caffeine', ''); expected = '咖啡因*2、苯甲酸钠'; count = 3 },
    @{ slots = @('sodium_benzoate', 'caffeine', 'sodium_benzoate', 'caffeine'); expected = '苯甲酸钠*2、咖啡因*2'; count = 4 },
    @{ slots = @('caffeine', 'caffeine', 'caffeine', 'caffeine'); expected = '咖啡因*4'; count = 4 }
)
foreach ($taskCase in $taskCases) {
    $taskActual = Format-RawMaterials $taskCase.slots
    $taskCount = @($taskCase.slots | Where-Object { -not [string]::IsNullOrEmpty($_) }).Count
    if ($taskActual -ne $taskCase.expected -or $taskCount -ne $taskCase.count) { throw '原药显示示例核验失败。' }
    $taskRecords.Add("通过：原始条目数=$taskCount；合并显示=$taskActual")
}

$taskWaveCases = @(
    @{ flags = @($false, $false, $false, $false); level = 0; valid = $true; display = '（0，0，0，0，0）' },
    @{ flags = @($true, $false, $true, $true); level = 4; valid = $true; display = '（1，0，1，1，4）' },
    @{ flags = @($true, $true, $true, $true); level = 6; valid = $true; display = '（1，1，1，1，6）' },
    @{ flags = @($false, $false, $false, $false); level = -1; valid = $false },
    @{ flags = @($false, $false, $false, $false); level = 7; valid = $false }
)
foreach ($taskWaveCase in $taskWaveCases) {
    $taskValid = $taskWaveCase.flags.Count -eq 4 -and $taskWaveCase.level -ge 0 -and $taskWaveCase.level -le 6
    if ($taskValid -ne $taskWaveCase.valid) { throw '波形边界核验失败。' }
    if ($taskValid) {
        $taskCoordinates = @($taskWaveCase.flags | ForEach-Object { [int]$_ }) + @($taskWaveCase.level)
        $taskDisplay = '（' + ($taskCoordinates -join '，') + '）'
        if ($taskDisplay -ne $taskWaveCase.display) { throw '波形显示核验失败。' }
        $taskRecords.Add("通过：波形显示=$taskDisplay")
    } else {
        $taskRecords.Add("通过：波形第五项=$($taskWaveCase.level) 拒绝写入规则")
    }
}

$taskRecords.Add('全部文档规则核验通过。此结果不证明游戏实现或引擎验收通过。')
$taskRecords | Set-Content -LiteralPath (Join-Path $taskEvidenceRoot '规则核验记录.txt') -Encoding UTF8
$taskRecords
