param([string]$ProjectRoot = 'D:\autolysis')

$ErrorActionPreference = 'Stop'
$archiveProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$archiveEvidenceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$archiveEncoding = [Text.UTF8Encoding]::new($false)
if (-not $archiveEvidenceRoot.StartsWith($archiveProjectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '证据目录必须位于本工程内。'
}

# 每个检查只选择一个有效版本；最后修改影响的三项旧回归替换初次记录。
$archiveRecords = @()
$archiveInitial = Get-Content -LiteralPath (Join-Path $archiveEvidenceRoot '既有回归\初次\检查汇总.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($archiveRecord in $archiveInitial) {
    $archiveRelative = '既有回归/初次/' + $archiveRecord.检查 + '.json'
    if ($archiveRecord.检查 -in @('telephone-device', 'handset-inventory', 'telephone-commit-observers')) {
        $archiveRelative = '最终受影响复验/' + $archiveRecord.检查 + '.json'
        $archiveRecord = Get-Content -LiteralPath (Join-Path $archiveEvidenceRoot $archiveRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $archiveRecord | Add-Member -NotePropertyName '采用证据' -NotePropertyValue $archiveRelative -Force
    $archiveRecords += $archiveRecord
}
$archiveSpecialPaths = @(
    '时序探针/授权环境/timing-probe.json',
    '专项验收/铃声中途采样修正/telephone-ring-start.json',
    '对话配置/授权环境/对话配置核验.json',
    '专项验收/初次/dialogue-system.json',
    '专项验收/实际处理时长补验/dialogue-boundaries.json',
    '字幕可见性边界/同步离树复验/字幕可见性边界.json',
    '专项验收/铃声中途采样修正/telephone-call.json',
    '电话边界专项/最后渐隐完成锁/电话来电边界专项.json',
    '专项验收/通话移动与容量初验/telephone-call-gameplay.json',
    '专项验收/全部归还边界补验/telephone-return-lock-boundaries.json',
    '主场景入口/初次/telephone-call-entry.json',
    '最终受影响复验/telephone-runtime-wait.json',
    '最终受影响复验/telephone-runtime-reject.json'
)
foreach ($archiveRelative in $archiveSpecialPaths) {
    $archiveRecord = Get-Content -LiteralPath (Join-Path $archiveEvidenceRoot $archiveRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
    $archiveRecord | Add-Member -NotePropertyName '采用证据' -NotePropertyValue $archiveRelative -Force
    $archiveRecords += $archiveRecord
}
foreach ($archiveRecord in $archiveRecords) {
    if (-not $archiveRecord.通过 -or $archiveRecord.退出码 -ne 0 -or @($archiveRecord.非预期错误).Count -ne 0) {
        throw ('所选记录未通过：' + $archiveRecord.采用证据)
    }
    if ('--headless' -notin $archiveRecord.命令参数) { throw '所选引擎检查未使用无图形参数。' }
}

$archiveIsolation = @()
foreach ($archiveName in @('基线新进程', '仅改原文新进程', '中文修改新进程')) {
    $archiveRelative = '文本文件隔离/' + $archiveName + '.json'
    $archiveRecord = Get-Content -LiteralPath (Join-Path $archiveEvidenceRoot $archiveRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $archiveRecord.通过 -or $archiveRecord.退出码 -ne 0 -or '--headless' -notin $archiveRecord.参数) { throw '文本隔离记录未通过。' }
    $archiveRecord | Add-Member -NotePropertyName '采用证据' -NotePropertyValue $archiveRelative -Force
    $archiveRecord | Add-Member -NotePropertyName '通过断言数' -NotePropertyValue 1 -Force
    $archiveIsolation += $archiveRecord
}
$archiveImport = Get-Content -LiteralPath (Join-Path $archiveEvidenceRoot '最终受影响复验/import.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $archiveImport.通过 -or $archiveImport.退出码 -ne 0) { throw '最终导入未通过。' }
$archiveSummary = [ordered]@{
    生成时间 = (Get-Date -Format o)
    通过 = $true
    统计规则 = '每项只计一个采用版本；最终三项旧回归替换初次记录；失败与重复运行不累计。文本隔离另计三项真实新进程检查。'
    引擎检查项数 = $archiveRecords.Count
    引擎通过断言数 = ($archiveRecords | Measure-Object -Property 通过断言数 -Sum).Sum
    文本隔离检查项数 = $archiveIsolation.Count
    合计通过断言数 = (($archiveRecords | Measure-Object -Property 通过断言数 -Sum).Sum + $archiveIsolation.Count)
    引擎导入 = $archiveImport
    引擎检查 = $archiveRecords
    文本隔离 = $archiveIsolation
    图形 = '未执行'
    实际试听 = '未执行'
    原生输入操作 = '未执行'
    引擎内部输入 = '实际物理测试键、正式菜单动作及移动输入由专项记录验证'
}
[IO.File]::WriteAllText((Join-Path $archiveEvidenceRoot '最终检查状态.json'), ($archiveSummary | ConvertTo-Json -Depth 8), $archiveEncoding)

$archiveTracked = @(
    'project.godot',
    'main-autolysis/player/autolysis_player.gd',
    'main-autolysis/player/autolysis_player.tscn',
    'main-autolysis/player/components/autolysis_inventory_controller.gd',
    'main-autolysis/player/tests/handset_inventory_test.gd',
    'main-autolysis/player/tests/telephone_device_test.gd',
    'main-autolysis/player/tests/run_telephone_verification.ps1',
    'main-autolysis/scenes/01-autolysis-test.tscn',
    'main-autolysis/scenes/prefabs/prefab_machines/machine_telephone_0.tscn',
    'main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_telephone.gd'
)
$archiveNewRoots = @(
    'main-autolysis/player/tests',
    'main-autolysis/player/components/autolysis_telephone_call_test_trigger.gd',
    'main-autolysis/player/components/autolysis_telephone_call_test_trigger.gd.uid',
    'main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_telephone_call_controller.gd',
    'main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_telephone_call_controller.gd.uid',
    'main-autolysis/systems/dialogue-system',
    'main-autolysis/systems/runtime-session',
    'main-autolysis/ui/dialogue'
)
Push-Location -LiteralPath $archiveProjectRoot
try {
    $archiveNewFiles = @(git -c core.quotepath=false ls-files --others --exclude-standard -- @archiveNewRoots)
    $archiveFiles = @(@($archiveTracked) + @($archiveNewFiles) | Sort-Object -Unique)
    $archiveSnapshotRoot = Join-Path $archiveEvidenceRoot '最终源码'
    if (Test-Path -LiteralPath $archiveSnapshotRoot) { throw '最终源码快照已存在，禁止覆盖。' }
    New-Item -ItemType Directory -Path $archiveSnapshotRoot | Out-Null
    $archiveHashes = @()
    foreach ($archiveRelative in $archiveFiles) {
        $archiveSource = [IO.Path]::GetFullPath((Join-Path $archiveProjectRoot $archiveRelative))
        if (-not $archiveSource.StartsWith($archiveProjectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '来源超出工程。' }
        $archiveDestination = [IO.Path]::GetFullPath((Join-Path $archiveSnapshotRoot $archiveRelative))
        if (-not $archiveDestination.StartsWith($archiveSnapshotRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '快照路径超出目标。' }
        New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($archiveDestination)) | Out-Null
        Copy-Item -LiteralPath $archiveSource -Destination $archiveDestination
        $archiveHashes += [pscustomobject]@{路径=$archiveRelative; 散列=(Get-FileHash -LiteralPath $archiveSource -Algorithm SHA256).Hash; 快照散列=(Get-FileHash -LiteralPath $archiveDestination -Algorithm SHA256).Hash}
    }
    $archiveAudioPaths = @('main-autolysis/assets/audio/sound_fx/phone/sfx_phone_default_0.wav', 'main-autolysis/assets/audio/sound_fx/phone/sfx_phone_default_0.wav.import')
    $archiveAudioPaths += @(Get-ChildItem -LiteralPath 'main-autolysis/assets/audio/speech/chat_0' -File | ForEach-Object {$_.FullName.Substring($archiveProjectRoot.Length + 1).Replace('\','/')})
    foreach ($archiveRelative in $archiveAudioPaths) {
        $archiveHashes += [pscustomobject]@{路径=$archiveRelative; 散列=(Get-FileHash -LiteralPath (Join-Path $archiveProjectRoot $archiveRelative) -Algorithm SHA256).Hash; 快照散列='保留原资产，记录散列'}
    }
    [IO.File]::WriteAllText((Join-Path $archiveEvidenceRoot '最终文件散列.json'), ($archiveHashes | ConvertTo-Json -Depth 4), $archiveEncoding)
    $archiveDiff = @(git -c core.quotepath=false diff -- @archiveTracked)
    [IO.File]::WriteAllText((Join-Path $archiveEvidenceRoot '最终已跟踪修改.diff'), ($archiveDiff -join "`n"), $archiveEncoding)
    $archiveStatus = @(git -c core.quotepath=false status --short)
    [IO.File]::WriteAllText((Join-Path $archiveEvidenceRoot '最终工作区.txt'), ($archiveStatus -join "`n"), $archiveEncoding)
    $archiveDiffCheck = @(git diff --check 2>&1)
    $archiveDiffExit = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $archiveEvidenceRoot '差异空白检查.json'), ([ordered]@{退出码=$archiveDiffExit; 通过=($archiveDiffExit -eq 0); 输出=@($archiveDiffCheck | ForEach-Object { $_.ToString() })} | ConvertTo-Json -Depth 4), $archiveEncoding)
    if ($archiveDiffExit -ne 0) { throw '差异空白检查未通过。' }
} finally { Pop-Location }
Write-Output ('通过：最终采用' + $archiveRecords.Count + '项引擎检查、' + $archiveIsolation.Count + '项文本隔离，合计' + $archiveSummary.合计通过断言数 + '条断言；源码和散列已保存。')
