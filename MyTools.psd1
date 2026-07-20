@{

# Module metadata
RootModule = 'MyTools.psm1'

ModuleVersion = '1.0.0'

GUID = '4b5d2a1f-7c3e-4a91-9f2d-6e8c1a0f5d27'

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