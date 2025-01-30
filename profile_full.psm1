#Requires -Version 7.2

# read current time for startup measurement
$_Times = @{
	internal = Get-Date
}

Set-StrictMode -Version Latest
# stop even on non-critical errors
$global:ErrorActionPreference = "Stop"
#$global:PSDefaultParameterValues["*:ErrorAction"] = $ErrorActionPreference
# throw error when native command returns non-zero exit code
$global:PSNativeCommandUseErrorActionPreference = $true
# show Information log stream
$global:InformationPreference = "Continue"

# add custom module directories
$env:PSModulePath = @(
	$env:PSModulePath
	"$PSScriptRoot\CustomModules"
	"$PSScriptRoot\UnmaintainedModules"
	"$PSScriptRoot\ZLocation2"
) -join [IO.Path]::PathSeparator


# set global path to data directory, this is used by multiple other custom modules in this repository
Set-PSDataRoot $PSScriptRoot\..\data


if ($IsWindows) {
	# create a new aliased drive for HKCR
	# ignore errors in case we're reloading the script and the drive already exists
	$null = New-PSDrive -Scope Global -PSProvider Registry -Root HKEY_CLASSES_ROOT -Name HKCR -ErrorAction Ignore
}

# set path where command history is saved
Set-PSReadLineOption -HistorySavePath (Get-PSDataPath "ConsoleHost_history.txt")
# set database path for ZLocation2
$env:ZLOCATION_DATABASE_PATH = Get-PSDataPath "z-location2.db" -NoCreate

# set env:LANG, which makes `git diff` and other originally Linux commands print stuff with correct encoding
$env:LANG = "C.UTF-8"

$_Times.setup = Get-Date

# a collection of random useful functions; -Global is used so that the module is visible externally
#  (among other benefits, this means that it can be reloaded separately)
Import-Module -Global $PSScriptRoot\functions.psm1 -DisableNameChecking
# stub completers which lazily load the actual completer on first invocation to minimize startup impact
Import-Module -Global $PSScriptRoot\functions_completers.psm1
# custom private functions, not commited to git
Import-Module -Global $PSScriptRoot\functions_custom.psm1 -ErrorAction Ignore -DisableNameChecking

# delay the import of remaining modules after the profile is loaded to improve startup time
Register-EngineEvent PowerShell.OnIdle -MaxTriggerCount 1 -Action {
	# delay the load of modules that take a long time to load, and are not immediately needed
	# this is better than just directly importing the modules here, because once the OnIdle
	#  callback is started, it cannot be iterrupted and the shell could be left unresponsive
	#  for a long time until all modules are loaded
	Import-Module DelayLoad 4>$null
	
	# setup ZLocation (my fork with some change)
	# if user types `z` immediately after prompt loads, this will not be loaded yet,
	#  so he'll have to wait for a bit, but the command will still work
	Import-ModuleDelayed ZLocation2
	
	# random argument completers, too many to list in functions_completers.psm1
	Import-ModuleDelayed ArgumentCompleters
}

$_Times.imports = Get-Date


# do not setup custom prompt and banner if set
if (-not (Test-Path Env:PS_SIMPLE_PROMPT)) {
	Import-Module $PSScriptRoot\Prompt\Colors
	# if set, do not show custom banner (TODO, version, calendar,...)
	if (-not (Test-Path Env:PS_NO_BANNER)) {
		& $PSScriptRoot\Prompt\banner.ps1
		$_Times.banner = Get-Date
	}
	# setup prompt
	Import-Module $PSScriptRoot\Prompt\Prompt -ArgumentList @($_Times)
	$_Times.prompt = Get-Date
} else {
	# function to load the prompt manually, if needed
	function full-prompt {
		Import-Module $PSScriptRoot\Prompt\Prompt -ArgumentList @(@{})
	}
}

