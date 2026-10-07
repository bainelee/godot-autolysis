$ErrorActionPreference = 'Stop'
$probeDirectory = 'D:\autolysis\docs\project-autolysis\00-discuss\交互系统\任务板计划证据\20261007\用户调整后'
$enginePath = 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe'
$scenePath = 'D:\autolysis\main-autolysis\scenes\prefabs\prefab_machines\quest_board_0.tscn'
$paperPath = 'D:\autolysis\main-autolysis\scenes\prefabs\prefab_paper\quest_paper_blank.tscn'
$probeScript = 'res://docs/project-autolysis/00-discuss/交互系统/任务板计划证据/20261007/用户调整后/quest_board_scene_probe.gd'
$arguments = @('--headless', '--path', 'D:\autolysis', '--script', $probeScript)
$sceneHashBefore = (Get-FileHash -LiteralPath $scenePath -Algorithm SHA256).Hash
$paperHashBefore = (Get-FileHash -LiteralPath $paperPath -Algorithm SHA256).Hash
$startTime = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
$probeProcess = Start-Process -FilePath $enginePath -ArgumentList $arguments -WorkingDirectory 'D:\autolysis' -WindowStyle Hidden -RedirectStandardOutput (Join-Path $probeDirectory 'stdout.log') -RedirectStandardError (Join-Path $probeDirectory 'stderr.log') -Wait -PassThru
$sceneHashAfter = (Get-FileHash -LiteralPath $scenePath -Algorithm SHA256).Hash
$paperHashAfter = (Get-FileHash -LiteralPath $paperPath -Algorithm SHA256).Hash
[ordered]@{
    '开始时间' = $startTime
    '结束时间' = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
    '引擎路径' = $enginePath
    '启动参数' = $arguments
    '工作目录' = 'D:\autolysis'
    '实际命令' = '& "D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe" --headless --path "D:\autolysis" --script "' + $probeScript + '"'
    '无图形限制' = '使用 --headless（无图形）；未开启图形窗口，未激活应用，未注入输入；Hidden（隐藏）参数只是本机进程启动附加配置，无图形由引擎显示后端探针验证。'
    '退出码' = $probeProcess.ExitCode
    '任务板场景SHA256（安全散列）执行前' = $sceneHashBefore
    '任务板场景SHA256（安全散列）执行后' = $sceneHashAfter
    '示意纸场景SHA256（安全散列）执行前' = $paperHashBefore
    '示意纸场景SHA256（安全散列）执行后' = $paperHashAfter
    '生产场景未改动' = ($sceneHashBefore -eq $sceneHashAfter -and $paperHashBefore -eq $paperHashAfter)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $probeDirectory '运行记录.json') -Encoding utf8
Get-Content -LiteralPath (Join-Path $probeDirectory 'stdout.log')
Get-Content -LiteralPath (Join-Path $probeDirectory 'stderr.log')
Write-Output ('引擎退出码：' + $probeProcess.ExitCode)
exit $probeProcess.ExitCode

