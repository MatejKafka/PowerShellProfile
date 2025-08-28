param(
		[Parameter(Mandatory)]
		[HashTable]
	$Times
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Export-ModuleMember # don't export anything

$script:ReuseLastCommandStatus = $false
$script:LastStatusString = ""

Import-Module $PSScriptRoot\Colors
Import-Module $PSScriptRoot\PSReadLineOptions
Import-Module $PSScriptRoot\FSNav -ArgumentList ([ref]$script:ReuseLastCommandStatus)


# written by our overriden version of Out-Default
$script:_LastCmdOutputTypes = [System.Collections.Generic.List[type]]::new()
# without setting this, drawing prompt would fail
$global:LastExitCode = 0
# LastExitCode is overwritten on each prompt; LastExitCode of the previous entered command is stored here
$global:PreviousCommandExitCode = 0
# otherwise python venv would break our fancy Prompt
$Env:VIRTUAL_ENV_DISABLE_PROMPT = $true
# this shows a progress bar on taskbar and in terminal tab icon in Windows Terminal
$PSStyle.Progress.UseOSCIndicator = $true

$script:FirstPromptTime = $null


function Get-StartupTimeStatusString {
	if ($script:FirstPromptTime -eq $null) {
		$script:FirstPromptTime = Get-Date
		$script:Times.rest = $script:FirstPromptTime
	}

	$LoadStartTime = (Get-Process -Id $pid).StartTime
	$StartupTime = $script:FirstPromptTime - $LoadStartTime
	$StartupTimeStr += "startup: " + (Format-TimeSpan $StartupTime)

	$Sorted = ,@{Name = $null; Value = $LoadStartTime}
	$Sorted += $script:Times.GetEnumerator() | Sort-Object -Property Value
	$TimeStrings = @()
	for ($i = 1; $i -lt $Sorted.Count; $i += 1) {
		$_ = $Sorted[$i]
		$TimeStrings += $_.Name + ": " + (Format-TimeSpan ($_.Value - $Sorted[$i - 1].Value))
	}

	return $StartupTimeStr + " | " +  ($TimeStrings -join ", ")
}

function Get-CommandStatusString {
	param(
			[Parameter(Mandatory)]
			[Microsoft.PowerShell.Commands.HistoryInfo]
		$Cmd,
			[Parameter(Mandatory)]
			[boolean]
		$ErrorOccurred,
			[Parameter(Mandatory)]
			[int]
		$LastExitCode,
			[Parameter(Mandatory)]
			[AllowEmptyCollection()]
			[System.Collections.Generic.List[type]]
		$CmdOutputTypes
	)

	# status string indicating outcome of the command command
	$StatusStr = ""

	# render output type of the command, unless it resulted in an error
	if ($CmdOutputTypes.Count -gt 0 -and -not $ErrorOccurred) {
		$FirstType = Get-ConciseTypeName $CmdOutputTypes[0] -StripSystem
		if ($CmdOutputTypes.Count -gt 1) {
			$StatusStr += "[" + $CmdOutputTypes.Count + "]"
		}
		$StatusStr += $FirstType + " | "
	}

	# print exit code if error occurred
	if ($ErrorOccurred) {
		if ($LastExitCode -eq -1073741510 -or $Cmd.ExecutionStatus -eq "Stopped") {
			$StatusStr += "Ctrl-C | "
		} elseif ($LastExitCode -eq 0) {
			# error originates from powershell
			$StatusStr += "Error | "
		} else {
			# error from external command
			$StatusStr += if ($LastExitCode -lt 0) {
				"0x{0:X} ({0}) | " -f $LastExitCode
			} else {
				[string]$LastExitCode + " | "
			}
		}
	}

	$ExecutionTime = $Cmd.EndExecutionTime - $Cmd.StartExecutionTime
	$StatusStr += Format-TimeSpan $ExecutionTime
	return $StatusStr
}


# this function is taken from `posh-git` module and simplified a bit to speed up startup
# loading the whole posh-git module caused quite a long delay, and we only need this one function
function Get-GitDirectory {
	$pathInfo = Get-Location
	if (!$pathInfo -or ($pathInfo.Provider.Name -ne 'FileSystem')) {
		$null
	} elseif ($Env:GIT_DIR) {
		$Env:GIT_DIR -replace '\\|/', [System.IO.Path]::DirectorySeparatorChar
	} else {
		$currentDir = Get-Item -LiteralPath $pathInfo -Force
		for (; $currentDir; $currentDir = $currentDir.Parent) {
			$gitDirPath = Join-Path $currentDir .git
			if (Test-Path -LiteralPath $gitDirPath -Type Container) {
				return $gitDirPath
			}
		}
	}
}

function Write-ShellStatus($InfoColor) {
	function Write-InfoStatus($Status) {
		Write-HostColor "($Status)" -NoNewLine -ForegroundColor $InfoColor
	}

	# show if we're in debug mode; in 7.3.0-preview.2, this is currently broken due to scoping rules
	if (Get-Variable PSDebugContext -ErrorAction Ignore) {
		Write-InfoStatus "DBG"
	}

	# show if we're inside a MSVC Developer shell
	if ($null -ne $env:VSINSTALLDIR) {
		Write-InfoStatus "msvc"
	}

	# show if we're running with active python venv
	if ($null -ne $env:VIRTUAL_ENV) {
		$VenvName = Split-Path -Leaf $env:VIRTUAL_ENV
		Write-InfoStatus $VenvName
	}

	if (Test-Path -Type Container .) {
		# show if we're inside a git repository
		$GitDir = Get-GitDirectory
		if ($GitDir) {
			$GitStr = try {
				$RefStr = cat (Join-Path $GitDir "./HEAD")
				# "ref: refs/heads/".Length
				$BranchName = if ($RefStr -like "ref: refs/heads/*") {$RefStr.Substring(16)} else {$RefStr}
				"git:" + $BranchName
			} catch {"git"}
			Write-InfoStatus $GitStr
		}
	} else {
		Write-HostColor "(X)" -NoNewLine -ForegroundColor "Red"
	}
}


$script:LastCmdId = $null

function BuildStatusStr($ErrorOccurred, $ExitCode, $LastCmdOutputTypes) {
	$LastCmd = Get-History -Count 1
	
	if ($script:ReuseLastCommandStatus) {
		$script:ReuseLastCommandStatus = $false
		$StatusStr = $script:LastStatusString
		# VT mark: end of command
		$VTMarkStr = "`e]133;D`a"

	} elseif ($null -eq $LastCmd) {
		# render startup timings
		$StatusStr = Get-StartupTimeStatusString
		$VTMarkStr = ""

	} elseif ($LastCmd.Id -ne $script:LastCmdID) {
		$script:LastCmdId = $LastCmd.Id
		# render previous command status
		$StatusStr = Get-CommandStatusString $LastCmd $ErrorOccurred $ExitCode $LastCmdOutputTypes

		# VT mark: end of command, with exit code
		$VTMarkExitCode = $ExitCode -ne 0 ? $ExitCode : $ErrorOccurred ? 1 : 0
		$VTMarkStr = "`e]133;D;${VTMarkExitCode}`a"
	
	} else {
		# either we're re-rendering prompt in the same place, or user pressed enter without entering a command
		$StatusStr = ""
		# VT mark: end of command
		$VTMarkStr = "`e]133;D`a"
	}

	$script:LastStatusString = $StatusStr
	return $StatusStr, $VTMarkStr
}

function PrintSeparatorAndStatus($StatusStr, $Color, $StatusColor) {
	if ($StatusStr) {
		$MaxStatusLength = $Host.UI.RawUI.WindowSize.Width - 4
		if ($StatusStr.Length -gt $MaxStatusLength) {
			$StatusStr = $StatusStr.Substring(0, $MaxStatusLength - 1) + "…"
		}
		Write-HostColor ("╦" + "═" * ($MaxStatusLength - $StatusStr.Length) + "") -ForegroundColor $Color -NoNewLine
		Write-HostColor $StatusStr -BackgroundColor $Color -ForegroundColor $StatusColor -NoNewLine
		Write-HostColor "═" -ForegroundColor $Color
	} else {
		Write-HostColor ("╦" + "═" * ($Host.UI.RawUI.WindowSize.Width - 1)) -ForegroundColor $Color
	}
	Write-HostColor "╚╣" -NoNewLine -ForegroundColor $Color
}

function global:Prompt {
	# capture these two before we do anything else
	$ErrorOccurred = -not $?
	$ExitCode = $global:LastExitCode

	$Colors = $ErrorOccurred ? $UIColors.Prompt.Error : $UIColors.Prompt.Ok
	$Color = $Colors.Base
	$CwdColor = $Colors.Highlight
	$StatusColor = $Colors.Status

	# render status string
	$StatusStr, $VTMarkStr = BuildStatusStr $ErrorOccurred $ExitCode $script:_LastCmdOutputTypes
	$CwdString = $ExecutionContext.SessionState.Path.CurrentLocation.Path
	if ($CwdString -like "Microsoft.PowerShell.Core\FileSystem::*") {
		# this happens e.g. after `gi dir | cd`
		$CwdString = $ExecutionContext.SessionState.Path.CurrentLocation.ProviderPath
	}

	# VT mark: prompt started
	$VTMarkStr += "`e]133;A$([char]07)"
	# VT mark: CWD
	$VTMarkStr += "`e]9;9;`"${CwdString}`"$([char]07)"

	# write the VT mark string first (command ended, prompt started)
	Write-Host -NoNewLine $VTMarkStr

	# write the horizontal separator and status string
	PrintSeparatorAndStatus $StatusStr $Color $StatusColor
	Write-ShellStatus $Color
	Write-HostColor -NoNewLine " "

	# write the prompt itself
	Write-HostColor $CwdString -NoNewLine -ForegroundColor $CwdColor

	# VT mark: prompt ended, command started
	Write-Host -NoNewLine "`e]133;B$([char]07)"


	# set indent of continuation prompt to match the main prompt (so that multiline code in the prompt has no jumps between lines)
	Set-PSReadLineOption -ContinuationPrompt (" " * [math]::max(0, $Host.UI.RawUI.CursorPosition.X - 1) + ">> ")

	# set tab/window title to the shortened version of CWD (my Windows Terminal tab title fits roughly 25 chars (it's non-monospace))
	$MAX_TAB_TITLE_LENGTH = 25
	$Host.UI.RawUI.WindowTitle = if ($CwdString.Length -le $MAX_TAB_TITLE_LENGTH) {
		$CwdString
	} else {
		$Trimmed = $CwdString.Substring($CwdString.Length - $MAX_TAB_TITLE_LENGTH)
		$SlashI = $Trimmed.IndexOfAny("\/")
		"…" + $(if ($SlashI -ge 0) {$Trimmed.Substring($SlashI)} else {$Trimmed})
	}

	
	# reset exit code
	$global:PreviousCommandExitCode = $global:LastExitCode
	$global:LastExitCode = 0
	# reset last output types and store them in the user-accessible $global:Types variable
	$global:Types = $script:_LastCmdOutputTypes.ToArray()
	$script:_LastCmdOutputTypes.Clear()

	return ">" * ($NestedPromptLevel + 1) + " "
}


<#
	This override allows us to capture the types of all output objects and display them in the prompt.

	ISSUE: PowerShell internally sets $_ based on success of last command;
		 this override contains some commands, so we'll lose the success status of previous
		 command entered by user, as it's overwritten by status of commands in this function
		this is tolerable, as prompt sees the correct value of $? and changes color based on it,
		so user doesn't really need to access $? from prompt (and it works as expected in scripts)
#>
function global:Out-Default {
	param(
			[switch]
		$Transcript,
			[Parameter(ValueFromPipeline)]
			[PSObject]
		$InputObject
	)

	begin {
		$ScriptCmd = { & 'Microsoft.PowerShell.Core\Out-Default' @PSBoundParameters }
		$SteppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
		$SteppablePipeline.Begin($PSCmdlet)
	}

	process {
		$SteppablePipeline.Process($_)
		if ($null -ne $_) {
			$script:_LastCmdOutputTypes.Add($_.GetType())
		}
	}

	end {
		$SteppablePipeline.End()
	}
}
