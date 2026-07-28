# MyTools.psm1

function Get-SystemInfo {
    <#
    .SYNOPSIS
    Gets basic system information.
    #>

    [CmdletBinding()]
    param()

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

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
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        if (Test-Path -Path $Path -ErrorAction Stop) {
            return $true
        }

        return $false
    }
    catch {
        throw
    }
}


function Write-LogMessage {
    <#
    .SYNOPSIS
    Writes a formatted log message.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
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
