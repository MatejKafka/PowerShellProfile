#Requires -Modules Wait-FileChange, Format-TimeSpan, ScratchFile, Oris, Recycle, Invoke-Notepad, TODO
Set-StrictMode -Version Latest


$RSS_FEED_FILE = "$PSScriptRoot/../data/rssFeeds.txt"
$TODO_FILE = "$PSScriptRoot/../data/todos.json"

Initialize-Todo $TODO_FILE


New-Alias ipy ipython
# where is masked by builtin alias for Where-Object
New-Alias which where.exe
New-Alias py python3.exe
New-Alias python python3.exe

Remove-Alias rm
New-Alias rm Remove-ItemSafely
New-Alias rmp Remove-Item

New-Alias / Invoke-Scratch
New-Alias // Invoke-LastScratch
New-Alias env Update-EnvVar
New-Alias venv Activate-Venv
New-Alias todo New-Todo
New-Alias npp Invoke-Notepad
New-Alias e Push-ExplorerLocation
New-Alias c Push-ClipboardLocation

function rss($DaysSince = 14) {
	if (-not (Test-Path $RSS_FEED_FILE)) {
		throw "The RSS feed file does not exist: '$RSS_FEED_FILE'"
	}
	$Since = [DateTime]::Today.AddDays(-$DaysSince)
	Read-RSSFeedFile $RSS_FEED_FILE | Invoke-RSS -Since $Since -NoAutoSelect
}

function rss-edit {
	npp $RSS_FEED_FILE
}

function Resolve-VirtualPath {
	param([Parameter(Mandatory)]$Path)
	return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function code {
	param(
			[Parameter(ValueFromPipeline)]
			[string]
		$File
	)
	& (gcm code -CommandType Application) (Resolve-VirtualPath $File)
}

function cal {
	Set-Notebook CALENDAR
}

function history-npp {
	npp (Get-PSReadLineOption).HistorySavePath
}

function make {
	wsl -- bash -ic "make $Args"
}

function manl {
	wsl -- man @Args
}

function Sleep-Computer {
	Add-Type -AssemblyName System.Windows.Forms
	$null = [System.Windows.Forms.Application]::SetSuspendState("Suspend", $false, $false)
}

class _CwdLnkShortcuts : System.Management.Automation.IValidateSetValuesGenerator {
	[String[]] GetValidValues() {
		return ls -File -Filter "./*.lnk" | Select-Object -ExpandProperty Name
	}
}

function lnk {
	param(
			[Parameter(Mandatory)]
			[ValidateSet([_CwdLnkShortcuts])]
			[string]
		$LnkPath
	)
	$Lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Resolve-Path $LnkPath))
	cd -LiteralPath $Lnk.TargetPath
}

class _WifiNames : System.Management.Automation.IValidateSetValuesGenerator {
	[String[]] GetValidValues() {
		return ((netsh.exe wlan show profile) -match '\s{2,}:\s') -replace '.*:\s' , ''
	}
}

function Get-Wifi {
	param(
			[ValidateSet([_WifiNames])]
			[string]
		$Name
	)
	
	if ([string]::IsNullOrEmpty($Name)) {
		return [_WifiNames]::new().GetValidValues() | % {
			Get-Wifi $_
		}
	}
	
	$Out = netsh.exe wlan show profile $Name key=clear
	$PasswordLine = $Out -match ".*    Key Content.*"
	return [PSCustomObject]@{
		Name = $Name
		Authentication = ($Out -match '.*    Authentication.*')[0] -replace '.*:\s', ''
		Password = if ($PasswordLine) {$PasswordLine[0] -replace '.*:\s', ''} else {$null}
	}
}

function Push-ExplorerLocation {
	$Dirs = Get-ExplorerDirectories
	$Selected = Read-HostListChoice $Dirs -Prompt "Select directory to cd to:" `
			-NoInputMessage "No explorer windows found."
	Push-Location $Selected
}

function Push-ClipboardLocation {
	$clip = Get-Clipboard
	if (Test-Path -Type Container $clip) {
		Push-Location $clip
	} elseif (Test-Path -Type Leaf $clip) {
		Push-Location (Split-Path $clip)
	} else {
		throw "Not a valid path"
	}
}

function Test-SshConnection {
	param(
			[Parameter(Mandatory)]
			[string]
		$Login,
			[ValidateScript({Test-Path $_})]
			[string]
		$KeyFilePath
	)
	
	$OrigLEC = $LastExitCode
	$Arg = if ([string]::IsNullOrEmpty($KeyFilePath)) {@()} else {@("-i", $KeyFilePath)}
	try {
		$null = $(ssh $Login -o PasswordAuthentication=no @Arg exit) 2>&1
		return $LastExitCode -eq 0
	} catch {
		return $False
	} finally {
		$LastExitCode = $OrigLEC
	}
}

function Copy-SshId {
	param(
			[Parameter(Mandatory)]
			[string]
		$Login,
			[Parameter(Mandatory)]
			[ValidateScript({Test-Path $_})]
			[string]
		$KeyFilePath
	)
	
	$PubKeyPath = if ([IO.Path]::GetExtension($KeyFilePath) -eq "") {
		$KeyFilePath + ".pub"
	} else {
		$KeyFilePath
	}
	
	$KeyFilePath = Resolve-Path $KeyFilePath
	
	Write-Verbose "Testing if key is already installed..."
	if (Test-SSHConnection $Login $KeyFilePath) {
		return "Key already installed."
	}

	Write-Verbose "Installing key..."
	Get-Content $PubKeyPath | ssh $Login "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
	if ($LastExitCode -gt 0) {
		throw "Could not install public key for '$Login'."
	}
	Write-Verbose "Public key successfully installed for '$Login', trying to log in..."
	if (Test-SSHConnection $Login $KeyFilePath) {
		return "Key successfully installed."
	}
	throw "Key installation failed."
}

function ssh-config {
	npp $env:HOME\.ssh\config
}

function Out-Tcp {
	param(
			[Parameter(Mandatory)]
			[string]
		$Host,
			[Parameter(Mandatory)]
			[int]
		$Port,
			[Parameter(Mandatory, ValueFromPipeline)]
			[string]
		$Message
	)
	
	begin {
		$sock = New-Object System.Net.Sockets.TcpClient
		$enc = New-Object System.Text.UTF8Encoding
		$sock.Connect($Host, $Port)
		$stream = $sock.GetStream()
	}
	process {
		$bytes = $enc.GetBytes($Message)
		[void]$stream.Write($bytes, 0, $bytes.Length)
	}
	end {$sock.Close()}
}

function Out-Udp {
	param(
			[Parameter(Mandatory)]
			[string]
		$Host,
			[Parameter(Mandatory)]
			[int]
		$Port,
			[Parameter(Mandatory, ValueFromPipeline)]
			[string]
		$Message,
			<# Wait for a reply after each sent packet. Only use on reliable networks,
			   as this blocks forever in case the reply packet is lost. #>
			[switch]
		$WaitForReply,
			<# Add a newline (\n) to each outgoing packet, and strip a single trailing newline from incoming packets, if present. #>
			[switch]
		$Newlines
	)
	
	begin {
		$sock = New-Object System.Net.Sockets.UdpClient
		$enc = New-Object System.Text.UTF8Encoding
		$sock.Connect($Host, $Port)
		# dummy for receiving, not used anywhere
		$remoteHost = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
	}
	process {
		if ($Newlines) {$Message = $Message + "`n"}
		$bytes = $enc.GetBytes($Message)
		[void]$sock.Send($bytes, $bytes.Length)
		if ($WaitForReply) {
			# TODO: handle decoding error
			$replyStr = $enc.GetString($sock.Receive([ref]$remoteHost))
			if ($Newlines) {
				echo ($replyStr -replace "`n$") # remove trailing newline, if any
			} else {
				echo $replyStr
			}
		}
	}
	end {$sock.Close()}
}

function ip {
	Get-NetIPAddress
		| ? {$_.AddressFamily -eq "IPv4" -and $_.SuffixOrigin -in @("Dhcp", "Manual") `
			-and !$_.InterfaceAlias.StartsWith("vEthernet")}
		| select InterfaceAlias, IPAddress
}

function oris {
	Get-OrisEnrolledEvents | Format-OrisEnrolledEvents
}

function BulkRename() {
	[array]$Items = ls @Args
	if ($null -eq $Items) {throw "No items to rename"}
	$TempFile = New-TemporaryFile
	$Items | select -ExpandProperty Name | Out-File $TempFile
	npp $TempFile
	[array]$NewNames = cat $TempFile
	rm $TempFile
	if ($Items.Count -ne $NewNames.Count) {
		throw "You must not add, delete or reorder lines"
	}
	
	$Renamed = 0
	for ($i = 0; $i -lt $Items.Count; $i++) {
		if ($Items[$i].Name -ne $NewNames[$i]) {
			Rename-Item $Items[$i] $NewNames[$i]
			$Renamed++
		}
	}
	Write-Host "Renamed $Renamed items."
}

function Activate-Venv([string]$VenvName) {
	if ("" -eq $VenvName) {
		$path = ".\venv\Scripts\Activate.ps1"
	} else {
		$path = ".\$VenvName\Scripts\Activate.ps1"
	}

	$dir = Get-Location
	while (-not (Test-Path (Join-Path $dir $path))) {
		$dir = Split-Path $dir
		if ($dir -eq "") {
			throw "No venv found."
		}
	}
	& (Join-Path $dir $path)
	echo "Activated venv in '$dir'."
}


function Get-ProcessHistory($Last = 10) {
	Get-WinEvent Security |
		where id -eq 4688 |
		select -First $Last |
		select TimeCreated, @{Label = "Command"; Expression = {$_.Properties[8].Value}}
}


function Update-EnvVar {
	param(
			[Parameter(Mandatory)]
			[string]
		$VarName
	)
	
	$Machine = [Environment]::GetEnvironmentVariable($VarName, [EnvironmentVariableTarget]::Machine)
	$User = [Environment]::GetEnvironmentVariable($VarName, [EnvironmentVariableTarget]::User)
	
	$Value = if ($null -eq $Machine -or $null -eq $User) {
		[string]($Machine + $User)
	} else {
		$Machine + [IO.Path]::PathSeparator + $User
	}
	[Environment]::SetEnvironmentVariable($VarName, $Value)
}


#function Pause {
#	Write-Host -NoNewLine 'Press any key to continue...'
#	$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
#}


# function sudo {
#	Start-Process -Verb RunAs -FilePath "pwsh" -ArgumentList (@("-NoExit", "-Command") + $args)
# }


function Update-PowerShell([switch]$Stable) {
	$InstallerScript = Invoke-RestMethod https://aka.ms/install-powershell.ps1
	$Installer = [ScriptBlock]::Create($InstallerScript)
	if ($Stable) {
		& $Installer -UseMSI
	} else {
		& $Installer -UseMSI -Preview
	}
	#Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Preview"
}


function Get-CmdExecutionTime($index=-1) {
	$cmd = (Get-History)[$index]
	$executionTime = $cmd.EndExecutionTime - $cmd.StartExecutionTime
	return Format-TimeSpan $executionTime
}


Export-ModuleMember -Function * -Cmdlet * -Alias *