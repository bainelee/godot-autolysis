param([string]$ProjectRoot = 'D:\autolysis')
$ErrorActionPreference = 'Stop'
$assetRoot = Join-Path $ProjectRoot 'main-autolysis\assets\audio\sound_fx\machine\typewriter'
$records = foreach ($asset in Get-ChildItem -LiteralPath $assetRoot -File -Filter '*.wav' | Sort-Object Name) {
    $bytes = [IO.File]::ReadAllBytes($asset.FullName)
    $chunks = @()
    $position = 12
    $rate = 0
    $channels = 0
    $bits = 0
    $byteRate = 0
    $dataBytes = 0
    while ($position + 8 -le $bytes.Length) {
        $identifier = [Text.Encoding]::ASCII.GetString($bytes, $position, 4)
        $length = [BitConverter]::ToUInt32($bytes, $position + 4)
        $chunks += $identifier
        $content = $position + 8
        if ($identifier -eq 'fmt ') {
            $channels = [BitConverter]::ToUInt16($bytes, $content + 2)
            $rate = [BitConverter]::ToUInt32($bytes, $content + 4)
            $byteRate = [BitConverter]::ToUInt32($bytes, $content + 8)
            $bits = [BitConverter]::ToUInt16($bytes, $content + 14)
        }
        if ($identifier -eq 'data') { $dataBytes += $length }
        $position = $content + $length + ($length % 2)
    }
    if ($byteRate -le 0 -or $dataBytes -le 0) { throw '音频文件缺少可测量的有效格式及采样数据。' }
    [pscustomobject]@{
        文件 = $asset.FullName
        声道 = $channels
        采样率 = $rate
        采样位数 = $bits
        每秒字节数 = $byteRate
        采样数据字节数 = $dataBytes
        秒数 = [double]$dataBytes / $byteRate
        原始块标识 = $chunks
        包含循环元数据 = $chunks -contains 'smpl'
        文件散列 = (Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash
    }
}
$records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '音频资产实测.json') -Encoding utf8
$records | Select-Object 文件, 秒数, 采样率, 包含循环元数据
