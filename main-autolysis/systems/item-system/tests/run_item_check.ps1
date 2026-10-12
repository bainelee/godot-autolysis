param(
    [Parameter(Mandatory=$true)][string]$CheckName,
    [string]$ScriptPath = '',
    [string]$ScenePath = '',
    [int]$QuitAfter = 0,
    [int]$FixedFps = 0,
    [switch]$Rendered,
    [switch]$Visible,
    [switch]$Import,
    [int]$TimeoutSeconds = 180,
    [string[]]$UserArguments = @(),
    [string]$EvidenceRoot = '',
    [string[]]$ExpectedErrorPatterns = @()
)

# 必须在具备引擎用户目录访问权限的进程中运行，单项失败立即退出。
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
. (Join-Path $PSScriptRoot 'autolysis_test_evidence_paths.ps1')
$evidenceRoot = Resolve-AutolysisTestEvidenceRoot -EvidenceRoot $EvidenceRoot -SystemDirectory '道具系统\单项检查'
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
$hasEvidenceArgument = @($UserArguments | Where-Object {
    $_ -ceq '--evidence-dir' -or $_.StartsWith('--evidence-dir=', [StringComparison]::Ordinal)
}).Count -gt 0
if (-not $Import -and ($ScriptPath -or $ScenePath) -and -not $hasEvidenceArgument) {
    $detailsDirectory = Join-Path $evidenceRoot $CheckName
    New-Item -ItemType Directory -Force -Path $detailsDirectory | Out-Null
    $UserArguments += @('--evidence-dir', $detailsDirectory.Replace('\', '/'))
}
$engineFile = 'D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe'
$engineArgs = @('--path', $projectRoot)
if (-not $Rendered) { $engineArgs += '--headless' }
if ($FixedFps -gt 0) { $engineArgs += @('--fixed-fps', "$FixedFps") }
if ($QuitAfter -gt 0) { $engineArgs += @('--quit-after', "$QuitAfter") }
if ($Import) { $engineArgs += @('--editor','--quit') }
elseif ($ScriptPath) { $engineArgs += @('--script', $ScriptPath) }
elseif ($ScenePath) { $engineArgs += $ScenePath }
if ($UserArguments.Count -gt 0) { $engineArgs += '--'; $engineArgs += $UserArguments }
$outputFile = Join-Path $evidenceRoot ($CheckName + '.stdout.log')
$errorFile = Join-Path $evidenceRoot ($CheckName + '.stderr.log')
# 真实鼠标验收需要可见窗口；自动检查仍使用隐藏窗口。
$checkWindowStyle = if ($Visible -and $Rendered) { 'Normal' } else { 'Hidden' }
$checkProcess = Start-Process -FilePath $engineFile -ArgumentList (ConvertTo-AutolysisProcessArgumentLine -Arguments $engineArgs) -WindowStyle $checkWindowStyle -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile
if (-not $checkProcess.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $checkProcess.Id -Force
    throw "检查超时，已停止本次启动的进程：$CheckName"
}
$checkProcess.Refresh()
$allOutput = [IO.File]::ReadAllText($outputFile) + "`n" + [IO.File]::ReadAllText($errorFile)
$unexpectedErrors = @()
$expectedErrorCounts = @{}
foreach ($pattern in $ExpectedErrorPatterns) { $expectedErrorCounts[$pattern] = 0 }
foreach ($errorMatch in [regex]::Matches($allOutput, '(?m)^(SCRIPT ERROR:|ERROR:|失败：)[^\r\n]*')) {
    $expectedError = $false
    foreach ($pattern in $ExpectedErrorPatterns) {
        if ($errorMatch.Value -match $pattern) {
            $expectedErrorCounts[$pattern] += 1
            $expectedError = $true
            break
        }
    }
    if (-not $expectedError) { $unexpectedErrors += $errorMatch.Value }
}
$missingExpectedErrors = @($ExpectedErrorPatterns | Where-Object { $expectedErrorCounts[$_] -ne 1 })
$passed = $checkProcess.ExitCode -eq 0 -and $unexpectedErrors.Count -eq 0 -and $missingExpectedErrors.Count -eq 0
$record = [pscustomobject]@{检查=$CheckName; 时间=(Get-Date -Format o); 进程编号=$checkProcess.Id; 退出码=$checkProcess.ExitCode; 通过=$passed; 引擎文件=$engineFile; 窗口显示=$checkWindowStyle; 命令参数=$engineArgs; 通过断言数=([regex]::Matches($allOutput,'(?m)^通过：')).Count; 预期错误计数=$expectedErrorCounts; 非预期错误=$unexpectedErrors}
$record | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $evidenceRoot ($CheckName + '.json')) -Encoding utf8
$record | Format-List
if (-not $passed) { Write-Output $allOutput; exit 1 }
exit 0
