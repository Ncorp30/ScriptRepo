# MyTools.psm1

function Get-SystemInfo {
    <#
    .SYNOPSIS
    Gets basic system information.
    #>

    [CmdletBinding()]
    param()

    $os = Get-CimInstance Win32_OperatingSystem

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        OS           = $os.Caption
        LastBootTime = $os.LastBootUpTime
    }
}


function Test-FileExists {
    <#
    .SYNOPSIS
    Checks whether a file exists.

    .PARAMETER Path
    File path to check.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        return $true
    }

    return $false
}


function Write-LogMessage {
    <#
    .SYNOPSIS
    Writes a formatted log message.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARNING","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host "[$timestamp][$Level] $Message"
}


# Export module functions
Export-ModuleMember -Function `
    Get-SystemInfo, `
    Test-FileExists, `
    Write-LogMessage