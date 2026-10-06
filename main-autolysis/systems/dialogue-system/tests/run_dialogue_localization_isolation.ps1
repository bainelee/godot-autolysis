param(
    [Parameter(Mandatory=$true)][string]$EvidenceRoot
)

$ErrorActionPreference = 'Stop'
$isolationProductionRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$isolationEvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if (Test-Path -LiteralPath $isolationEvidenceRoot) { throw '隔离证据目录已经存在，禁止覆盖' }
New-Item -ItemType Directory -Path $isolationEvidenceRoot | Out-Null
$isolationProjectRoot = Join-Path $isolationEvidenceRoot 'isolated-project'
New-Item -ItemType Directory -Path $isolationProjectRoot | Out-Null
$isolationEncoding = [Text.UTF8Encoding]::new($false)
$isolationSources = @{
    'autolysis_dialogue_definition.gd' = 'main-autolysis\systems\dialogue-system\autolysis_dialogue_definition.gd'
    'dialogue_source.cfg' = 'main-autolysis\systems\dialogue-system\dialogue_source.cfg'
    'dialogue_zh.csv' = 'main-autolysis\systems\dialogue-system\dialogue_zh.csv'
    'chat_0_0.wav' = 'main-autolysis\assets\audio\speech\chat_0\chat_0_0.wav'
}
$isolationBeforeHashes = @{}
foreach ($isolationEntry in $isolationSources.GetEnumerator()) {
    $isolationSourcePath = Join-Path $isolationProductionRoot $isolationEntry.Value
    $isolationBeforeHashes[$isolationEntry.Value] = (Get-FileHash -LiteralPath $isolationSourcePath -Algorithm SHA256).Hash
    Copy-Item -LiteralPath $isolationSourcePath -Destination (Join-Path $isolationProjectRoot $isolationEntry.Key)
}
[IO.File]::WriteAllText((Join-Path $isolationProjectRoot 'project.godot'), @'
config_version=5

[application]
config/name="Dialogue Localization Isolation"

[rendering]
renderer/rendering_method="gl_compatibility"
'@, $isolationEncoding)
[IO.File]::WriteAllText((Join-Path $isolationProjectRoot 'chat_0.tres'), @'
[gd_resource type="Resource" script_class="AutolysisDialogueDefinition" load_steps=4 format=3]

[ext_resource type="Script" path="res://autolysis_dialogue_definition.gd" id="1_script"]
[ext_resource type="Translation" path="res://dialogue_zh.zh.translation" id="2_translation"]
[ext_resource type="AudioStream" path="res://chat_0_0.wav" id="3_voice"]

[resource]
script = ExtResource("1_script")
dialogue_id = &"chat_0"
line_ids = PackedStringArray("chat_0_0")
voice_streams = Array[AudioStream]([ExtResource("3_voice")])
chinese_translation = ExtResource("2_translation")
'@, $isolationEncoding)
[IO.File]::WriteAllText((Join-Path $isolationProjectRoot 'read_snapshot.gd'), @'
extends SceneTree

const DEFINITION: AutolysisDialogueDefinition = preload("res://chat_0.tres")

func _initialize() -> void:
    var arguments: PackedStringArray = OS.get_cmdline_user_args()
    var snapshot: Dictionary = DEFINITION.make_snapshot()
    var text: String = snapshot.get("lines", PackedStringArray([""]))[0]
    var passed: bool = snapshot.get("ok", false) and arguments.size() >= 2 and text == arguments[0]
    var record: FileAccess = FileAccess.open(arguments[1], FileAccess.WRITE)
    record.store_string(JSON.stringify({"通过": passed, "实际字幕": text, "预期字幕": arguments[0], "引擎": Engine.get_version_info()}, "\t"))
    print("通过：独立进程读取实际中文导入资源" if passed else "失败：实际中文与预期不符")
    quit(0 if passed else 1)
'@, $isolationEncoding)

function Invoke-IsolationEngine {
    param([string]$Name, [string[]]$EngineArguments)
    $isolationStdout = Join-Path $isolationEvidenceRoot ($Name + '.stdout.log')
    $isolationStderr = Join-Path $isolationEvidenceRoot ($Name + '.stderr.log')
    $isolationProcess = Start-Process -FilePath 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe' -ArgumentList $EngineArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $isolationStdout -RedirectStandardError $isolationStderr
    if (-not $isolationProcess.WaitForExit(60000)) { Stop-Process -Id $isolationProcess.Id; throw '隔离引擎超时' }
    $isolationProcess.Refresh()
    $isolationOutput = [IO.File]::ReadAllText($isolationStdout) + [IO.File]::ReadAllText($isolationStderr)
    $isolationPassed = $isolationProcess.ExitCode -eq 0 -and $isolationOutput -notmatch '(?m)^(SCRIPT ERROR:|ERROR:|失败：)'
    [pscustomobject]@{检查=$Name; 参数=$EngineArguments; 退出码=$isolationProcess.ExitCode; 通过=$isolationPassed; 进程编号=$isolationProcess.Id} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $isolationEvidenceRoot ($Name + '.json')) -Encoding utf8
    if (-not $isolationPassed) { Write-Output $isolationOutput; throw ('隔离检查失败：' + $Name) }
    Write-Output ('通过：' + $Name)
}

$isolationCsvPath = Join-Path $isolationProjectRoot 'dialogue_zh.csv'
$isolationSourceConfigPath = Join-Path $isolationProjectRoot 'dialogue_source.cfg'
$isolationCsvOriginal = [IO.File]::ReadAllText($isolationCsvPath)
$isolationBaselineLine = ($isolationCsvOriginal -split "`r?`n" | Where-Object { $_.StartsWith('chat_0_0,') })
$isolationBaselineText = $isolationBaselineLine.Substring('chat_0_0,'.Length)
Invoke-IsolationEngine -Name '基线导入' -EngineArguments @('--headless','--path',$isolationProjectRoot,'--editor','--quit')
Invoke-IsolationEngine -Name '基线新进程' -EngineArguments @('--headless','--path',$isolationProjectRoot,'--script','res://read_snapshot.gd','--',$isolationBaselineText,(Join-Path $isolationEvidenceRoot '基线字幕.json'))

$isolationSourceOriginal = [IO.File]::ReadAllText($isolationSourceConfigPath)
$isolationSourceVariant = $isolationSourceOriginal.Replace(('chat_0_0 = "' + $isolationBaselineText + '"'), 'chat_0_0 = "隔离测试仅原文修改"')
if ($isolationSourceVariant -eq $isolationSourceOriginal) { throw '原文修改未命中实际首句' }
[IO.File]::WriteAllText($isolationSourceConfigPath, $isolationSourceVariant, $isolationEncoding)
Invoke-IsolationEngine -Name '仅改原文新进程' -EngineArguments @('--headless','--path',$isolationProjectRoot,'--script','res://read_snapshot.gd','--',$isolationBaselineText,(Join-Path $isolationEvidenceRoot '仅原文字幕.json'))

$isolationChineseText = '隔离测试中文表格修改生效。'
$isolationChineseVariant = $isolationCsvOriginal.Replace(('chat_0_0,' + $isolationBaselineText), ('chat_0_0,' + $isolationChineseText))
if ($isolationChineseVariant -eq $isolationCsvOriginal) { throw '中文修改未命中实际首句' }
[IO.File]::WriteAllText($isolationCsvPath, $isolationChineseVariant, $isolationEncoding)
Invoke-IsolationEngine -Name '中文修改重新导入' -EngineArguments @('--headless','--path',$isolationProjectRoot,'--editor','--quit')
Invoke-IsolationEngine -Name '中文修改新进程' -EngineArguments @('--headless','--path',$isolationProjectRoot,'--script','res://read_snapshot.gd','--',$isolationChineseText,(Join-Path $isolationEvidenceRoot '修改中文字幕.json'))

$isolationHashRecords = @()
foreach ($isolationEntry in $isolationSources.GetEnumerator()) {
    $isolationCurrentHash = (Get-FileHash -LiteralPath (Join-Path $isolationProductionRoot $isolationEntry.Value) -Algorithm SHA256).Hash
    $isolationHashRecords += [pscustomobject]@{生产路径=$isolationEntry.Value; 前散列=$isolationBeforeHashes[$isolationEntry.Value]; 后散列=$isolationCurrentHash; 未改变=($isolationBeforeHashes[$isolationEntry.Value] -eq $isolationCurrentHash)}
    if ($isolationBeforeHashes[$isolationEntry.Value] -ne $isolationCurrentHash) { throw '生产文件散列变化' }
}
$isolationHashRecords | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $isolationEvidenceRoot '生产文件散列.json') -Encoding utf8
Write-Output '通过：三轮独立运行、真实中文重新导入及全部生产来源散列保持不变'
