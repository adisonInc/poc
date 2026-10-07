# Business Laptop Deployment PoC (Azure AD)

This repository contains a **proof of concept** for automating business laptop provisioning:

1. Prepare a Windows laptop for Azure AD / Intune enrollment
2. Uninstall common OEM/bloatware applications
3. Capture deployment logs for audit and troubleshooting

## Files

- `/scripts/Deploy-BusinessLaptop-PoC.ps1` – PowerShell automation script

## Quick start

> Run from an elevated PowerShell session on a Windows laptop.

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
.\scripts\Deploy-BusinessLaptop-PoC.ps1 -Verbose
```

## What the script does

- Verifies admin access and starts transcript logging
- Optionally renames the laptop using a configurable prefix
- Removes OEM apps by name pattern (both packaged AppX and winget-based installs when available)
- Opens Microsoft device enrollment to let the user sign in and enroll with Azure AD / Intune
- Writes a deployment summary to the log path

## Notes

- This is a PoC and should be validated in a non-production pilot group first.
- Actual production rollouts typically integrate with Windows Autopilot + Intune policies.