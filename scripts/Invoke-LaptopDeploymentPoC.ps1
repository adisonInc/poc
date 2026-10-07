[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OemPatternFile = (Join-Path -Path $PSScriptRoot -ChildPath "..\config\oem-app-patterns.json"),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "C:\ProgramData\LaptopDeployment\deployment.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-DeploymentLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"
    $entry = "{0} [{1}] {2}" -f $timestamp, $Level, $Message
    Add-Content -Path $script:LogPath -Value $entry
    Write-Host $entry
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AzureAdJoinedStatus {
    if (-not (Get-Command dsregcmd.exe -ErrorAction SilentlyContinue)) {
        Write-DeploymentLog -Level "WARN" -Message "dsregcmd.exe not found. Azure AD join status cannot be verified."
        return $false
    }

    $statusOutput = dsregcmd.exe /status
    $azureJoinedMatch = $statusOutput | Select-String -Pattern "AzureAdJoined\s*:\s*YES" -Quiet
    return [bool]$azureJoinedMatch
}

function Load-OemPatterns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "OEM pattern file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $patterns = $raw | ConvertFrom-Json
    if (-not $patterns -or $patterns.Count -eq 0) {
        throw "OEM pattern file is empty: $Path"
    }

    return [string[]]$patterns
}

function Remove-MatchingAppxPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    $removed = [System.Collections.Generic.List[string]]::new()

    foreach ($pattern in $Patterns) {
        Write-DeploymentLog -Level "INFO" -Message "Searching AppX packages matching '$pattern'."

        $installed = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue)
        foreach ($pkg in $installed) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                $removed.Add($pkg.Name) | Out-Null
                Write-DeploymentLog -Level "INFO" -Message "Removed installed AppX package: $($pkg.Name)"
            }
            catch {
                Write-DeploymentLog -Level "WARN" -Message "Failed to remove installed package '$($pkg.Name)': $($_.Exception.Message)"
            }
        }

        $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pattern })
        foreach ($pkg in $provisioned) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                $removed.Add($pkg.DisplayName) | Out-Null
                Write-DeploymentLog -Level "INFO" -Message "Removed provisioned AppX package: $($pkg.DisplayName)"
            }
            catch {
                Write-DeploymentLog -Level "WARN" -Message "Failed to remove provisioned package '$($pkg.DisplayName)': $($_.Exception.Message)"
            }
        }
    }

    return $removed | Sort-Object -Unique
}

if (-not (Test-IsAdministrator)) {
    throw "Run this script from an elevated PowerShell session (Administrator)."
}

$logDirectory = Split-Path -Path $LogPath -Parent
if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -Path $LogPath -ItemType File -Force | Out-Null
}

$transcriptPath = Join-Path -Path $logDirectory -ChildPath "deployment-transcript-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
Start-Transcript -Path $transcriptPath -Force | Out-Null

try {
    Write-DeploymentLog -Level "INFO" -Message "Starting business laptop deployment PoC for user '$UserPrincipalName'."

    $isJoined = Get-AzureAdJoinedStatus
    if ($isJoined) {
        Write-DeploymentLog -Level "INFO" -Message "Device is already Azure AD joined."
    }
    else {
        Write-DeploymentLog -Level "WARN" -Message "Device is not Azure AD joined."
        Write-DeploymentLog -Level "INFO" -Message "Open Settings > Accounts > Access work or school and enroll '$UserPrincipalName' in Azure AD."
    }

    $patterns = Load-OemPatterns -Path $OemPatternFile
    Write-DeploymentLog -Level "INFO" -Message ("Loaded {0} OEM app patterns." -f $patterns.Count)

    $removedPackages = Remove-MatchingAppxPackages -Patterns $patterns
    if ($removedPackages.Count -gt 0) {
        Write-DeploymentLog -Level "INFO" -Message ("Removed {0} package(s): {1}" -f $removedPackages.Count, ($removedPackages -join ", "))
    }
    else {
        Write-DeploymentLog -Level "INFO" -Message "No matching OEM packages found."
    }

    Write-DeploymentLog -Level "INFO" -Message "Laptop deployment PoC completed successfully."
}
catch {
    Write-DeploymentLog -Level "ERROR" -Message "Deployment PoC failed: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
