function Resolve-AutolysisTestEvidenceRoot {
    param(
        [string]$EvidenceRoot = '',
        [Parameter(Mandatory=$true)][string]$SystemDirectory
    )

    # 显式目录保留原义；默认每次运行使用独立目录，避免覆盖历史证据。
    if (-not $EvidenceRoot) {
        $runDirectory = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $systemRoot = Join-Path 'D:\autolysis_history\测试运行' $SystemDirectory
        $EvidenceRoot = Join-Path $systemRoot $runDirectory
    }
    return [IO.Path]::GetFullPath($EvidenceRoot)
}

function ConvertTo-AutolysisProcessArgumentLine {
    param([string[]]$Arguments = @())

    # 进程启动接口会拼接参数数组；逐项引用以保留空格、引号和结尾反斜杠。
    $quotedArguments = foreach ($argumentValue in $Arguments) {
        $argument = [string]$argumentValue
        $escapedArgument = [regex]::Replace($argument, '(\\*)"', '$1$1\"')
        $escapedArgument = [regex]::Replace($escapedArgument, '(\\+)$', '$1$1')
        '"' + $escapedArgument + '"'
    }
    return $quotedArguments -join ' '
}
