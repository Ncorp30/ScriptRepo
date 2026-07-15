# Base log folder
$BasePath = "C:\CA-Monitor\Logs"
$StalePublishedTemplates = @()
$TemplateLookup = @{}
$TemplateInventory = @()
# Ensure folder exists (only once, no timestamp folder)
if (!(Test-Path $BasePath)) {
    New-Item -Path $BasePath -ItemType Directory | Out-Null
}

# Timestamp for file
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Transcript file with timestamp
$TranscriptFile = Join-Path $BasePath "Transcript_$TimeStamp.txt"

# Start transcript
Start-Transcript -Path $TranscriptFile -Append


$OS = (Get-CimInstance Win32_OperatingSystem).Caption

function Test-ADModule {
    return (Get-Module -ListAvailable -Name ActiveDirectory) -ne $null
}

function Ensure-ADModule {
    if (-not (Test-ADModule)) {
        return $false
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "ActiveDirectory module was found but failed to import." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }
}

# --------------------------
# SERVER OS
# --------------------------
if ($OS -match "Windows Server") {

    if (Test-ADModule) {
        if (Ensure-ADModule) {
            Write-Host "ActiveDirectory module is already installed." -ForegroundColor Green
        }
        else {
            exit
        }
    }
    else {
        Write-Host "ActiveDirectory module NOT found — Installing..." -ForegroundColor Yellow
        Install-WindowsFeature RSAT-AD-PowerShell
        if (Ensure-ADModule) {
            Write-Host "Installation complete on Server." -ForegroundColor Green
        }
        else {
            exit
        }
    }
}

# --------------------------
# WINDOWS 10 / 11 OS
# --------------------------
elseif ($OS -match "Windows 10" -or $OS -match "Windows 11") {

    $requiredRsat = @(
        "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",   # For Get-AD*
        "Rsat.CertificateServices.Tools~~~~0.0.1.0"      # For AD CS tools
    )

    foreach ($rsatName in $requiredRsat) {

        $rsat = Get-WindowsCapability -Online |
                Where-Object { $_.Name -eq $rsatName }

        if ($rsat.State -ne "Installed") {
            Write-Host "Installing $rsatName ..." -ForegroundColor Yellow
            try {
                Add-WindowsCapability -Online -Name $rsatName -ErrorAction Stop
                Write-Host "$rsatName installed successfully." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to install $rsatName" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                $ProgressPreference = $oldProg
                exit
            }
        }
        else {
            Write-Host "$rsatName already installed." -ForegroundColor Cyan
        }
    }

    if (-not (Ensure-ADModule)) {
        exit
    }
}

# ================================
# CONFIG
# ================================
$EndTime   = Get-Date
$StartTime = $EndTime.AddMinutes(-30)

$SnapshotFile = "C:\CA-Monitor\PublishedTemplates.json"

# Ensure folder exists
$Folder = Split-Path $SnapshotFile
if (!(Test-Path $Folder)) {
    New-Item -ItemType Directory -Path $Folder | Out-Null
}

# ================================
# CACHE (Performance Boost)
# ================================
$TemplateCache = @{}
# ================================
# 📊 GLOBAL COUNTERS (SUMMARY)
# ================================

$Summary = @{
    Created      = 0
    Modified     = 0
    Deleted      = 0
    Published    = 0
    Unpublished  = 0
}


# ================================
# STEP 1: SNAPSHOT (Published Templates)
# ================================
$ConfigNC = (Get-ADRootDSE).ConfigurationNamingContext
# ================================
# BULK LOAD ALL TEMPLATES (FAST)
# ================================
$AllTemplates = Get-ADObject `
    -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigNC" `
    -Filter * `
    -Properties displayName,msPKI-Cert-Template-OID,whenChanged,msPKI-Certificate-Name-Flag,msPKI-Enrollment-Flag

# Create lookup dictionary (CN → Object)
# Create lookup dictionary (CN → Object)
$TemplateLookup = [hashtable]::new()  

foreach ($t in $AllTemplates)
{
    if (
        -not [string]::IsNullOrWhiteSpace($t.Name) -or
        -not [string]::IsNullOrWhiteSpace($t.'msPKI-Cert-Template-OID')
    )
    {


        # safer assignment
        $key = ($t.Name -replace '\s+', ' ').Trim().ToLower()
$TemplateLookup[$key] = $t
    }
    else
    {
        $TemplateInventory += "$($t.DistinguishedName) | Reason: Missing Name/OID"
    }
}
$ConfigNC = (Get-ADRootDSE).ConfigurationNamingContext

$CAObjects = Get-ADObject `
    -SearchBase "CN=Enrollment Services,CN=Public Key Services,CN=Services,$ConfigNC" `
    -Filter { objectClass -eq "pKIEnrollmentService" } `
    -Properties certificateTemplates, displayName

# ================================
# COLLECT + VALIDATE PUBLISHED TEMPLATES
# ================================
# ================================
# COLLECT + VALIDATE PUBLISHED TEMPLATES
# ================================
$CurrentTemplates = @()
$SkippedTemplates = @()
$StalePublishedTemplates = @()

foreach ($CA in $CAObjects)
{
    if (-not $CA.certificateTemplates) { continue }

    foreach ($tpl in $CA.certificateTemplates)
    {
        # ----------------------------
        # 1️⃣ Must exist in AD lookup
        # ----------------------------
        $tplNormalized = ($tpl -replace '\s+', ' ').Trim().ToLower()

if (-not $TemplateLookup.ContainsKey($tplNormalized))
{
    $StalePublishedTemplates += $tpl
    continue
}

$TemplateObj = $TemplateLookup[$tplNormalized]

        # ----------------------------
        # 2️⃣ VALIDATION (KEEP THIS LOGIC)
        # ----------------------------
        if (
            -not [string]::IsNullOrWhiteSpace($TemplateObj.displayName) -and
            -not [string]::IsNullOrWhiteSpace($TemplateObj.'msPKI-Cert-Template-OID')
        )
        {
            # ✅ ONLY VALID PUBLISHED TEMPLATES ENTER SNAPSHOT
            $CurrentTemplates += $tpl
        }
        else
        {
            # 🔴 SKIPPED (invalid template)
            Write-Host "Skipped Template → $tpl | Reason: Invalid (Missing Name/OID)" -ForegroundColor Yellow

            $SkippedTemplates += $tpl
        }
    }
}

# ================================
# NORMALIZATION (SAFE SNAPSHOT)
# ================================
$CurrentTemplates = $CurrentTemplates |
    Where-Object { $_ -ne $null } |
    ForEach-Object { $_.Trim().ToLower() } |
    Sort-Object -Unique
$OldTemplates = $OldTemplates | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToLower() } | Sort-Object -Unique
#$CurrentTemplates = $CurrentTemplates | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToLower() } | Sort-Object -Unique
# ==========================================
# ⚠️ STALE PUBLISHED TEMPLATE SUMMARY
# ==========================================
if ($StalePublishedTemplates.Count -gt 0)
{
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "⚠️ STALE PUBLISHED TEMPLATES (CA ONLY)" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow

    foreach ($tpl in $StalePublishedTemplates | Sort-Object -Unique)
    {
        Write-Host " - $tpl"
    }

    Write-Host ""
    Write-Host "Total Stale Templates: $($StalePublishedTemplates.Count)" -ForegroundColor Yellow
}
# ================================

# ================================
$FirstRun = $false

if (Test-Path $SnapshotFile)
{
    $OldTemplates = Get-Content $SnapshotFile -Raw | ConvertFrom-Json

    if ($null -eq $OldTemplates)
    {
        $OldTemplates = @()
    }
    elseif ($OldTemplates -isnot [System.Array])
    {
        $OldTemplates = @($OldTemplates)
    }
}
else
{
    Write-Host ""
    Write-Host "No baseline found for published templates." -ForegroundColor Yellow
    Write-Host "Monitoring for Published/Unpublished templates will start from next run." -ForegroundColor Yellow

    $OldTemplates = @()
    $FirstRun = $true
}

# ================================
# 🔥 CLEAN OLD SNAPSHOT (IMPORTANT FIX)
# ================================
$OldTemplates = $OldTemplates |
    Where-Object { $_ -ne $null } |
    ForEach-Object { $_.Trim().ToLower() } |
    Sort-Object -Unique
$CurrentTemplates = $CurrentTemplates | ForEach-Object { $_.Trim().ToLower() }

$OldTemplates = $OldTemplates | Sort-Object -Unique
$CurrentTemplates = $CurrentTemplates | Sort-Object -Unique
if (-not $FirstRun)
{
    # 🔥 SAFETY: ensure clean comparison
    $OldClean = $OldTemplates | ForEach-Object { $_.Trim().ToLower() }
    $CurrentClean = $CurrentTemplates | ForEach-Object { $_.Trim().ToLower() }

    # Detect publish/unpublish
    $NewPublished =
        $CurrentClean | Where-Object { $_ -notin $OldClean }

    $RemovedTemplates =
        $OldClean | Where-Object { $_ -notin $CurrentClean }

    
}
else
{
    $NewPublished = @()
    $RemovedTemplates = @()
}

# ================================
# STEP 2: EVENT LOG COLLECTION
# ================================
$EventIDs = 5137,5136,5141
try {
    $Events = Get-WinEvent -FilterHashtable @{
        LogName='Security'
        Id=$EventIDs
        StartTime=$StartTime
    } -ErrorAction SilentlyContinue | Sort-Object TimeCreated
}
catch {
    $Events = @()
}


$GroupedEvents = @{}

foreach ($Event in $Events)
{
    $xml = [xml]$Event.ToXml()

    $User = ($xml.Event.EventData.Data | Where {$_.Name -eq "SubjectUserName"}).'#text'
    $Domain = ($xml.Event.EventData.Data | Where {$_.Name -eq "SubjectDomainName"}).'#text'

    # Safe DN extraction
    $ObjectDN = ($xml.Event.EventData.Data | Where {$_.Name -eq "ObjectDN"}).'#text'
    if (-not $ObjectDN)
    {
        $ObjectDN = ($xml.Event.EventData.Data | Where {$_.Name -eq "ObjectName"}).'#text'
    }

    # Clean DN
    if ($ObjectDN) { $ObjectDN = $ObjectDN.Trim() }


    if (-not $ObjectDN -or $ObjectDN -notlike "*CN=Certificate Templates*")
    { 
        continue
    }

    $TimeKey = $Event.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
    $Key = "$ObjectDN|$TimeKey"

    if (-not $GroupedEvents.ContainsKey($Key))
    {
        $GroupedEvents[$Key] = @{
            User = "$Domain\$User"
            Time = $Event.TimeCreated
            EventIDs = @()
            Changes = @()
        }
    }

    $GroupedEvents[$Key].EventIDs += $Event.Id

    $AttributeName = ($xml.Event.EventData.Data | Where {$_.Name -eq "AttributeLDAPDisplayName"}).'#text'
    $AttributeValue = ($xml.Event.EventData.Data | Where {$_.Name -eq "AttributeValue"}).'#text'

    if ($AttributeName)
    {
        $Entry = "$AttributeName : $AttributeValue"

        if (-not ($GroupedEvents[$Key].Changes -contains $Entry))
        {
            $GroupedEvents[$Key].Changes += $Entry
        }
    }
}

# ================================
# STEP 3: OUTPUT (EVENTS)
# ================================
foreach ($Key in $GroupedEvents.Keys)
{ 
   
    $Data = $GroupedEvents[$Key]
    $ObjectDN = $Key.Split("|")[0]

    $TemplateOID = "N/A"
    $TemplateDN  = $ObjectDN
    $Template = $null

    # ===== CACHE LOOKUP =====
    if ($TemplateCache.ContainsKey($ObjectDN))
    {
        $Template = $TemplateCache[$ObjectDN]
    }
    else
    { 
    if ($Data.EventIDs -contains 5141)
    {
        $Template = $null
    }
    else{
        try
        {
            $Template = Get-ADObject -Identity $ObjectDN -Properties displayName,msPKI-Cert-Template-OID -ErrorAction SilentlyContinue
            $TemplateCache[$ObjectDN] = $Template
        }
        catch
        {
            $Template = $null
        }}
    }

    # ===== DATA RESOLUTION =====
    if ($Template)
    {
        $TemplateName = $Template.displayName
        $TemplateOID  = $Template.'msPKI-Cert-Template-OID'
    }
    else
    {
        if ($ObjectDN -match "CN=([^,]+)")
        {
            $TemplateName = $Matches[1] + " (Deleted)"
        }
        else
        {
            $TemplateName = "Template not found"
        }
    }
   
    # ===== ACTION =====
    if ($Data.EventIDs -contains 5137)
    {
        $Action="Template Created"
        $Summary.Created++
    }
    elseif ($Data.EventIDs -contains 5141)
    {
        $Action="Template Deleted"
        
         $Summary.Deleted++
    }
    elseif($Data.EventIDs -contains 5136)
    {
        $Action="Template Modified"
         $Summary.Modified++ 
         
    }
   

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Template Name  : $TemplateName"
    Write-Host "Template DN    : $TemplateDN"
    Write-Host "Template OID   : $TemplateOID"
    Write-Host "Action         : $Action"
    Write-Host "Performed By   : $($Data.User)"
    Write-Host "Time           : $($Data.Time)"
    Write-Host "============================================"

    # ================================
    # ✅ EVENT-ONLY SECURITY ANALYSIS
    # ================================
    $SubjectSupply = $false
    $ManagerApproval = $false
    $DisplayNameFromEvent = $null

  foreach ($Change in $Data.Changes)
{
    # Split "Attribute : Value"
    $parts = $Change -split " : ", 2

    if ($parts.Count -ne 2) { continue }

    $Attr  = $parts[0].Trim()
    $Value = $parts[1].Trim()

    switch ($Attr)
    {
        "displayName" {
            $DisplayNameFromEvent = $Value
        }

        "msPKI-Certificate-Name-Flag" {
            $SanValue = [int]$Value
            $SubjectSupply = ($SanValue -band 0x1) -ne 0
        }

        "msPKI-Enrollment-Flag" {
            $EnrollValue = [int]$Value
            $ManagerApproval = ($EnrollValue -band 0x2) -ne 0
        }
    }
}

    Write-Host ""
    Write-Host "Security Analysis:" -ForegroundColor Cyan

    if ($DisplayNameFromEvent)
    {
        Write-Host "  - Display Name        : $DisplayNameFromEvent"
    }
    Write-Host "  - Supply Subject (CN)  : $(if($SubjectSupply){'YES'}else{'NO'})"
    Write-Host "  - Manager Approval     : $(if($ManagerApproval){'REQUIRED'}else{'NOT REQUIRED'})"
}
# ================================
# STEP 4 & 5: OUTPUT (ONLY AFTER BASELINE EXISTS)
# ================================
if (-not $FirstRun)
{

    # ---------------- PUBLISHED ----------------
    foreach ($TemplateCN in $NewPublished)
    {
       $TemplateCNLower = ($TemplateCN -replace '\s+', ' ').Trim().ToLower()

       
        if (-not $TemplateLookup.ContainsKey($TemplateCNLower))
        {
            continue
        }

        Write-Host ""
        Write-Host "NEW TEMPLATE PUBLISHED"
        $Summary.Published++

        $TemplateObj = $TemplateLookup[$TemplateCNLower]

        Write-Host "Template Name : $($TemplateObj.displayName)"
        Write-Host "Template CN   : $($TemplateObj.Name)"
        Write-Host "Template DN   : $($TemplateObj.DistinguishedName)"
        Write-Host "Template OID  : $($TemplateObj.'msPKI-Cert-Template-OID')"
        Write-Host "Last Modified : $($TemplateObj.whenChanged)"

        Write-Host "--------------------------------------------"
    }

    # ---------------- UNPUBLISHED ----------------
    foreach ($TemplateCN in $RemovedTemplates)
    {
         $TemplateCNLower = ($TemplateCN -replace '\s+', ' ').Trim().ToLower()

        # ❌ Skip stale/broken
        if (-not $TemplateLookup.ContainsKey($TemplateCNLower))
        {
            continue
        }

        Write-Host ""
        Write-Host "TEMPLATE UNPUBLISHED"
        $Summary.Unpublished++

        $TemplateObj = $TemplateLookup[$TemplateCNLower]

        Write-Host "Template Name : $($TemplateObj.displayName)"
        Write-Host "Template CN   : $($TemplateObj.Name)"
        Write-Host "Template DN   : $($TemplateObj.DistinguishedName)"
        Write-Host "Template OID  : $($TemplateObj.'msPKI-Cert-Template-OID')"
        Write-Host "Last Modified : $($TemplateObj.whenChanged)"

        Write-Host "--------------------------------------------"
    }
}
# ================================
# STEP 6: NO ACTIVITY CHECK
# ================================
# ================================
# FINAL OUTPUTf
# ================================

$HasActivity = (
    ($Summary.Created -gt 0) -or
    ($Summary.Modified -gt 0) -or
    ($Summary.Deleted -gt 0) -or
    ($Summary.Published -gt 0) -or
    ($Summary.Unpublished -gt 0)
)

if (-not $HasActivity)
{
    Write-Host ""
    Write-Host "ℹ️ No template activity in last 30 minutes." -ForegroundColor Yellow
}
else
{
    Write-Host ""
    Write-Host "================ FINAL SUMMARY ================" -ForegroundColor Cyan

    if ($Summary.Created -gt 0)     { Write-Host "Template Created   : $($Summary.Created)" }
    if ($Summary.Modified -gt 0)    { Write-Host "Template Modified Events  : $($Summary.Modified)" }
    if ($Summary.Deleted -gt 0)     { Write-Host "Template Deleted   : $($Summary.Deleted)" }
    if ($Summary.Published -gt 0)   { Write-Host "Published          : $($Summary.Published)" }
    if ($Summary.Unpublished -gt 0) { Write-Host "Unpublished        : $($Summary.Unpublished)" }

    Write-Host "==============================================="
}

# ================================
# STEP 7: SAVE SNAPSHOT
# ================================
$CurrentTemplates | Sort-Object -Unique | ConvertTo-Json -Depth 3 | Set-Content $SnapshotFile

Stop-Transcript