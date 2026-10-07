param(
    [string]$EvidenceRoot = '',
    [string[]]$Checks = @()
)

# 本次修订只运行无图形检查，不提供图形或原生输入选项。
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$runner = Join-Path $projectRoot 'main-autolysis\systems\item-system\tests\run_item_check.ps1'
if (-not $EvidenceRoot) {
    $EvidenceRoot = Join-Path $projectRoot ('docs\project-autolysis\00-discuss\交互系统\任务文件打印实施证据\20261007\持有文字与空间音效修订\复验-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if ((Test-Path -LiteralPath $EvidenceRoot) -and @(Get-ChildItem -LiteralPath $EvidenceRoot -Force).Count -gt 0) {
    throw '证据目录非空，请指定新目录以保留历史运行。'
}
$playerTests = 'res://main-autolysis/player/tests/'
$itemTests = 'res://main-autolysis/systems/item-system/tests/'
$cases = @(
    @{Name='导入解析'; Import=$true},
    @{Name='手持文字'; Script=$playerTests+'quest_held_text_test.gd'},
    @{Name='数据纸面'; Script='res://main-autolysis/systems/quest-print-system/tests/quest_paper_data_view_test.gd'},
    @{Name='打印时序'; Script='res://main-autolysis/systems/quest-print-system/tests/quest_machine_behavior_test.gd'},
    @{Name='逐行打印音效'; Script='res://main-autolysis/systems/quest-print-system/tests/quest_machine_audio_test.gd'},
    @{Name='主场景输入'; Script=$playerTests+'quest_print_main_test.gd'},
    @{Name='聚焦取纸'; Script=$playerTests+'quest_paper_inventory_test.gd'},
    @{Name='展示释放边界'; Script=$playerTests+'quest_display_release_probe.gd'},
    @{Name='机器空间音效'; Script=$playerTests+'machine_spatial_audio_test.gd'; FixedFps=0},
    @{Name='道具回归'; Script=$itemTests+'item_system_test.gd'},
    @{Name='胶囊显示回归'; Script=$itemTests+'capsule_data_behavior_test.gd'},
    @{Name='直接交互回归'; Script=$playerTests+'direct_interaction_test.gd'},
    @{Name='组件迁移回归'; Script=$playerTests+'component_migration_test.gd'},
    @{Name='聚焦回归'; Script=$playerTests+'focus_interaction_test.gd'},
    @{Name='电话持物互斥回归'; Script=$playerTests+'telephone_device_test.gd'},
    @{Name='电话呼叫回归'; Script=$playerTests+'telephone_call_test.gd'; FixedFps=0},
    @{Name='电话测试入口回归'; Script=$playerTests+'telephone_call_entry_test.gd'; FixedFps=0},
    @{Name='电话运行机会回归'; Script=$playerTests+'telephone_runtime_once_test.gd'; FixedFps=0},
    @{Name='电话运行拒绝回归'; Script=$playerTests+'telephone_runtime_once_test.gd'; FixedFps=0; Arguments=@('--reject-request')},
    @{Name='电话内部输入回归'; Script=$playerTests+'telephone_input_test.gd'},
    @{Name='听筒显示回归'; Script=$playerTests+'telephone_handset_view_test.gd'},
    @{Name='持筒移动回归'; Script=$playerTests+'telephone_movement_test.gd'},
    @{Name='通话移动回归'; Script=$playerTests+'telephone_call_gameplay_test.gd'; FixedFps=0},
    @{Name='电话显示提交回归'; Script=$playerTests+'telephone_display_entry_audit.gd'},
    @{Name='电话呼叫边界回归'; Script=$playerTests+'telephone_call_boundary_test.gd'; FixedFps=0},
    @{Name='电话归还锁回归'; Script=$playerTests+'telephone_return_lock_boundary_test.gd'; FixedFps=0},
    @{Name='共享对白回归'; Script=$playerTests+'dialogue_system_test.gd'; FixedFps=0},
    @{Name='对白边界回归'; Script=$playerTests+'dialogue_boundary_test.gd'; FixedFps=0},
    @{Name='对白可见性回归'; Script='res://main-autolysis/systems/dialogue-system/tests/dialogue_visibility_boundary_test.gd'; FixedFps=0},
    @{Name='对白配置回归'; Script='res://main-autolysis/systems/dialogue-system/tests/dialogue_configuration_check.gd'; FixedFps=0}
)
$unknown = @($Checks | Where-Object {$_ -notin $cases.Name})
if ($unknown.Count -gt 0) { throw ('未知检查：' + ($unknown -join '、')) }
$selected = @($cases | Where-Object {$Checks.Count -eq 0 -or $_.Name -in $Checks})
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $EvidenceRoot '.gdignore'),'')

function Get-ProjectSourceHashes {
    $paths = @(& rg --files (Join-Path $projectRoot 'main-autolysis') -g '*.gd' -g '*.tscn' -g '*.tres' -g '*.uid' -g '*.ps1' -g '*.import' -g '*.wav' -g '*.svg')
    if ($LASTEXITCODE -ne 0) { throw '实际来源枚举失败。' }
    $paths += Join-Path $projectRoot 'project.godot'
    foreach ($path in @($paths | Sort-Object -Unique)) {
        [pscustomobject]@{文件=$path.Substring($projectRoot.Length + 1).Replace('\','/');散列=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    }
}
$startingHashes = @(Get-ProjectSourceHashes)
$startingHashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '启动前源码散列.json') -Encoding UTF8
$results = @()
foreach ($case in $selected) {
    $parameters = @{
        CheckName=$case.Name
        EvidenceRoot=$EvidenceRoot
        FixedFps=60
        TimeoutSeconds=240
        UserArguments=@('--evidence-dir', (Join-Path $EvidenceRoot $case.Name).Replace('\','/'))
    }
    if ($case.Import) { $parameters.Import = $true }
    else { $parameters.ScriptPath = $case.Script }
    if ($case.ContainsKey('FixedFps')) { $parameters.FixedFps = $case.FixedFps }
    if ($case.ContainsKey('Arguments')) { $parameters.UserArguments += $case.Arguments }
    Write-Output ('开始无图形检查：' + $case.Name)
    & $runner @parameters | Out-File -LiteralPath (Join-Path $EvidenceRoot ($case.Name + '.执行器.log')) -Encoding UTF8
    $recordPath = Join-Path $EvidenceRoot ($case.Name + '.json')
    $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $outputText = [IO.File]::ReadAllText((Join-Path $EvidenceRoot ($case.Name + '.stdout.log'))) + "`n" + [IO.File]::ReadAllText((Join-Path $EvidenceRoot ($case.Name + '.stderr.log')))
    $leaks = @([regex]::Matches($outputText,'(?m)^(WARNING: ObjectDB instances leaked at exit[^\r\n]*|ERROR: [0-9]+ resources still in use at exit[^\r\n]*)') | ForEach-Object {$_.Value})
    if ($leaks.Count -gt 0) {
        $record.通过 = $false
        $record.非预期错误 = @($record.非预期错误) + $leaks
        $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $recordPath -Encoding UTF8
    }
    $results += $record
    $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '检查汇总.json') -Encoding UTF8
    Write-Output ($case.Name + '：通过=' + $record.通过 + '，断言=' + $record.通过断言数 + '，退出码=' + $record.退出码)
    if (-not $record.通过) { throw ('检查失败，日志已保留：' + $case.Name) }
}
$endingHashes = @(Get-ProjectSourceHashes)
$endingHashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '完成后源码散列.json') -Encoding UTF8
$sourceChanges = @(Compare-Object ($startingHashes | ForEach-Object {$_.文件 + '=' + $_.散列}) ($endingHashes | ForEach-Object {$_.文件 + '=' + $_.散列}))
[pscustomobject]@{通过=($sourceChanges.Count -eq 0);启动前文件数=$startingHashes.Count;完成后文件数=$endingHashes.Count;变化=$sourceChanges} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceRoot '验收期间源码冻结.json') -Encoding UTF8
if ($sourceChanges.Count -gt 0) { throw '验收期间源码有变化，本轮不能作为冻结后最终验收。' }
Write-Output ('全部选定无图形检查通过：' + $results.Count)
