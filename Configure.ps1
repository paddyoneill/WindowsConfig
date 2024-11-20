# Elevate to admin if needed
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

if ( !( $myWindowsPrincipal.IsInRole($adminRole) ) )
{
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"

    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

# Track if reboot needed at end of script
# Only outputs a message if true
$RebootRequired = $false

# Read config file
$Config = Get-Content -Path $PSScriptRoot\Config.json | ConvertFrom-Json
$PackageList = $Config.Packages
$FontList = $Config.Fonts


####################
# Install Packages #
####################

foreach ( $Package in $PackageList )
{
    winget list -e --id $Package --accept-source-agreements --disable-interactivity | Out-Null
    if (-not $? )
    {
        Write-Host "Installing package $Package"
        winget install -e --id $Package --accept-source-agreements --disable-interactivity
        if ( $? ) {
            Write-Host "Installed package $Package"
        }
    }
    else
    {
        Write-Host "Package $Package already installed"
    }
}


#################
# Install Fonts #
#################

$FontDownloadDir = $PSScriptRoot + "\Fonts"
if ( !(Test-Path -PathType Container $FontDownloadDir) )
{
    New-Item -ItemType Directory -Path $FontDownloadDir | Out-Null
}

foreach ( $Font in $FontList)
{
    Write-Host "Installing $($Font.Name) Font"

    if ( !(Test-Path -PathType Container $FontDownloadDir\$($Font.Name)) )
    {
        New-Item -ItemType Directory -Path $FontDownloadDir\$($Font.Name) | Out-Null
    } 
    
    $FontArchive = ([uri]$($Font.Source)).Segments[-1]
    if ( !(Test-Path -PathType Leaf $FontDownloadDir\$($Font.Name)\$FontArchive) )
    {
        Invoke-WebRequest $($Font.Source) -OutFile $FontDownloadDir\$($Font.Name)\$FontArchive
    }

    Expand-Archive $FontDownloadDir\$($Font.Name)\$FontArchive -Destination $FontDownloadDir\$($Font.Name) -Force

    $FontFiles = Get-ChildItem -Path $FontDownloadDir\$($Font.Name) -Include ('*.otf', '*.ttf') -Recurse
    
    foreach ( $FontFile in $FontFiles )
    {
        Copy-Item $FontFile 'C:\Windows\Fonts'
        
        $FontRegEntry = @{
            Path = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
            Name = $FontFile.BaseName
        }

        $ExinstingRegEntry = Get-ItemProperty @FontRegEntry
        if ( $ExinstingRegEntry -eq $null )
        {
            New-ItemProperty @FontRegEntry -Value $FontFile.Name
        }
    }
}


###########################
# Link PowerShell Profile #
###########################
if (-not (Test-Path -Path $PROFILE))
{
    Write-Host "Creating link for PowerShell Profile"
    New-Item -Path $PROFILE -ItemType SymbolicLink -Value $PSScriptRoot\PowerShell_profile.ps1
}

##################
# Enable Hyper-V #
##################

$HyperVState = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V | Select-Object State

if ( $HyperVState -match "Disabled" )
{
    Write-Host "Enabling Hyper-V"
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
    $RebootRequired = $true
} else {
    Write-Host "Hyper-V already enabled"
}


####################
# Enable SSH Agent #
####################

$SSHAgentStatus = Get-Service ssh-agent | Select StartType

if ( $SSHAgentStatus -match "Disabled" )
{
    Write-Host "Enabling SSH Agent"
    Get-Service ssh-agent | Set-Service -StartupType Automatic
    $RebootRequired = $true
} else {
    Write-Host "SSH Agent already enabled"
}


# Output if a reboot is required to complete setup
if ( $RebootRequired ) {
    Write-Host "Reboot to finish setup"
}
