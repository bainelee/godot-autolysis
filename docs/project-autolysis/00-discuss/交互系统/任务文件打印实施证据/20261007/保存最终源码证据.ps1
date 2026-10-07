param([string]$DestinationName = '实施后')

$ErrorActionPreference = 'Stop'
$projectRoot = 'D:\autolysis'
$evidenceRoot = $PSScriptRoot
$snapshotRoot = [IO.Path]::GetFullPath((Join-Path $evidenceRoot $DestinationName))
if (-not $snapshotRoot.StartsWith($evidenceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '快照目标必须在本次证据目录之内。'
}
if (Test-Path -LiteralPath $snapshotRoot) { throw '快照已经存在，不能覆盖历史。' }
New-Item -ItemType Directory -Path $snapshotRoot | Out-Null
$sourcePaths = @(& rg --files main-autolysis -g '*.gd' -g '*.tscn' -g '*.tres' -g '*.uid' -g '*.ps1' -g '*.import')
if ($LASTEXITCODE -ne 0) { throw '源码枚举失败。' }
$sourcePaths += @(
    'AGENTS.md',
    'project.godot',
    'docs/project-autolysis/00-discuss/交互系统/任务文件打印实现计划p1.md',
    'docs/project-autolysis/00-discuss/交互系统/任务文件打印讨论p1.md',
    'main-autolysis/assets/ui/item-icons/quest_paper.svg',
    'main-autolysis/assets/audio/sound_fx/machine/sfx_machine_notice_0.wav',
    'main-autolysis/assets/audio/sound_fx/machine/sfx_machine_scanning_0.wav'
)
$sourcePaths += @(& rg --files main-autolysis/assets/audio/sound_fx/phone -g '*.wav')
if ($LASTEXITCODE -ne 0) { throw '原有电话音频枚举失败。' }
$hashes = @()
foreach ($relativePath in @($sourcePaths | Sort-Object -Unique)) {
    $sourcePath = Join-Path $projectRoot $relativePath
    $targetPath = Join-Path $snapshotRoot $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    $hashes += [pscustomobject]@{文件=$relativePath;散列=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash;长度=(Get-Item -LiteralPath $sourcePath).Length}
}
$hashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $snapshotRoot '来源散列.json') -Encoding UTF8
$initialHashes = Get-Content -LiteralPath (Join-Path $evidenceRoot '实施前/来源散列.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$comparisons = @()
foreach ($initial in $initialHashes) {
    $currentFile = Join-Path $projectRoot $initial.path
    $currentHash = if (Test-Path -LiteralPath $currentFile) { (Get-FileHash -LiteralPath $currentFile -Algorithm SHA256).Hash } else { '' }
    $comparisons += [pscustomobject]@{文件=$initial.path;实施前散列=$initial.sha256;实施后散列=$currentHash;字节保持一致=($initial.sha256 -eq $currentHash)}
}
$comparisons | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $snapshotRoot '已有来源前后对照.json') -Encoding UTF8
& git -c core.quotepath=false status --short | Set-Content -LiteralPath (Join-Path $snapshotRoot '工作区状态.txt') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw '保存工作区状态失败。' }
$patchPath = Join-Path $snapshotRoot '对提交基线差异.patch'
& git diff --binary --no-ext-diff --output=$patchPath
if ($LASTEXITCODE -ne 0) { throw '保存提交基线差异失败。' }
$whitespaceOutput = @(& git diff --check 2>&1)
$whitespaceCode = $LASTEXITCODE
$whitespaceOutput | Set-Content -LiteralPath (Join-Path $snapshotRoot '差异空白检查.log') -Encoding UTF8
[pscustomobject]@{退出码=$whitespaceCode;通过=($whitespaceCode -eq 0)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $snapshotRoot '差异空白检查.json') -Encoding UTF8
$changes = @($comparisons | Where-Object { -not $_.字节保持一致 })
[pscustomobject]@{保存时间=(Get-Date -Format o);源码与资源数=$hashes.Count;原来源变化数=$changes.Count;快照目录=$snapshotRoot;差异空白通过=($whitespaceCode -eq 0)} | ConvertTo-Json
if ($whitespaceCode -ne 0) { throw '差异空白检查失败。' }
