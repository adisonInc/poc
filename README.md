# Business Laptop Deployment Automation PoC

This proof of concept (PoC) demonstrates Windows laptop deployment automation for:

- Azure AD readiness checks for business-user sign-in
- Uninstalling OEM/bloatware apps
- Deployment activity logging for audit/troubleshooting

## Repository Structure

- `/scripts/Invoke-LaptopDeploymentPoC.ps1` - Main PowerShell automation script
- `/config/oem-app-patterns.json` - Default OEM app name patterns

## Prerequisites

- Windows 10/11 business laptop
- PowerShell 5.1+ (or PowerShell 7+)
- Local administrator rights
- Internet connectivity for Azure AD enrollment/sign-in steps

## Usage

1. Open PowerShell as Administrator.
2. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Invoke-LaptopDeploymentPoC.ps1 -UserPrincipalName "user@contoso.com"
```

Optional overrides:

```powershell
.\scripts\Invoke-LaptopDeploymentPoC.ps1 `
  -UserPrincipalName "user@contoso.com" `
  -OemPatternFile ".\config\oem-app-patterns.json" `
  -LogPath "C:\ProgramData\LaptopDeployment\deployment.log"
```

## What the PoC Does

1. Creates a deployment log and starts transcript capture.
2. Checks whether the device is Azure AD joined.
3. If not joined, prompts operator guidance for Azure AD work/school enrollment.
4. Removes installed/provisioned AppX packages matching OEM patterns.
5. Records all actions and a final summary in the log.

## Notes

- This is a PoC and should be adapted for enterprise rollout tooling such as Intune/Autopilot task sequences.
- Always validate OEM app patterns in a pilot ring before broad deployment.