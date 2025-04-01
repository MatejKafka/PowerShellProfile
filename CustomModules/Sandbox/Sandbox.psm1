Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


class MappedFolder {
    [string]$HostFolder
    [string]$SandboxFolder
    [bool]$ReadOnly = $false
}

function x($TagName, [Parameter(ValueFromRemainingArguments)]$Rest) {
    return [System.Xml.Linq.XElement]::new([System.Xml.Linq.XName]$TagName, $Rest)
}

function add($Parent, $Element) {
    $Parent.Add($Element)
}


function MapSwitches($Config, $Switches) {
    function map($Key, $Negate = $false) {
        $SwitchName = if ($Negate) {"No" + $Key} else {$Key}
        $Value = $Switches[$SwitchName]
        if ($null -ne $Value) {
            $ValueStr = if ($Value -xor $Negate) {"Enable"} else {"Disable"}
            add $Config (x $Key $ValueStr)
        }
    }

    map vGPU
    map Networking $true
    map AudioInput $true
    map VideoInput
    map ProtectedClient
    map PrinterRedirection
    map ClipboardRedirection $true
}

# https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file
function New-SandboxConfig {
    param($MappedFolder, $LogonCommand, $MemoryInMB, $Switches)

    $Config = x "Configuration"

    MapSwitches $Config $Switches

    if ($MemoryInMB -ne 0) {
        add $Config (x MemoryInMB $MemoryInMB)
    }

    if ($LogonCommand) {
        add $Config (x LogonCommand (x Command $LogonCommand))
    }

    $mfs = foreach ($f in $MappedFolder) {
        x MappedFolder `
            (x HostFolder $f.HostFolder) `
            (x SandboxFolder $f.SandboxFolder) `
            (x ReadOnly $(if ($f.ReadOnly) {"true"} else {"false"}))
    }
    add $Config (x MappedFolders @mfs)


    $ConfigDoc = [System.Xml.Linq.XDocument]::new()
    $ConfigDoc.Add($Config)
    return $ConfigDoc
}

function Invoke-Sandbox {
    [CmdletBinding()]
    param(
        [MappedFolder[]]$MappedFolder = @(),

        [scriptblock]$LogonCommand,
        [switch]$VisibleWindow,
        [switch]$NoExit,

        [ulong]$MemoryInMB = 0,

        [switch]$vGPU,
        [switch]$NoNetworking,
        [switch]$NoAudioInput,
        [switch]$VideoInput,
        [switch]$ProtectedClient,
        [switch]$PrinterRedirection,
        [switch]$NoClipboardRedirection
    )

    $ConfigDir = mkdir "$env:TEMP\Sandbox-$(New-Guid)"
    try {
        if ($NoExit) {
            $VisibleWindow = $true
        }

        $ProcessedLogonCommand = if ($LogonCommand) {
            $LogonCommand.ToString() >$ConfigDir\LogonCommand.ps1
            $MappedFolder += [MappedFolder]@{HostFolder = $ConfigDir; SandboxFolder = "C:\_internal_shared"; ReadOnly = $true}

            $CmdStr = ""
            $CmdStr += if ($VisibleWindow) {"cmd /c start "}
            $CmdStr += "powershell "
            $CmdStr += if ($NoExit) {"-NoExit "}
            $CmdStr += "-NoProfile -ExecutionPolicy Bypass C:\_internal_shared\LogonCommand.ps1"
            $CmdStr
        }

        $Config = New-SandboxConfig $MappedFolder $ProcessedLogonCommand $MemoryInMB $PSBoundParameters
        $Config.Save("$ConfigDir\config.wsb")

        Write-Verbose "Config file: $ConfigDir\config.wsb"
        cat "$ConfigDir\config.wsb" | Write-Verbose

        $Cmd = gcm WindowsSandboxRemoteSession.exe, WindowsSandbox.exe -ErrorAction Ignore | select -First 1
        & $Cmd "$ConfigDir\config.wsb" | Out-Default
    } finally {
        rm -Force -Recurse -ErrorAction Ignore $ConfigDir
    }
}