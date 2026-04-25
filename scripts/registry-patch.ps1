#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes QEMU/VirtIO/hypervisor registry artifacts from a Windows guest.

.DESCRIPTION
    Runs inside the Windows VM (as Administrator) after driver installation.
    Scrubs registry keys that expose VM presence to detection tools like
    Pafish, Al-Khaser, VMAware, and WMI queries.

    Run via registry-patch.bat for automatic elevation, or directly:
        powershell -ExecutionPolicy Bypass -File registry-patch.ps1

    Take a VM snapshot BEFORE running this script.
    After running, reboot the VM and run detection tools to verify.

.NOTES
    Some keys may be recreated by Windows Update or driver reinstallation.
    Disable Windows Update or re-run after updates if needed.
#>

param(
    [switch]$DryRun,
    [switch]$Verbose
)

$ErrorActionPreference = "SilentlyContinue"
$changes = @()

function Remove-KeySafe {
    param([string]$Path, [string]$Reason)
    if (Test-Path $Path) {
        if (-not $DryRun) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $changes += [PSCustomObject]@{ Action="RemoveKey"; Path=$Path; Reason=$Reason }
        if ($Verbose) { Write-Host "[*] Removed key: $Path  ($Reason)" -ForegroundColor Yellow }
    }
}

function Set-ValueSafe {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Reason)
    if (Test-Path $Path) {
        if (-not $DryRun) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -ErrorAction SilentlyContinue
        }
        $changes += [PSCustomObject]@{ Action="SetValue"; Path="$Path\$Name"; Value=$Value; Reason=$Reason }
        if ($Verbose) { Write-Host "[*] Set value: $Path\$Name = $Value  ($Reason)" -ForegroundColor Cyan }
    }
}

Write-Host "`n[*] Registry artifact scrubber — Windows VM anti-detection" -ForegroundColor Green
Write-Host "    Mode: $(if ($DryRun) {'DRY RUN (no changes)'} else {'LIVE'})`n"

# ============================================================
# Section 1: VM vendor software keys
# These are checked by Pafish, Al-Khaser, and custom malware.
# ============================================================
Write-Host "[1/6] VM vendor software keys..."

$vendorKeys = @(
    @{ Path = "HKLM:\SOFTWARE\Oracle";          Reason = "VirtualBox vendor key" },
    @{ Path = "HKLM:\SOFTWARE\VMware, Inc.";    Reason = "VMware vendor key" },
    @{ Path = "HKLM:\SOFTWARE\QEMU";            Reason = "QEMU vendor key" },
    @{ Path = "HKCU:\SOFTWARE\Oracle";          Reason = "VirtualBox user key" },
    @{ Path = "HKLM:\SOFTWARE\Red Hat, Inc.";   Reason = "VirtIO vendor key" },
    @{ Path = "HKLM:\SOFTWARE\Wow6432Node\Oracle";       Reason = "VirtualBox 32-bit key" },
    @{ Path = "HKLM:\SOFTWARE\Wow6432Node\VMware, Inc."; Reason = "VMware 32-bit key" }
)

foreach ($k in $vendorKeys) { Remove-KeySafe -Path $k.Path -Reason $k.Reason }

# ============================================================
# Section 2: VM services in CurrentControlSet
# Service names are checked by Win32_Service WMI queries and
# direct registry enumeration by Al-Khaser.
# ============================================================
Write-Host "[2/6] VM-related service registrations..."

$vmServicePatterns = @('QEMU', 'VirtIO', 'viostor', 'vioscsi', 'NetKVM',
                        'Balloon', 'vioser', 'vioinput', 'viogpudo',
                        'viorng', 'pvpanic', 'VBoxGuest', 'VBoxMouse',
                        'VBoxService', 'VBoxSF', 'VBoxVideo', 'vmhgfs',
                        'vmci', 'vmxnet', 'vmx_svga', 'vmusbmouse')

$servicesPath = "HKLM:\SYSTEM\CurrentControlSet\Services"
Get-ChildItem $servicesPath -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.PSChildName
    foreach ($pattern in $vmServicePatterns) {
        if ($name -match $pattern) {
            Remove-KeySafe -Path $_.PSPath -Reason "VM service: $name"
            break
        }
    }
}

# ============================================================
# Section 3: ACPI/BIOS string caches
# Windows caches ACPI OEM strings under HARDWARE\ACPI\DSDT.
# QEMU leaves "BOCHS " or "QEMU  " as OEM ID in the DSDT.
# These are cleared after our SMBIOS spoofing takes effect,
# but explicit removal ensures no stale strings remain.
# ============================================================
Write-Host "[3/6] ACPI/BIOS string caches..."

$acpiPath = "HKLM:\HARDWARE\ACPI"
if (Test-Path $acpiPath) {
    Get-ChildItem $acpiPath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.PSChildName
        if ($name -match 'BOCHS|QEMU|VBOX|VIRT') {
            Remove-KeySafe -Path $_.PSPath -Reason "ACPI OEM string: $name"
        }
    }
}

# ============================================================
# Section 4: Display adapter string patches
# The display driver DriverDesc and ProviderName appear in
# Device Manager and WMI Win32_VideoController.
# VirtIO GPU appears as "Red Hat VirtIO GPU" — replace with
# a plausible Intel UHD string.
# ============================================================
Write-Host "[4/6] Display adapter driver strings..."

$displayClassGuid = "{4D36E968-E325-11CE-BFC1-08002BE10318}"
$displayClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$displayClassGuid"

if (Test-Path $displayClassPath) {
    Get-ChildItem $displayClassPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $desc = $props.DriverDesc
        if ($desc -match 'QEMU|VirtIO|Red Hat|llvmpipe|SVGA|VirtualBox') {
            Set-ValueSafe -Path $_.PSPath -Name "DriverDesc" `
                -Value "Intel(R) UHD Graphics 630" -Reason "Display adapter identity"
            Set-ValueSafe -Path $_.PSPath -Name "ProviderName" `
                -Value "Intel Corporation" -Reason "Display adapter provider"
        }
    }
}

# ============================================================
# Section 5: Network adapter strings
# VirtIO NIC appears as "Red Hat VirtIO Ethernet Adapter" in
# Win32_NetworkAdapter. Patching the driver INF (driver-rename.py)
# handles new installs; this section covers post-install cleanup.
# ============================================================
Write-Host "[5/6] Network adapter driver strings..."

$netClassGuid = "{4D36E972-E325-11CE-BFC1-08002BE10318}"
$netClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$netClassGuid"

if (Test-Path $netClassPath) {
    Get-ChildItem $netClassPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $desc = $props.DriverDesc
        if ($desc -match 'VirtIO|Red Hat|QEMU|Realtek.*Virtual') {
            Set-ValueSafe -Path $_.PSPath -Name "DriverDesc" `
                -Value "Intel(R) Ethernet Connection I219-V" -Reason "NIC identity"
            Set-ValueSafe -Path $_.PSPath -Name "ProviderName" `
                -Value "Intel Corporation" -Reason "NIC provider"
        }
    }
}

# ============================================================
# Section 6: Hyper-V / virtualization metadata
# Windows records virtualization metadata in several locations
# that can be queried to determine if running in a VM.
# ============================================================
Write-Host "[6/6] Hyper-V and virtualization metadata..."

$hvPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization"
)
foreach ($p in $hvPaths) { Remove-KeySafe -Path $p -Reason "Hyper-V guest metadata" }

# Clear Hyper-V-related values without removing the entire key
$hvKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$hvValues = @("VirtualizationBasedSecurityStatus")
foreach ($v in $hvValues) {
    if ((Get-ItemProperty $hvKey -Name $v -ErrorAction SilentlyContinue).$v -ne $null) {
        if (-not $DryRun) {
            Remove-ItemProperty -Path $hvKey -Name $v -Force -ErrorAction SilentlyContinue
        }
        $changes += [PSCustomObject]@{ Action="RemoveValue"; Path="$hvKey\$v"; Reason="Virtualization hint" }
    }
}

# ============================================================
# Summary
# ============================================================
Write-Host "`n[+] Done. $($changes.Count) changes made." -ForegroundColor Green
if ($DryRun) {
    Write-Host "    (Dry run — no actual modifications)" -ForegroundColor Yellow
}

$logPath = "$env:TEMP\registry-patch-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$changes | Export-Csv -Path $logPath -NoTypeInformation
Write-Host "[+] Change log: $logPath"
Write-Host "[!] Reboot the VM before running detection tools.`n" -ForegroundColor Cyan
