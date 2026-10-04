$ErrorActionPreference = 'Stop'
$evidencePath = $PSScriptRoot
$projectPath = 'D:\autolysis'
$beforeSources = Get-Content -LiteralPath (Join-Path $evidencePath '修改前来源散列.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedChanges = @(
    'main-autolysis\scenes\prefabs\prefab_machines\scripts\autolysis_telephone.gd',
    'main-autolysis\scenes\prefabs\prefab_machines\machine_telephone_0.tscn',
    'main-autolysis\player\tests\telephone_device_test.gd',
    'main-autolysis\player\tests\telephone_dependency_audit.gd',
    'main-autolysis\player\tests\telephone_movement_test.gd'
)
$sourceRecords = foreach ($before in $beforeSources) {
    $sourcePath = [IO.Path]::GetFullPath($before.路径)
    if (-not $sourcePath.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '来源不在本项目中。' }
    $relativePath = $sourcePath.Substring($projectPath.Length + 1)
    $destination = Join-Path (Join-Path $evidencePath '修改后') $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destination
    $afterHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $changed = $before.散列 -ne $afterHash
    if ($changed -and $relativePath -notin $expectedChanges) { throw ('非本次来源出现变化：' + $relativePath) }
    [pscustomobject]@{路径=$sourcePath;修改前散列=$before.散列;修改后散列=$afterHash;本次发生变化=$changed;预期本次修改=($relativePath -in $expectedChanges)}
}
$sourceRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidencePath '修改后来源散列.json') -Encoding UTF8
$checkRecords = foreach ($folder in @('取下与依赖回归','受影响流程回归','解析与移动回归')) {
    Get-Content -LiteralPath (Join-Path (Join-Path $evidencePath $folder) '检查汇总.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}
if (@($checkRecords.检查 | Select-Object -Unique).Count -ne @($checkRecords).Count) { throw '检查存在重复，不能累计。' }
foreach ($check in $checkRecords) {
    if (-not $check.通过 -or $check.退出码 -ne 0 -or @($check.非预期错误).Count -ne 0 -or '--headless' -notin $check.命令参数) { throw ('检查未通过或不是无图形：' + $check.检查) }
}
$checkRecords | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidencePath '最终自动验收汇总.json') -Encoding UTF8
$changedFiles = @($sourceRecords | Where-Object 本次发生变化)
$unchangedFiles = @($sourceRecords | Where-Object { -not $_.本次发生变化 })
$summary = [pscustomobject]@{
    检查数=@($checkRecords).Count
    通过断言数=($checkRecords | Measure-Object -Property 通过断言数 -Sum).Sum
    全部检查退出零且非预期错误为空=$true
    全部引擎检查为无图形=$true
    来源快照数量=@($sourceRecords).Count
    本次修改数量=$changedFiles.Count
    保持散列一致数量=$unchangedFiles.Count
    本次修改路径=$changedFiles.路径
    保持散列一致路径=$unchangedFiles.路径
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidencePath '最终核查汇总.json') -Encoding UTF8
foreach ($relativePath in $expectedChanges) {
    $beforePath = Join-Path (Join-Path $evidencePath '修改前') $relativePath
    $afterPath = Join-Path $projectPath $relativePath
    $diffPath = Join-Path $evidencePath (($relativePath.Replace('\','_')) + '.diff')
    & git -c core.autocrlf=false diff --no-index -- $beforePath $afterPath | Set-Content -LiteralPath $diffPath -Encoding UTF8
    if ($LASTEXITCODE -notin @(0,1)) { throw ('差异读取失败：' + $relativePath) }
    $whitespaceOutput = & git -c core.autocrlf=false diff --no-index --check -- $beforePath $afterPath
    if ($LASTEXITCODE -notin @(0,1) -or $whitespaceOutput) { throw ('差异空白检查失败：' + $relativePath) }
}
& git -c core.autocrlf=false diff --check
if ($LASTEXITCODE -ne 0) { throw '工作区差异空白检查失败。' }
$summary | ConvertTo-Json -Depth 4
