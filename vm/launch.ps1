# vm/launch.ps1 — Windows launcher for the stealth VM
# Run in PowerShell as Administrator
# Edit vm\config.windows.ps1 before running

#Requires -RunAsAdministrator
param(
    [switch]$BasicDisplay,   # Use basic VirtIO display instead of VirtIO-GL
    [switch]$NoTPM,          # Skip TPM (use only if swtpm is unavailable)
    [switch]$NoStealth,      # Skip all anti-detection flags (for baseline testing)
    [switch]$InstallMode     # Boot from ISO for fresh Windows install
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load config
. "$ScriptDir\config.windows.ps1"

# ── Preflight ────────────────────────────────────────────────────────────────
if (-not (Test-Path $QemuExe)) {
    Write-Error "QEMU not found at: $QemuExe`nInstall from https://qemu.weilnetz.de/w64/"
    exit 1
}

if (-not (Test-Path $DiskImage)) {
    Write-Host "Disk image not found. Creating $DiskImageSizeGB GB image..."
    & $QemuImg create -f qcow2 $DiskImage "${DiskImageSizeGB}G"
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create disk image"; exit 1 }
    Write-Host "[OK] Disk image created: $DiskImage"
}

# ── Acceleration ─────────────────────────────────────────────────────────────
# WHPX = Windows Hypervisor Platform (fast, requires Hyper-V features enabled)
# HAXM = Intel HAXM (alternative for Intel CPUs)
# TCG  = software emulation (slow but universal fallback)
$AccelFlag = "-accel whpx,kernel-irqchip=off"
try {
    $whpxTest = & $QemuExe -accel whpx,kernel-irqchip=off -machine none -nographic 2>&1
    if ($whpxTest -match "WHPX|Failed") { throw }
    Write-Host "[*] Acceleration: WHPX (Windows Hypervisor Platform)"
} catch {
    Write-Host "[!] WHPX not available. Falling back to TCG (software — will be slow)."
    Write-Host "    To enable WHPX: Control Panel → Programs → Turn Windows features on/off"
    Write-Host "    Enable: 'Windows Hypervisor Platform' and 'Hyper-V'"
    $AccelFlag = "-accel tcg,thread=multi"
}

# ── OVMF firmware ─────────────────────────────────────────────────────────────
if (-not (Test-Path $OvmfVars)) {
    Write-Host "[*] Copying OVMF VARS template..."
    $OvmfVarsDir = Split-Path $OvmfVars
    if (-not (Test-Path $OvmfVarsDir)) { New-Item -ItemType Directory -Path $OvmfVarsDir | Out-Null }
    Copy-Item $OvmfVarsTemplate $OvmfVars
}

# ── ACPI table ────────────────────────────────────────────────────────────────
$AcpiArgs = @()
if ($StealthAcpi -and -not $NoStealth) {
    $AmlPath = "$ScriptDir\acpi\SSDT-fake-battery.aml"
    if (-not (Test-Path $AmlPath)) {
        Write-Host "[*] Compiling ACPI table..."
        & iasl "$ScriptDir\acpi\SSDT-fake-battery.dsl" -o $AmlPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] iasl not found or failed — skipping fake battery ACPI."
            Write-Host "    Install: https://acpica.org/downloads"
        }
    }
    if (Test-Path $AmlPath) {
        $AcpiArgs = @("-acpitable", "file=$AmlPath")
        Write-Host "[*] ACPI: fake battery SSDT loaded"
    }
}

# ── ISO drives ────────────────────────────────────────────────────────────────
$IsoArgs = @()
if ($InstallMode -or (Test-Path $WinISO)) {
    if (Test-Path $WinISO) {
        $IsoArgs += @("-drive", "file=$WinISO,media=cdrom,index=0,readonly=on")
        Write-Host "[*] ISO: $WinISO"
    }
    if (Test-Path $VirtioISO) {
        $IsoArgs += @("-drive", "file=$VirtioISO,media=cdrom,index=1,readonly=on")
        Write-Host "[*] VirtIO ISO: $VirtioISO"
    }
}

# ── TPM ────────────────────────────────────────────────────────────────────────
$TpmArgs = @()
if (-not $NoTPM) {
    $SwtpmSock = "$env:TEMP\swtpm-sock"
    if (-not (Test-Path $SwtpmSock) -and (Get-Command swtpm -ErrorAction SilentlyContinue)) {
        Write-Host "[*] Starting swtpm..."
        $SwtpmState = "$env:TEMP\swtpm-state"
        New-Item -ItemType Directory -Path $SwtpmState -Force | Out-Null
        Start-Process -FilePath "swtpm" `
            -ArgumentList "socket --tpmstate dir=$SwtpmState --ctrl type=unixio,path=$SwtpmSock --tpm2" `
            -WindowStyle Hidden
        Start-Sleep -Milliseconds 500
    }
    if (Test-Path $SwtpmSock) {
        $TpmArgs = @(
            "-chardev", "socket,id=chrtpm,path=$SwtpmSock",
            "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
            "-device", "tpm-tis,tpmdev=tpm0"
        )
        Write-Host "[*] TPM: swtpm connected"
    } else {
        Write-Host "[!] TPM socket not found. Use -NoTPM flag, or install swtpm."
        Write-Host "    Without TPM, Windows 11 install will fail — use Windows 10 or bypass TPM."
        Write-Host "    TPM bypass: during install, press Shift+F10 and run:"
        Write-Host "    reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1"
    }
}

# ── Anti-detection CPU/feature args ──────────────────────────────────────────
$CpuArgs = @("-cpu", "max,hypervisor=off,+invtsc,+rdtscp,hv-vendor-id=AuthenticAMD")
$FeatureArgs = @()
if ($NoStealth) {
    $CpuArgs = @("-cpu", "qemu64")
    Write-Host "[*] Stealth: OFF (baseline mode)"
} else {
    Write-Host "[*] Stealth: ON (all anti-detection flags active)"
}

# ── Networking ────────────────────────────────────────────────────────────────
# User-mode networking: no TAP driver required. The VM can reach the internet.
# MAC is set to Dell OUI regardless.
$NetArgs = @(
    "-netdev", "user,id=net0,hostfwd=tcp::3389-:3389",
    "-device", "e1000e,netdev=net0,mac=$MacAddr"
)

# ── Display ───────────────────────────────────────────────────────────────────
$DisplayArgs = @("-device", "virtio-vga", "-display", "gtk")
if (-not $BasicDisplay) {
    # virtio-vga-gl requires Mesa/virgl on the host.
    # On Windows, OpenGL passthrough via virgl is not yet fully supported.
    # Use SDL display for best compatibility on Windows host.
    $DisplayArgs = @("-device", "virtio-vga", "-display", "sdl")
    Write-Host "[*] Display: SDL (virtio-vga)"
    Write-Host "    Note: For WebGL renderer passthrough (Proctorio), GPU passthrough is needed."
    Write-Host "    See docs/13-lockdown-browsers.md for details."
}

# ── SMBIOS ────────────────────────────────────────────────────────────────────
$SmbiosArgs = @()
if (-not $NoStealth) {
    $SmbiosArgs = @(
        "-smbios", 'type=0,vendor=Dell Inc.,version=1.18.0,date=11/02/2022,release=1.18',
        "-smbios", "type=1,manufacturer=Dell Inc.,product=OptiPlex 7090,version=Not Specified,serial=ABCD1234,uuid=44454C4C-4700-1052-8050-C3C04F325931,sku=OptiPlex 7090,family=OptiPlex",
        "-smbios", 'type=2,manufacturer=Dell Inc.,product=0TT6JF,version=A01,serial=CN7692370D05F5.',
        "-smbios", 'type=3,manufacturer=Dell Inc.,version=Not Specified,serial=ABCD1234',
        "-smbios", 'type=4,sock_pfx=CPU,manufacturer=Intel,version=Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz,max-speed=4800,current-speed=2900',
        "-smbios", 'type=17,manufacturer=Samsung,serial=87654321,asset=Not Specified,part=M378A1K43EB2-CWE,speed=3200'
    )
}

# ── Build full argument list ──────────────────────────────────────────────────
$QemuArgs = @(
    "-machine", "q35,smm=on",
    $AccelFlag.Split(" "),
    "-m", $VmRam,
    "-smp", "$VmCores,cores=$VmCoresPerSocket,threads=$VmThreads,sockets=$VmSockets"
) + $CpuArgs + @(
    "-drive", "if=pflash,format=raw,readonly=on,file=$OvmfCode",
    "-drive", "if=pflash,format=raw,file=$OvmfVars",
    "-drive", "file=$DiskImage,format=qcow2,if=none,id=drive0,cache=writeback,discard=unmap",
    "-device", "nvme,drive=drive0,serial=S4EWNX0R123456,model=Samsung SSD 970 EVO Plus 1TB"
) + $IsoArgs + @(
    "-boot", "order=dc"
) + $NetArgs `
  + $DisplayArgs `
  + $SmbiosArgs `
  + $AcpiArgs `
  + $TpmArgs `
  + @(
    "-rtc", "base=localtime,clock=host,driftfix=slew",
    "-no-hpet",
    "-global", "kvm-pit.lost_tick_policy=delay",
    "-device", "usb-ehci,id=ehci",
    "-device", "usb-hub,bus=ehci.0",
    "-device", "usb-tablet",
    "-serial", "none",
    "-parallel", "none",
    "-monitor", "stdio"
)

Write-Host "`n[*] Launching QEMU..."
Write-Host "    $QemuExe $($QemuArgs -join ' ')`n"

& $QemuExe @QemuArgs
