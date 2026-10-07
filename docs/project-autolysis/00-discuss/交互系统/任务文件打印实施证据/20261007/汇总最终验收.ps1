$ErrorActionPreference = 'Stop'
$evidenceRoot = $PSScriptRoot
# 每个检查只选择一份最终有效记录，不累计历史或同一专项重复执行。
$recordPaths = @(
    '最终来源与配置验收/导入解析.json',
    '最终专项/数据纸面.json',
    '最终混音边界验收/打印时序.json',
    '最终混音边界验收/主场景输入.json',
    '聚焦内容完整性最终/聚焦取纸.json',
    '最终回归/展示释放边界.json',
    '最终回归/道具回归.json',
    '最终回归/直接交互回归.json',
    '最终回归/组件迁移回归.json',
    '最终回归/聚焦回归.json',
    '最终混音边界验收/电话持物互斥回归.json',
    '最终回归/电话测试入口回归.json'
)
$allowedWarningPatterns = @(
    '^WARNING: 提示灯[01]运行引用或材质失效；停止对应灯表现$',
    '^WARNING: 通知中心按压停止更新：打印按钮可选按压播放器或动画失效$',
    '^WARNING: 提示灯[01]配置失效；停止对应灯表现$',
    '^WARNING: 提示音[01]播放器失效；停止对应声音表现$'
)
$rows = @()
foreach ($relativePath in $recordPaths) {
    $recordPath = Join-Path $evidenceRoot $relativePath
    $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $stdoutPath = $recordPath.Replace('.json','.stdout.log')
    $stderrPath = $recordPath.Replace('.json','.stderr.log')
    $outputText = [IO.File]::ReadAllText($stdoutPath) + "`n" + [IO.File]::ReadAllText($stderrPath)
    $diagnostics = @([regex]::Matches($outputText, '(?m)^(SCRIPT ERROR:|ERROR:|WARNING:|Leaked instance:|RID allocations:)[^\r\n]*') | ForEach-Object {$_.Value})
    $expectedWarnings = @()
    $unexpected = @()
    foreach ($line in $diagnostics) {
        $allowed = $false
        if ($record.检查 -eq '打印时序') {
            foreach ($pattern in $allowedWarningPatterns) {
                if ($line -match $pattern) { $allowed = $true; break }
            }
        }
        if ($allowed) { $expectedWarnings += $line }
        else { $unexpected += $line }
    }
    $passed = $record.通过 -and $record.退出码 -eq 0 -and @($record.非预期错误).Count -eq 0 -and $unexpected.Count -eq 0
    $rows += [pscustomobject]@{
        检查=$record.检查
        记录=$relativePath
        时间=$record.时间
        退出码=$record.退出码
        通过断言数=$record.通过断言数
        严格审计通过=$passed
        故障注入表现警告=$expectedWarnings
        非预期错误及警告=$unexpected
        记录散列=(Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash
        标准输出散列=(Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash
        错误输出散列=(Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash
    }
}
$failures = @($rows | Where-Object {-not $_.严格审计通过})
$summary = [pscustomobject]@{
    汇总时间=(Get-Date -Format o)
    自动验收通过=($failures.Count -eq 0)
    检查数=$rows.Count
    通过断言合计=($rows | Measure-Object -Property 通过断言数 -Sum).Sum
    去重规则='每项只计列出的最终有效一次执行；先前失败、同项重复及专用诊断不累计'
    图形画面='未执行'
    实际试听='未执行'
    编辑器人工操作='未执行'
    引擎内部输入='主场景无图形专项执行键盘与鼠标按钮事件；进入聚焦许可替换见实施记录'
    系统原生输入='未执行；未定位或注入系统指针'
    历史退出警告='机械第四轮及较早电话回归有一次对象泄漏警告；后续详细及原参数复验未重现，根因未取得证据，原日志保留'
    检查=$rows
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot '最终检查状态.json') -Encoding UTF8
$rows | Select-Object 检查,通过断言数,严格审计通过 | Format-Table -AutoSize
Write-Output ('有效检查数：' + $summary.检查数 + '；不重复累计断言：' + $summary.通过断言合计)
if ($failures.Count -ne 0) { throw '最终严格日志审计存在失败，检查最终检查状态。' }
