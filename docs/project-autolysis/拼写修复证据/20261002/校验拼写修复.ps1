# 校验 luquid（错误液体拼写）到 liquid（液体）的替换；只写入本次证据目录。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$工程目录 = 'D:\autolysis'
$证据目录 = 'D:\autolysis\docs\project-autolysis\拼写修复证据\20261002'
$错误拼写 = 'luquid'
$正确拼写 = 'liquid'
$唯一标识 = 'uid://bbqs75e8vtnql'
$字符编码 = [System.Text.UTF8Encoding]::new($false)

if (-not [string]::Equals([System.IO.Path]::GetFullPath($PSScriptRoot), $证据目录, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '校验脚本必须位于指定证据目录内执行。'
}

function 调用只读程序 {
    param([string]$程序名称, [string[]]$参数)
    $程序路径 = (Get-Command -Name $程序名称 -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $启动信息 = [System.Diagnostics.ProcessStartInfo]::new()
    $启动信息.FileName = $程序路径
    $启动信息.WorkingDirectory = $工程目录
    $启动信息.UseShellExecute = $false
    $启动信息.CreateNoWindow = $true
    $启动信息.RedirectStandardOutput = $true
    $启动信息.RedirectStandardError = $true
    $启动信息.StandardOutputEncoding = $字符编码
    $启动信息.StandardErrorEncoding = $字符编码
    foreach ($参数项 in $参数) {
        $启动信息.ArgumentList.Add($参数项)
    }
    $进程 = [System.Diagnostics.Process]::new()
    $进程.StartInfo = $启动信息
    try {
        [void]$进程.Start()
        $标准输出任务 = $进程.StandardOutput.ReadToEndAsync()
        $标准错误任务 = $进程.StandardError.ReadToEndAsync()
        $进程.WaitForExit()
        return [pscustomobject]@{
            '退出码' = $进程.ExitCode
            '标准输出' = $标准输出任务.GetAwaiter().GetResult()
            '标准错误' = $标准错误任务.GetAwaiter().GetResult()
        }
    }
    finally {
        $进程.Dispose()
    }
}

function 统一换行 {
    param([string]$内容)
    return $内容.Replace("`r`n", "`n").Replace("`r", "`n")
}

function 提取非空行 {
    param([string]$内容)
    return @((统一换行 $内容).Split("`n") | Where-Object { $_.Length -gt 0 })
}

function 写入证据 {
    param([string]$文件名, [string]$内容)
    if ([System.IO.Path]::GetFileName($文件名) -cne $文件名) {
        throw '证据文件名不得包含目录。'
    }
    $目标路径 = [System.IO.Path]::GetFullPath((Join-Path -Path $证据目录 -ChildPath $文件名))
    if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($目标路径), $证据目录, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw '写入目标超出指定证据目录。'
    }
    [System.IO.File]::WriteAllText($目标路径, $内容, $字符编码)
}

$当前提交结果 = 调用只读程序 'git' @('rev-parse', 'HEAD')
if ($当前提交结果.退出码 -ne 0) {
    throw ('无法读取版本控制当前提交：' + $当前提交结果.标准错误)
}
$当前提交 = $当前提交结果.标准输出.Trim()
$原文件列表结果 = 调用只读程序 'git' @('-c', 'core.quotepath=false', 'grep', '--full-name', '-l', '-i', '-F', $错误拼写, $当前提交, '--', 'main-autolysis', 'project.godot')
if ($原文件列表结果.退出码 -ne 0) {
    throw ('无法读取原始错误文件列表：' + $原文件列表结果.标准错误)
}
$原文件列表 = @(提取非空行 $原文件列表结果.标准输出 | ForEach-Object {
    $前缀 = $当前提交 + ':'
    if (-not $_.StartsWith($前缀, [System.StringComparison]::Ordinal)) {
        throw '版本控制输出包含无法识别的路径。'
    }
    $_.Substring($前缀.Length)
})

$逐文件结果 = @()
foreach ($原路径 in $原文件列表) {
    $现路径 = $原路径.Replace($错误拼写, $正确拼写)
    $现绝对路径 = [System.IO.Path]::GetFullPath((Join-Path -Path $工程目录 -ChildPath $现路径))
    if (-not $现绝对路径.StartsWith(($工程目录 + '\main-autolysis\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ('原始错误文件超出运行工程目录：' + $原路径)
    }
    $原始内容结果 = 调用只读程序 'git' @('show', ($当前提交 + ':' + $原路径))
    if ($原始内容结果.退出码 -ne 0) {
        throw ('无法读取原始文件：' + $原路径 + '；' + $原始内容结果.标准错误)
    }
    $原始内容 = $原始内容结果.标准输出
    $现文件存在 = [System.IO.File]::Exists($现绝对路径)
    $原始错误次数 = [System.Text.RegularExpressions.Regex]::Matches($原始内容, $错误拼写, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
    $替换内容 = 统一换行 ($原始内容.Replace($错误拼写, $正确拼写))
    $当前文件内容 = if ($现文件存在) { [System.IO.File]::ReadAllText($现绝对路径, $字符编码) } else { '' }
    $等价 = $现文件存在 -and [string]::Equals($替换内容, (统一换行 $当前文件内容), [System.StringComparison]::Ordinal)
    $当前安全散列 = if ($现文件存在) { (Get-FileHash -LiteralPath $现绝对路径 -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    $原始错误行 = @()
    $行号 = 0
    foreach ($行 in (统一换行 $原始内容).Split("`n")) {
        $行号++
        if ($行.IndexOf($错误拼写, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $原始错误行 += [pscustomobject]@{ '原始行号' = $行号; '原始文本' = $行 }
        }
    }
    $逐文件结果 += [pscustomobject]@{
        '原路径' = $原路径
        '现路径' = $现路径
        '原始错误次数' = $原始错误次数
        '当前文件存在' = $现文件存在
        '仅替换错误拼写且统一换行后相等' = $等价
        '当前文件安全散列算法' = 'SHA256（安全散列算法256位）'
        '当前文件安全散列' = $当前安全散列
        '原始错误行' = $原始错误行
    }
}

$文件清单结果 = 调用只读程序 'rg' @('--files', '-uuu', 'main-autolysis', 'project.godot')
if ($文件清单结果.退出码 -ne 0) {
    throw ('无法完成含隐藏及忽略文件的清单扫描：' + $文件清单结果.标准错误)
}
$运行文件清单 = @(提取非空行 $文件清单结果.标准输出)
$旧名称命中 = @($运行文件清单 | Where-Object { $_.IndexOf($错误拼写, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
$旧内容结果 = 调用只读程序 'rg' @('-l', '-uuu', '-i', '-F', '--text', $错误拼写, 'main-autolysis', 'project.godot')
if ($旧内容结果.退出码 -notin @(0, 1)) {
    throw ('无法完成含隐藏、忽略及二进制文件的内容扫描：' + $旧内容结果.标准错误)
}
$旧内容命中 = @(提取非空行 $旧内容结果.标准输出)

$原罐路径 = 'main-autolysis/scenes/prefabs/prefab_machines/luquid_tank_0.tscn'
$现罐路径 = $原罐路径.Replace($错误拼写, $正确拼写)
$原罐内容结果 = 调用只读程序 'git' @('show', ($当前提交 + ':' + $原罐路径))
if ($原罐内容结果.退出码 -ne 0) {
    throw ('无法读取原罐场景：' + $原罐内容结果.标准错误)
}
$原罐首行 = (统一换行 $原罐内容结果.标准输出).Split("`n")[0]
$现罐绝对路径 = Join-Path -Path $工程目录 -ChildPath $现罐路径
$现罐首行 = (统一换行 ([System.IO.File]::ReadAllText($现罐绝对路径, $字符编码))).Split("`n")[0]
$唯一标识字段 = 'uid="' + $唯一标识 + '"'
$唯一标识保留 = $原罐首行.Contains($唯一标识字段) -and $现罐首行.Contains($唯一标识字段)
$旧罐路径已不存在 = -not [System.IO.File]::Exists((Join-Path -Path $工程目录 -ChildPath $原罐路径))
$全部等价 = @($逐文件结果 | Where-Object { -not $_.仅替换错误拼写且统一换行后相等 }).Count -eq 0
$总错误次数 = ($逐文件结果 | Measure-Object -Property '原始错误次数' -Sum).Sum
$校验通过 = $原文件列表.Count -eq 12 -and $全部等价 -and $旧名称命中.Count -eq 0 -and $旧内容命中.Count -eq 0 -and $唯一标识保留 -and $旧罐路径已不存在

$结果 = [ordered]@{
    '记录时间' = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([datetime]::UtcNow, 'China Standard Time').ToString('yyyy-MM-dd HH:mm:ss') + '（北京时间）'
    '工程目录' = $工程目录
    '版本控制原始提交' = $当前提交
    '校验通过' = $校验通过
    '写入限制' = '校验脚本仅写入所在的指定证据目录；只读读取运行工程及版本控制对象。'
    '对比规则' = '原始提交内容执行 luquid（错误液体拼写）到 liquid（液体）的逐字替换；双方回车换行及回车统一为换行后，进行逐字精确比较。'
    '原始含错误文件数量' = $原文件列表.Count
    '原始错误出现次数' = $总错误次数
    '逐文件对比全部通过' = $全部等价
    '逐文件结果' = $逐文件结果
    '旧拼写残留检索' = [ordered]@{
        '范围' = @('main-autolysis', 'project.godot')
        '扫描规则' = '检索运行工程和工程配置；含隐藏、忽略文件；二进制按文本检索；忽略大小写。'
        '排除范围说明' = '历史证据、文档及引擎缓存不属于本次运行源文件验收范围。'
        '文件清单命令参数' = @('--files', '-uuu', 'main-autolysis', 'project.godot')
        '内容检索命令参数' = @('-l', '-uuu', '-i', '-F', '--text', 'luquid', 'main-autolysis', 'project.godot')
        '文件清单退出码' = $文件清单结果.退出码
        '内容检索退出码' = $旧内容结果.退出码
        '扫描文件数量' = $运行文件清单.Count
        '旧拼写文件名命中数量' = $旧名称命中.Count
        '旧拼写文件名命中' = $旧名称命中
        '旧拼写内容命中文件数量' = $旧内容命中.Count
        '旧拼写内容命中文件' = $旧内容命中
    }
    '罐场景唯一标识校验' = [ordered]@{
        '原路径' = $原罐路径
        '现路径' = $现罐路径
        '唯一标识' = $唯一标识
        '原罐场景首行' = $原罐首行
        '现罐场景首行' = $现罐首行
        '唯一标识保留' = $唯一标识保留
        '旧罐路径已不存在' = $旧罐路径已不存在
    }
}
写入证据 '拼写校验结果.json' ($结果 | ConvertTo-Json -Depth 20)
Write-Output ('校验通过：' + $校验通过 + '；原始错误文件：' + $原文件列表.Count + '；原始错误次数：' + $总错误次数 + '；旧内容命中：' + $旧内容命中.Count + '；旧文件名命中：' + $旧名称命中.Count)
if (-not $校验通过) {
    throw '拼写修复校验未通过；实际结果已保存至指定证据目录。'
}
