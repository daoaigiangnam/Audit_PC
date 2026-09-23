Set-StrictMode -Version Latest

function Get-FirstValue {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) {
        if ($null -ne $Object) {
            $p = $Object.PSObject.Properties[$name]
            if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
        }
    }
    return $null
}

function Get-InstalledSoftware {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $items = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            ForEach-Object {
                [pscustomobject]@{
                    name = $_.DisplayName
                    version = $_.DisplayVersion
                    publisher = $_.Publisher
                    install_date = $_.InstallDate
                    estimated_size = $_.EstimatedSize
                }
            }
    }
    return @($items | Sort-Object name,version,publisher -Unique)
}

function Get-NetworkInventory {
    $rows = @()
    $configs = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue
    foreach ($cfg in $configs) {
        $adapter = Get-CimInstance Win32_NetworkAdapter -Filter "Index=$($cfg.Index)" -ErrorAction SilentlyContinue
        $desc = [string]$cfg.Description
        $name = if ($adapter) { [string]$adapter.NetConnectionID } else { $desc }
        $type = 'OTHER'
        if ($desc -match 'Wi-?Fi|Wireless|802\.11') { $type = 'WIFI' }
        elseif ($desc -match 'WWAN|Cellular|LTE|5G|4G|Mobile Broadband|Modem|Fibocom|Quectel|Sierra Wireless|Telit') { $type = 'MODEM' }
        elseif ($desc -match 'Ethernet|Gigabit|PCIe|Realtek|Intel.*Ethernet') { $type = 'LAN' }
        $rows += [pscustomobject]@{
            type = $type
            name = $name
            description = $desc
            ipv4 = @($cfg.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
            gateway = @($cfg.DefaultIPGateway)
            mac = $adapter.MACAddress
            dns = @($cfg.DNSServerSearchOrder)
            dhcp = if ($cfg.DHCPEnabled) { 'Enabled' } else { 'Disabled' }
            connection_status = if ($adapter.NetConnectionStatus -eq 2) { 'Connected' } else { [string]$adapter.NetConnectionStatus }
            link_speed = $adapter.Speed
        }
    }
    return @($rows)
}

function Get-AuditInventory {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $biosObj = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $base = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1

    $memory = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            capacity = [math]::Round($_.Capacity / 1GB, 2)
            speed = $_.Speed
            slot = $_.DeviceLocator
            manufacturer = $_.Manufacturer
            part_number = $_.PartNumber
            serial_number = $_.SerialNumber
        }
    })

    $storage = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            drive = $_.DeviceID
            used_gb = [math]::Round((($_.Size - $_.FreeSpace) / 1GB), 2)
            total_gb = [math]::Round(($_.Size / 1GB), 2)
        }
    })

    $monitors = @(Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            manufacturer = (([char[]]$_.ManufacturerName | Where-Object { $_ -ne [char]0 }) -join '')
            model = (([char[]]$_.UserFriendlyName | Where-Object { $_ -ne [char]0 }) -join '')
            serial_number = (([char[]]$_.SerialNumberID | Where-Object { $_ -ne [char]0 }) -join '')
        }
    })

    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            vram = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1GB, 2) } else { $null }
            driver_version = $_.DriverVersion
        }
    })

    $battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ name=$_.Name; status=$_.Status; charge_percent=$_.EstimatedChargeRemaining }
    })

    $network = @(Get-NetworkInventory)

    $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ display_name=$_.displayName; status=$_.productState; executable_path=$_.pathToSignedProductExe; signature_version=$null }
    })
    if ($av.Count -eq 0) {
        $def = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($def) { $av = @([pscustomobject]@{ display_name='Microsoft Defender'; status=$def.AntivirusEnabled; executable_path=$null; signature_version=$def.AntivirusSignatureVersion }) }
    }

    $bitlocker = @()
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $bitlocker = @(Get-BitLockerVolume -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ mount_point=$_.MountPoint; protection_status=[string]$_.ProtectionStatus; volume_status=[string]$_.VolumeStatus; encryption_percent=$_.EncryptionPercentage }
        })
    }

    $firewall = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ profile=$_.Name; enabled=$_.Enabled }
    })

    $tpmObj = Get-Tpm -ErrorAction SilentlyContinue
    $tpm = if ($tpmObj) { [pscustomobject]@{ present=$tpmObj.TpmPresent; ready=$tpmObj.TpmReady; manufacturer_version=$tpmObj.ManufacturerVersion } } else { $null }
    $secureBoot = try { [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $null }

    $windowsLicense = @(Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND LicenseStatus IS NOT NULL" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Windows' } | ForEach-Object {
        [pscustomobject]@{ product_type='Windows'; product_name=$_.Name; status=$_.LicenseStatus; partial_product_key=$_.PartialProductKey }
    })
    $officeLicense = @(Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue | Where-Object { $_.PartialProductKey -and $_.Name -match 'Office|Microsoft 365' } | ForEach-Object {
        [pscustomobject]@{ product_type='Office'; product_name=$_.Name; status=$_.LicenseStatus; partial_product_key=$_.PartialProductKey }
    })

    $lastBoot = if ($os) { $os.LastBootUpTime } else { $null }
    $uptime = if ($lastBoot) { (Get-Date) - $lastBoot } else { $null }

    return @{
        username = $env:USERNAME
        domain = if ($cs) { $cs.Domain } else { $env:USERDOMAIN }
        computer_name = $env:COMPUTERNAME
        manufacturer = if ($cs) { $cs.Manufacturer } else { $null }
        model = if ($cs) { $cs.Model } else { $null }
        serial_number = if ($base) { $base.IdentifyingNumber } else { $null }
        asset_tag = (Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SMBIOSAssetTag -First 1)
        mainboard = if ($board) { @{ manufacturer=$board.Manufacturer; product=$board.Product; serial_number=$board.SerialNumber } } else { $null }
        bios = if ($biosObj) { @{ version=$biosObj.SMBIOSBIOSVersion; date=$biosObj.ReleaseDate } } else { $null }
        cpu = if ($cpu) { @{ name=$cpu.Name; cores=$cpu.NumberOfCores; threads=$cpu.NumberOfLogicalProcessors; max_clock=$cpu.MaxClockSpeed } } else { $null }
        memory = $memory
        storage = $storage
        monitors = $monitors
        gpu = $gpu
        battery = $battery
        windows = if ($os) { @{ caption=$os.Caption; version=$os.Version; build=$os.BuildNumber; architecture=$os.OSArchitecture } } else { $null }
        operating_system = if ($os) { @{ caption=$os.Caption; version=$os.Version; build=$os.BuildNumber; architecture=$os.OSArchitecture } } else { $null }
        windows_update = $null
        last_boot = $lastBoot
        uptime = if ($uptime) { [string]$uptime } else { $null }
        network = $network
        antivirus = $av
        bitlocker = $bitlocker
        firewall = $firewall
        tpm = $tpm
        secure_boot = $secureBoot
        licenses = @($windowsLicense + $officeLicense)
        software = @(Get-InstalledSoftware)
        hardware = @{ manufacturer=if($cs){$cs.Manufacturer}; model=if($cs){$cs.Model}; serial_number=if($base){$base.IdentifyingNumber}; asset_tag=(Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SMBIOSAssetTag -First 1) }
        other = @{}
        collected_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}
