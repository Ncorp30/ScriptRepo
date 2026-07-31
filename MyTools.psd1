@{

# Module metadata
RootModule = 'MyTools.psm1'

ModuleVersion = '1.0.0'

GUID = 'c2f4a7d1-5b3e-4a6f-9d21-7e8a4c6f2d10'

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
