param([string]$RunDirectory = '统一最终修正后')

$ErrorActionPreference = 'Stop'
$runRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $RunDirectory))
if (-not $runRoot.StartsWith($PSScriptRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '运行目录必须属于本轮修订证据。' }
$records = @(Get-Content -LiteralPath (Join-Path $runRoot '检查汇总.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
if ($records.Count -ne 27 -or @($records.检查 | Sort-Object -Unique).Count -ne 27) { throw '最终统一验收必须具有27项互不重复的记录。' }
$freeze = Get-Content -LiteralPath (Join-Path $runRoot '验收期间源码冻结.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$allowedWarnings = @{
    '打印时序' = @(
        'WARNING: 提示灯0运行引用或材质失效；停止对应灯表现',
        'WARNING: 通知中心按压停止更新：打印按钮可选按压播放器或动画失效',
        'WARNING: 提示灯1配置失效；停止对应灯表现',
        'WARNING: 提示音1播放器失效；停止对应声音表现'
    )
    '电话呼叫回归' = @('WARNING: 铃声播放器或指定资源失效')
}
$audit = @()
foreach ($summary in $records) {
    $name = $summary.检查
    $recordPath = Join-Path $runRoot ($name + '.json')
    $stdoutPath = Join-Path $runRoot ($name + '.stdout.log')
    $stderrPath = Join-Path $runRoot ($name + '.stderr.log')
    $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $logText = [IO.File]::ReadAllText($stdoutPath) + "`n" + [IO.File]::ReadAllText($stderrPath)
    $warnings = @([regex]::Matches($logText, '(?m)^WARNING: [^\r\n]*') | ForEach-Object {$_.Value})
    $unclassified = @($warnings | Where-Object {$_ -notin $allowedWarnings[$name]})
    $failedLines = @([regex]::Matches($logText, '(?m)^失败[：:][^\r\n]*') | ForEach-Object {$_.Value})
    $strictPass = $record.通过 -and $record.退出码 -eq 0 -and '--headless' -in $record.命令参数 -and @($record.非预期错误).Count -eq 0 -and $unclassified.Count -eq 0 -and $failedLines.Count -eq 0
    $audit += [pscustomobject]@{
        检查=$name;通过=$strictPass;断言数=$record.通过断言数;退出码=$record.退出码
        记录=$recordPath;记录散列=(Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash
        标准输出散列=(Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash
        错误输出散列=(Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash
        已核实故障注入警告=$warnings;未分类警告=$unclassified;失败断言=$failedLines;非预期错误=@($record.非预期错误)
    }
}
$failed = @($audit | Where-Object {-not $_.通过})
$result = [pscustomobject]@{
    时间=(Get-Date -Format o);通过=($freeze.通过 -and $failed.Count -eq 0)
    检查数=$audit.Count;有效断言总数=($audit | Measure-Object 断言数 -Sum).Sum
    验收期间源码冻结=$freeze;检查=$audit
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '最终检查状态.json') -Encoding UTF8
$result | Select-Object 时间,通过,检查数,有效断言总数 | ConvertTo-Json
if (-not $result.通过) { throw '最终严格审计未通过，需核实保存的失败或警告。' }
