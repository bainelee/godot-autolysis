param([string]$ProjectRoot = 'D:\autolysis')

$ErrorActionPreference = 'Stop'
$verifyProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$verifyEvidenceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$verifyEncoding = [Text.UTF8Encoding]::new($false)
$verifyDocuments = @(
    (Join-Path $verifyProjectRoot 'docs\project-autolysis\00-discuss\交互系统\电话来电与对话系统实现计划p1.md'),
    (Join-Path $verifyEvidenceRoot '实施记录.md'),
    (Join-Path $verifyEvidenceRoot '验收矩阵.md')
)
$verifyLinks = @()
foreach ($verifyDocument in $verifyDocuments) {
    $verifyText = [IO.File]::ReadAllText($verifyDocument)
    foreach ($verifyMatch in [regex]::Matches($verifyText, '\[[^\]]*\]\(([^)]+)\)')) {
        $verifyReference = $verifyMatch.Groups[1].Value.Trim('<','>')
        if ($verifyReference -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { continue }
        $verifyLine = 0
        $verifyPath = $verifyReference
        if ($verifyPath -match ':(\d+)$') {
            $verifyLine = [int]$Matches[1]
            $verifyPath = $verifyPath.Substring(0, $verifyPath.LastIndexOf(':'))
        }
        if ($verifyPath -match '^/?([a-zA-Z]:[/\\].*)$') {
            $verifyPath = $Matches[1]
        } else {
            $verifyPath = Join-Path ([IO.Path]::GetDirectoryName($verifyDocument)) $verifyPath
        }
        $verifyPath = [IO.Path]::GetFullPath($verifyPath)
        $verifyExists = Test-Path -LiteralPath $verifyPath
        $verifyLineCount = if ($verifyExists -and $verifyLine -gt 0) { [IO.File]::ReadAllLines($verifyPath).Length } else { 0 }
        $verifyValid = $verifyExists -and ($verifyLine -eq 0 -or ($verifyLine -ge 1 -and $verifyLine -le $verifyLineCount))
        $verifyLinks += [pscustomobject]@{文档=$verifyDocument; 引用=$verifyReference; 实际路径=$verifyPath; 存在=$verifyExists; 行号=$verifyLine; 实际行数=$verifyLineCount; 通过=$verifyValid}
    }
}
$verifyFailures = @($verifyLinks | Where-Object { -not $_.通过 })
$verifyLinkReport = [ordered]@{时间=(Get-Date -Format o); 通过=($verifyFailures.Count -eq 0); 本地链接数=$verifyLinks.Count; 不同目标数=@($verifyLinks.实际路径 | Sort-Object -Unique).Count; 带行号链接数=@($verifyLinks | Where-Object {$_.行号 -gt 0}).Count; 失败数=$verifyFailures.Count; 明细=$verifyLinks}
[IO.File]::WriteAllText((Join-Path $verifyEvidenceRoot '文档链接核对.json'), ($verifyLinkReport | ConvertTo-Json -Depth 6), $verifyEncoding)
if ($verifyFailures.Count -ne 0) { $verifyFailures | Format-List; throw '存在无效文档链接。' }

$verifyManifest = Get-Content -LiteralPath (Join-Path $verifyEvidenceRoot '最终文件散列.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$verifyHashes = @()
foreach ($verifyEntry in $verifyManifest) {
    $verifyActualHash = (Get-FileHash -LiteralPath (Join-Path $verifyProjectRoot $verifyEntry.路径) -Algorithm SHA256).Hash
    $verifyHashes += [pscustomobject]@{路径=$verifyEntry.路径; 归档散列=$verifyEntry.散列; 实际散列=$verifyActualHash; 通过=($verifyActualHash -eq $verifyEntry.散列)}
}
$verifyChanged = @($verifyHashes | Where-Object {-not $_.通过})
$verifyHashReport = [ordered]@{时间=(Get-Date -Format o); 通过=($verifyChanged.Count -eq 0); 文件数=$verifyHashes.Count; 改变数=$verifyChanged.Count; 明细=$verifyHashes}
[IO.File]::WriteAllText((Join-Path $verifyEvidenceRoot '最终散列复核.json'), ($verifyHashReport | ConvertTo-Json -Depth 5), $verifyEncoding)
if ($verifyChanged.Count -ne 0) { $verifyChanged | Format-List; throw '归档后生产或验收文件改变。' }
Write-Output ('通过：' + $verifyLinks.Count + '个本地链接及' + $verifyHashes.Count + '个文件散列核对。')
