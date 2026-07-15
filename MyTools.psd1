@{

# Module metadata
RootModule = 'MyTools.psm1'

ModuleVersion = '1.0.0'

GUID = '8d6f9f3c-1f6b-4d90-ae72-123456789abc'

Author = 'NathCorp'

CompanyName = 'NathCorp'

Copyright = '(c) NathCorp. All rights reserved.'

Description = 'Utility PowerShell module for system and file operations.'


# Minimum PowerShell version
PowerShellVersion = '5.1'


# Functions exported by module
FunctionsToExport = @(
    'Get-SystemInfo',
    'Test-FileExists',
    'Write-LogMessage'
)


# Cmdlets/variables not exported
CmdletsToExport = @()

VariablesToExport = @()

AliasesToExport = @()


# Compatible platforms
CompatiblePSEditions = @(
    'Desktop',
    'Core'
)

}
