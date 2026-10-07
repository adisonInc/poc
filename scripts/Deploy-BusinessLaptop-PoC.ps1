[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$DeviceNamePrefix = "BIZ-LT",
    [string[]]$OemAppPatterns = @(
        "McAfee",
        "WildTangent",
        "Candy Crush",
        "Dropbox Promotion",
        "Booking",
        "Netflix"
    ),
    [string]$LogPath = "C:\ProgramData\LaptopDeployment\deployment.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-DeploymentLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Run this script in an elevated PowerShell session (Administrator)."
    }
}

function Ensure-LogDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
}

function Rename-BusinessLaptop {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    $sanitized = ($serial -replace '[^A-Za-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        $sanitized = (Get-Random -Minimum 10000 -Maximum 99999).ToString()
    }

    $targetName = "$Prefix-$($sanitized.Substring(0, [Math]::Min(7, $sanitized.Length)))"
    if ($env:COMPUTERNAME -ieq $targetName) {
        Write-DeploymentLog "Computer already named '$targetName'."
        return
    }

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Rename computer to $targetName")) {
        Rename-Computer -NewName $targetName -Force
        Write-DeploymentLog "Renamed computer to '$targetName' (restart required)."
    }
}

function Remove-OemApps {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        Write-DeploymentLog "Processing OEM pattern: $pattern"

        $installedAppx = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$pattern*" }
        foreach ($app in $installedAppx) {
            if ($PSCmdlet.ShouldProcess($app.Name, "Remove AppX package")) {
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                Write-DeploymentLog "Removed AppX package: $($app.Name)"
            }
        }

        $provisionedAppx = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*$pattern*" }
        foreach ($app in $provisionedAppx) {
            if ($PSCmdlet.ShouldProcess($app.DisplayName, "Remove provisioned AppX package")) {
                Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction SilentlyContinue | Out-Null
                Write-DeploymentLog "Removed provisioned package: $($app.DisplayName)"
            }
        }

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $wingetTargets = winget list --accept-source-agreements 2>$null |
                Where-Object { $_ -match $pattern } |
                ForEach-Object { ($_ -split '\s{2,}')[0] } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique

            foreach ($target in $wingetTargets) {
                if ($PSCmdlet.ShouldProcess($target, "Uninstall package via winget")) {
                    winget uninstall --name $target --silent --accept-source-agreements | Out-Null
                    Write-DeploymentLog "Uninstalled winget package: $target"
                }
            }
        }
    }
}

function Start-AzureAdEnrollment {
    Write-DeploymentLog "Starting Azure AD / Intune enrollment prompt."
    if ($PSCmdlet.ShouldProcess("Current device", "Open MDM enrollment URI")) {
        Start-Process "ms-device-enrollment:?mode=mdm"
    }
}

Assert-Administrator
Ensure-LogDirectory -Path $LogPath
Start-Transcript -Path $LogPath -Append | Out-Null

try {
    Write-DeploymentLog "=== Business laptop deployment PoC started ==="
    Rename-BusinessLaptop -Prefix $DeviceNamePrefix
    Remove-OemApps -Patterns $OemAppPatterns
    Start-AzureAdEnrollment
    Write-DeploymentLog "=== Deployment PoC complete. User can proceed with Azure AD sign-in/enrollment. ==="
}
finally {
    Stop-Transcript | Out-Null
}
