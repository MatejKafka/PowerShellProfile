Set-StrictMode -Version Latest


Set-Alias ipy ipython
Set-Alias rms Remove-ItemSafely
Set-Alias man Get-ConciseHelp

if ($IsWindows) {
	# where is masked by builtin alias for Where-Object
	Set-Alias which where.exe
	Set-Alias py python.exe

	Set-Alias grep Select-String
}


Set-Alias / Invoke-Scratch
Set-Alias // Invoke-LastScratch
Set-Alias venv Activate-Venv
Set-Alias npp Invoke-Notepad
Set-Alias e Push-ExternalLocation
Set-Alias o Open-TextFile

$global:PSDefaultParameterValues["Launch-VsDevShell.ps1:Arch"] = "amd64"
$global:PSDefaultParameterValues["Launch-VsDevShell.ps1:SkipAutomaticLocation"] = $true
"C:\Program Files", "C:\Program Files (x86)" `
	| % {gi "$_\Microsoft Visual Studio\2022\*\Common7\Tools\Launch-VsDevShell.ps1" -ErrorAction Ignore} `
	| select -First 1 `
	| % {Set-Alias msvc $_.FullName}


function .. {
	cd ..
}

<# "mkdir and enter" #>
function mke($Path) {
	cd -LiteralPath (mkdir $Path)
}

<# remove dir and cd .. #>
function rme {
	$wd = Get-Location
	cd ..
	rm -Recurse -Force $wd
}

function rmf {
	rm -Recurse -Force @Args -ErrorAction Ignore
}

function touch {
	(gi @Args).LastWriteTime = Get-Date
}

function gits {
	git status @Args
}
function gitd {
	git diff @Args
}
function gitdc {
	git diff --cached @Args
}
function gitl {
	git log @Args
}
function gitp {
	git push @Args
}
function gitpf {
	git push --force
}
function gitri {
	$HasChanges = git status --porcelain
	if ($HasChanges) {
		git add -A
		git stash
	}

	try {
		git rebase -i @Args
	} finally {
		if ($HasChanges) {
			$GitDir = git rev-parse --git-dir
			if (Test-Path $GitDir\rebase-merge) {
				# on-going merge
				Write-Warning "Restore working tree changes when rebase is finished."
			} else {
				git stash pop
				git reset
			}
		}
	}
}


function og {
	o -Gui @Args
}

function mklink {
	param(
		[Parameter(Mandatory)][string]$Path,
		[Parameter(Mandatory)][string]$Target
	)

	$Path = Resolve-VirtualPath $Path
	$Target = ($Target -replace "/", "\").TrimEnd([char]"\")

	$ResolvedTarget = [System.IO.Path]::Combine((Split-Path $Path), $Target)
	if (Test-Path -Type Container $ResolvedTarget) {
		[System.IO.Directory]::CreateSymbolicLink($Path, $Target)
	} elseif (Test-Path -Type Leaf $ResolvedTarget) {
		[System.IO.File]::CreateSymbolicLink($Path, $Target)
	} else {
		throw "Target does not exist: $ResolvedTarget"
	}
}

function rcp {
	param(
		[Parameter(Mandatory)][string[]]$Path,
		<# EXAMPLE: user@domain.com:~/path/to/target #>
		[Parameter(Mandatory)][string]$Destination
	)

	# remove trailing slash, tar does not like it
	$Path = ($Path -replace "\\", "/") -replace "/$"
	$SshHost, $DestinationPath = $Destination -split ":", 2
	$DestinationPath = $DestinationPath -replace "\\", "/"

	# needs $PSNativeCommandPreserveBytePipe feature (iirc default since 7.4)
	# quoted to work around the dumb `PSNativeWindowsTildeExpansion` experimental feature
	ssh $SshHost rm -r "$DestinationPath/*"
	tar czf - $Path | ssh $SshHost tar xvzfC - "$DestinationPath"
}

function Get-GithubVersion([string[]]$Repo) {
	foreach ($r in $Repo) {
		Get-GithubRelease $r | select -First 1 | % tag_name
			| % {if ($_ -like "v*") {$_.Substring(1)} else {$_}}
	}
}

function todo([string]$TodoText) {
	if ([string]::IsNullOrEmpty($TodoText)) {
		Write-HostColor "TODO:" -ForegroundColor "#909060"
		Get-Todo | % {" $_"} | Write-HostColor -ForegroundColor "#909060"
	} else {
		New-Todo $TodoText
	}
}

function find($Pattern, $Path = ".", $Context = 0, [switch]$CaseSensitive) {
	ls -Recurse -File $Path | ? {$_.Target -eq $null}
		| Select-String $Pattern -Context $Context -CaseSensitive:$CaseSensitive -ErrorAction Continue
}

function findo($Pattern, $Path = ".", $Context = 0, [switch]$CaseSensitive, [switch]$Gui) {
	$Path = Resolve-Path $Path
	find $Pattern $Path $Context -CaseSensitive:$CaseSensitive
		| Read-HostListChoice -FormatSb {$_.ToEmphasizedString($Path)}
		| % {o $_.Path $_.LineNumber -Gui:$Gui}
}

function reflect {
	[CmdletBinding()]
	param(
			[Parameter(Mandatory)]
		$Object,
			[Parameter(Mandatory)]
			[ArgumentCompleter({
				param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)

				if ($FakeBoundParameters.ContainsKey("Object")) {
					return $FakeBoundParameters["Object"].GetType().GetMembers([System.Reflection.BindingFlags]"NonPublic,Public,Instance") `
						| ? {-not ($_.Attributes -band [System.Reflection.MethodAttributes]::SpecialName) -and $_.Name -notlike "<*>k__BackingField"} `
						| % Name | select -Unique
				}
			})]
			[string]
		$Name,
			[Parameter(ValueFromRemainingArguments)]
		$Args
	)

	$Members = $Object.GetType().GetMember($Name, [System.Reflection.BindingFlags]"NonPublic,Public,Instance")
	if (-not $Members) {
		throw "Member not found."
	}

	if ($Members[0] -is [System.Reflection.PropertyInfo] -or $Members[0] -is [System.Reflection.FieldInfo]) {
		if (-not $Args) {
			# use WriteObject, ordinary return would unroll any enumerables
			$PSCmdlet.WriteObject($Members[0].GetValue($Object), $false)
		} elseif (@($Args).Count -eq 1) {
			$PSCmdlet.WriteObject($Members[0].SetValue($Object, $Args[0]), $false)
		} else {
			throw "Too many arguments for a property setter."
		}

	} elseif ($Members[0] -is [System.Reflection.MethodInfo]) {
		if (@($Members).Count -ne 1) {
			throw "Multiple matching method overloads, overload resolution is not currently supported."
		}

		$PSCmdlet.WriteObject($Members[0].Invoke($Object, $Args), $false)
	}
}

function Get-LatestEmail($HowMany, $ConfigFile) {
	$Server = Connect-EmailServer -FilePath $ConfigFile
	$Folder = $Server.Emails
	$CurrentDate = Get-Date
	$Folder.Fetch([math]::Max($Folder.Count - $HowMany, 0), -1, [MailKit.MessageSummaryItems]::Envelope)
		| % Envelope
		| % {[pscustomobject]@{
			Age = Format-Age $_.Date.DateTime $CurrentDate
			Sender = $_.From.Name ?? $_.From.Address
			Subject = $_.Subject
		}}
}

function pinvoke {
	[CmdletBinding()]
	param([array]$Signature, $ClassName = "Win32")

	$Usings = @("System", "System.Text", "System.Runtime.InteropServices")
	if ($(try {[Microsoft.Win32.SafeHandles.SafeFileHandle]} catch {})) {
		$Usings += @("Microsoft.Win32.SafeHandles")
	}

	$DefStr = ""
	$Usings | % {$DefStr += "using $_;`n"}
	$DefStr += "`n"
	$DefStr += "public static partial class $ClassName {`n"

	$Signature | % {
		$Dll, $Signature = if ($_.Trim() -match "\[(.*?)\.dll\]\s*(.*)") {
			$Matches[1], $Matches[2]
		} else {
			"kernel32.dll", $_
		}
		$DefStr += "    [DllImport(`"$Dll`")]`n"
		$DefStr += "    public static extern $Signature;`n"
	}

	$DefStr += "`n}"
	Write-Verbose "`n$DefStr"
	Add-Type $DefStr
}



<# Open current directory in Altap Salamander. #>
function so([ValidateSet("Left", "Right", "Active", "L", "R", "A")]$Pane = "Right", $Path = (Get-Location)) {
	& "C:\Program Files\Altap Salamander\salamand.exe" $(switch -Wildcard ($Pane) {
		L* {"-O", "-P", 1, "-L", $Path}
		R* {"-O", "-P", 2, "-R", $Path}
		A* {"-O", "-A", $Path}
	})
}
<# Set current directory to the dir open in Altap Salamander. #>
function s {
	Get-AltapSalamanderDirectory | select -First 1 | % FullName | Set-Location
}

# source: https://github.com/sethvs/sthArgumentCompleter/blob/master/sthArgumentCompleterFunctions.ps1
function Get-ArgumentCompleter
{
	Param (
		[switch]$Native,
		[switch]$Custom
	)

	if (-not $Native -and -not $Custom) {
		$Native = $true
		$Custom = $true
	}

	$flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
	$_context = $ExecutionContext.GetType().GetField('_context',$flags).GetValue($ExecutionContext)

	if ($Custom) {
		$_context.GetType().GetProperty('CustomArgumentCompleters',$flags).GetValue($_context)
	}
	if ($Native) {
		$_context.GetType().GetProperty('NativeArgumentCompleters',$flags).GetValue($_context)
	}
}

function Resolve-VirtualPath {
	param([Parameter(Mandatory)]$Path)
	return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function make {
	wsl -- bash -ic "make $Args"
}

function manl {
	wsl -- man @Args
}

function w {
	$WslArgs = @($Args | % {$_.ToString().Replace("\", "/")})
	wsl -- @WslArgs
}

function wcmake([ValidateSet("Release", "Debug", "RelWithDebInfo", "MinSizeRel")][string]$BuildType = "Release", [switch]$Clang, [switch]$Verbose, [switch]$Force) {
	$BuildDir = "cmake-build-$($BuildType.ToLowerInvariant())$(if ($Clang) {"-clang"})"

	if ($Force -and (Test-Path $BuildDir)) {
		rm -Recurse $BuildDir
	}

	$Args = if ($Clang) {@("-DCMAKE_C_COMPILER=clang", "-DCMAKE_CXX_COMPILER=clang++")} else {@()}

	if (-not (Test-Path $BuildDir)) {
		echo "cmake -S . -B $BuildDir -G Ninja -DCMAKE_BUILD_TYPE=$BuildType $($Args -join " ")"
		wsl -- cmake -S . -B $BuildDir -G Ninja "-DCMAKE_BUILD_TYPE=$BuildType" @Args
	}
	echo "cmake --build $BuildDir $($Verbose ? "--verbose" : $null)"
	wsl -- cmake --build $BuildDir $($Verbose ? "--verbose" : $null)
}

function Sleep-Computer {
	Add-Type -AssemblyName System.Windows.Forms
	$null = [System.Windows.Forms.Application]::SetSuspendState("Suspend", $false, $false)
}

function Get-SleepEvent {
	Get-WinEvent -ProviderName Microsoft-Windows-Kernel-Power, Microsoft-Windows-Power-Troubleshooter
		| ? Id -in 1, 41, 42
		| select TimeCreated, Message -First 30
}

class _CwdLnkShortcuts : System.Management.Automation.IValidateSetValuesGenerator {
	[string[]] GetValidValues() {
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
		return Get-WiFiProfile | % ProfileName
	}
}

function Get-Wifi {
	param(
			[ValidateSet([_WifiNames])]
			[string]
		$Name
	)
	return Get-WifiProfile -ClearKey $Name
}
Set-Alias wifi Get-Wifi

function Push-ExternalLocation {
	[array]$Dirs = Get-FileManagerDirectory

	$Clip = Get-Clipboard | select -First 1 # only get first line of clipboard
	if (Test-Path -Type Container $Clip) {
		$Dirs += Get-Item $Clip
	} elseif (Test-Path -Type Leaf $Clip) {
		$Dirs += Get-Item (Split-Path $Clip)
	}

	$Selected = Read-HostListChoice $Dirs -Prompt "Select directory to cd to:" `
			-NoInputMessage "No Explorer, Altap Salamander or clipboard locations found."
	Set-Location $Selected
}

function Expand-Msi([Parameter(Mandatory)]$MsiPath, [Parameter(Mandatory)]$OutputPath) {
	$MsiPath = Resolve-Path $MsiPath
	$OutputPath = Resolve-VirtualPath $OutputPath

	# /qn = no GUI
	# TARGETDIR = where to extract
	Start-Process -Wait msiexec -ArgumentList /a, $MsiPath, /qn, TARGETDIR=$OutputPath
	return Get-Item $OutputPath
}

function BulkRename() {
	[array]$Items = Get-Item @Args
	if ($null -eq $Items) {throw "No items to rename"}
	$TempFile = New-TemporaryFile
	$Items | select -ExpandProperty Name | Out-File $TempFile
	Open-TextFile $TempFile
	[array]$NewNames = cat $TempFile
	rm $TempFile
	if ($Items.Count -ne $NewNames.Count) {
		throw "You must not add, delete or reorder lines"
	}

	$Renames = @()
	for ($i = 0; $i -lt $Items.Count; $i++) {
		if ($Items[$i].Name -ne $NewNames[$i]) {
			$Renames += ,@($Items[$i], $NewNames[$i])
		}
	}

	Write-Host "The following items will be renamed:"
	$Renames | % {
		Write-Host "    $($_[0]) -> $($_[1])"
	}

	if (@($Renames).Count -eq 0) {
		Write-Host "No files renamed."
		return
	}

	$Options = @("&Yes", "&No")
	$Continue = switch ($Host.UI.PromptForChoice("Execute renames?", $null, $Options, 0)) {
		0 {$true} # Yes
		1 {$false} # No
	}

	if ($Continue) {
		$Renames | % {Rename-Item $_[0] $_[1]}
		Write-Host "Renamed $(@($Renames).Count) items."
	} else {
		Write-Host "Rename aborted."
	}
}

function Activate-Venv([string]$VenvName) {
	if ("" -eq $VenvName) {
		$Paths = ".\venv\Scripts\Activate.ps1", ".\.venv\Scripts\Activate.ps1"
	} else {
		$Paths = ".\$VenvName\Scripts\Activate.ps1"
	}

	$Dir = Get-Location
	while ($True) {
		$Path = $Paths | % {Join-Path $Dir $_} | ? {Test-Path $_} | select -First 1
		if ($Path) {break}

		$Dir = Split-Path $Dir
		if ($Dir -eq "") {
			throw "No venv found."
		}
	}
	& $Path
	echo "Activated venv in '$Dir'."
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


function Get-CmdExecutionTime($index=-1) {
	$cmd = (Get-History)[$index]
	$executionTime = $cmd.EndExecutionTime - $cmd.StartExecutionTime
	return Format-TimeSpan $executionTime
}

function tmp($Extension, $Prefix = "") {
	$Tmp = if ($IsWindows) {$env:TEMP} else {"/tmp"}
	return Join-Path $Tmp "$Prefix$(New-Guid)$Extension"
}

<# Convert the passed number to hex. #>
function hex([Parameter(Mandatory)]$n, $FormatSpecifier = "0x{0:X}") {
	if ($n -is [string]) {
		$n = [long]$n
		try {$n = [int]$n} catch {} # throws when the cast overflows
	} elseif ($n -is [decimal]) {
		throw "Decimal is not supported."
	} else {
		# https://github.com/PowerShell/PowerShell/issues/24018
		$n = [System.Management.Automation.LanguagePrimitives]::ConvertTo($n, $n.GetType())
	}
	return $FormatSpecifier -f $n
}

<# Convert the passed number to binary. #>
function bin([Parameter(Mandatory)]$n) {
	return hex $n "0b{0:b}"
}


# streams
function drop {
	<#
		.SYNOPSIS
		Drops items in pipeline until either `N` items are dropped, or an item satisfies the `Until` condition.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, ValueFromPipeline)]
		$InputObject,
		[Parameter(Mandatory, Position = 0, ParameterSetName = "N")]
		[int]
		$N,
		[Parameter(Mandatory, Position = 0, ParameterSetName = "Until")]
		[scriptblock]
		$Until,
		[Parameter(Mandatory, ParameterSetName = "eq")]
		[AllowNull()]
		$eq,
		[Parameter(Mandatory, ParameterSetName = "ne")]
		[AllowNull()]
		$ne
	)

	begin {
		if ($MyInvocation.BoundParameters.ContainsKey("eq")) {
			$Until = {$_ -eq $eq}
		} elseif ($MyInvocation.BoundParameters.ContainsKey("ne")) {
			$Until = {$_ -ne $ne}
		}

		$i = 0
		if ($Until) {
			$N = 1
		}
	}

	process {
		if ($i -ge $N) {
			return $_
		}

		if (-not $Until) {
			$i++
		} else {
			if ($Until.InvokeWithContext(@{}, [System.Collections.Generic.List[psvariable]][psvariable]::new('_', $_), @())) {
				$N = 0
				return $_
			}
		}
	}
}

function enumerate {
	begin {[ulong]$i = 0}
	process {[pscustomobject]@{Index = $i++; Item = $_}}
}

function join([string]$Delimiter = '') {
	begin {$Sb = [System.Text.StringBuilder]::new()}
	process {
		foreach ($str in $Input) {
			if ($Sb.Length -ne 0) {
				$null = $Sb.Append($Delimiter)
			}
			$null = $Sb.Append($str.ToString())
		}
	}
	end {
		return $Sb.ToString()
	}
}


function Get-RandomPassword($Length = 40, [switch]$AsPlaintext) {
	$Alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	$Password = (Get-SecureRandom -Maximum $Alphabet.Length -Count $Length | % {$Alphabet[$_]}) -join ""
	if ($AsPlaintext) {
		return $Password
	} else {
		return $Password | ConvertTo-SecureString -AsPlaintext
	}
}


function Get-ListeningService {
	Get-NetTCPConnection | ? State -eq Listen | % {
		$p = Get-Process -Id $_.OwningProcess
		[pscustomobject]@{
			LocalPort = $_.LocalPort
			PID = $p.Id
			CommandLine = $p.CommandLine
		}
	}
}

function Get-ModuleHelp($Name) {
	(Get-Module $Name).ExportedCommands.GetEnumerator() | % Value | Get-Help | select Name, Synopsis
}

function index($Pattern = "*", [switch]$Exact) {
	if (-not $Exact) {
		$Pattern = "*$Pattern*"
	}
    $Pattern = $Pattern -replace "\*", "%"

    $Connection = New-Object -ComObject ADODB.Connection
    $RecordSet = New-Object -ComObject ADODB.Recordset

    $Connection.Open("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';")
    $RecordSet.Open("SELECT System.ItemPathDisplay FROM SYSTEMINDEX WHERE System.FileName LIKE '" + $Pattern + "'", $Connection)

    $Output = while (-not $RecordSet.EOF) {
        $RecordSet.Fields.Item("System.ItemPathDisplay").Value
        $RecordSet.MoveNext()
    }

    $Output | sort
}


$NotebookPath = Get-PSDataPath "Notebook.txt"
function Get-Notebook {
	Get-Content -Raw $NotebookPath
}
function notes {
	Open-TextFile $NotebookPath
}

Export-ModuleMember -Function * -Cmdlet * -Alias *
