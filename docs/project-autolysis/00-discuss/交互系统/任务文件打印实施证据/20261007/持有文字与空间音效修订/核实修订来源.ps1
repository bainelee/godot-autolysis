param([string]$SnapshotName = '实施后')

$ErrorActionPreference = 'Stop'
$projectRoot = 'D:\autolysis'
$before = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '实施前/来源散列.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$after = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot ($SnapshotName + '/来源散列.json')) -Raw -Encoding UTF8 | ConvertFrom-Json)
$beforeMap = @{}
$afterMap = @{}
foreach ($entry in $before) { $beforeMap[$entry.文件.Replace('\','/')] = $entry }
foreach ($entry in $after) { $afterMap[$entry.文件.Replace('\','/')] = $entry }
$comparisons = @()
$drift = @()
foreach ($relative in @(@($beforeMap.Keys) + @($afterMap.Keys) | Sort-Object -Unique)) {
    $oldHash = if ($beforeMap.ContainsKey($relative)) {$beforeMap[$relative].散列} else {''}
    $newHash = if ($afterMap.ContainsKey($relative)) {$afterMap[$relative].散列} else {''}
    $status = if (-not $oldHash) {'新增'} elseif (-not $newHash) {'删除'} elseif ($oldHash -eq $newHash) {'相同'} else {'修改'}
    $comparisons += [pscustomobject]@{文件=$relative;本轮实施前散列=$oldHash;本轮实施后散列=$newHash;状态=$status}
    if ($newHash) {
        $actualPath = Join-Path $projectRoot $relative
        $actualHash = if (Test-Path -LiteralPath $actualPath) {(Get-FileHash -LiteralPath $actualPath -Algorithm SHA256).Hash} else {''}
        if ($actualHash -ne $newHash) { $drift += [pscustomobject]@{文件=$relative;快照散列=$newHash;当前散列=$actualHash} }
    }
}
$comparisons | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '修订来源前后对照.json') -Encoding UTF8
$audio = @($comparisons | Where-Object {$_.文件 -like 'main-autolysis/assets/audio/sound_fx/phone/*.wav'})
$audio | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '原电话音频字节保留核查.json') -Encoding UTF8
$result = [pscustomobject]@{
    时间=(Get-Date -Format o);通过=($drift.Count -eq 0 -and @($audio | Where-Object {$_.状态 -ne '相同'}).Count -eq 0)
    本轮实施前文件数=$before.Count;本轮实施后文件数=$after.Count
    修改数=@($comparisons | Where-Object {$_.状态 -eq '修改'}).Count
    新增数=@($comparisons | Where-Object {$_.状态 -eq '新增'}).Count
    删除数=@($comparisons | Where-Object {$_.状态 -eq '删除'}).Count
    原电话音频数=$audio.Count;快照后源码变化=$drift
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '最终源码冻结核查.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 5
if (-not $result.通过) { throw '修订来源对照或快照后源码冻结核查失败。' }
