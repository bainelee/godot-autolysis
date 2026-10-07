$ErrorActionPreference = 'Stop'
$recordPaths = @(
    '实施记录.md', '手持文字实施记录.md', '持有文字主链补验记录.md',
    '空间音效实施记录.md', '其他设备音效只读审计.md',
    '生产与旧兼容边界只读复核.md', '内容更新同步释放/实施记录.md'
)
$references = @()
foreach ($relative in $recordPaths) {
    $content = Get-Content -LiteralPath (Join-Path $PSScriptRoot $relative) -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($content, '\]\((/?[A-Za-z]:/[^)]+)\)')) {
        $target = $match.Groups[1].Value.TrimStart('/')
        $line = 0
        if ($target -match '^(.*):([0-9]+)$') {
            $target = $Matches[1]
            $line = [int]$Matches[2]
        }
        $exists = Test-Path -LiteralPath $target -PathType Leaf
        $lineValid = $exists -and ($line -eq 0 -or $line -le [IO.File]::ReadAllLines($target).Length)
        $references += [pscustomobject]@{记录=$relative;引用=$match.Groups[1].Value;存在=$exists;索引有效=$lineValid}
    }
}
$result = [pscustomobject]@{时间=(Get-Date -Format o);通过=(@($references | Where-Object {-not $_.索引有效}).Count -eq 0);引用数=$references.Count;引用=$references}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '最终记录引用核查.json') -Encoding UTF8
$result | Select-Object 时间,通过,引用数 | ConvertTo-Json
if (-not $result.通过) { throw '实施记录存在无效实际来源引用。' }
