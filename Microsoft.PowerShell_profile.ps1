### Entry point to my profile, automatically loaded by pwsh on startup.

# when pwsh is invoked with -File, -Command,... (scripted invocation), PSReadLine is not loaded in the InitialSessionState;
#  since the argv parser is not exposed from the engine, this is the simplest option I found to detect script invocations
if (-not [runspace]::DefaultRunspace.InitialSessionState.Modules) {
	# do not load anything when invoking a script (essentially emulate an implicit -NoProfile)
	return
}

Set-StrictMode -Version Latest

# do not load the profile when running from conhost.exe; however, I did not find a good way to detect conhost specifically,
#  especially since some terminal emulators use it internally, since conpty is still pretty young, so I instead I special-case
#  everything else I'm using; change this if you want the profile to load in other terminals
if (-not $IsWindows `
		-or [Environment]::GetEnvironmentVariable("PS_FULL_PROFILE") <# manual override #> `
		-or [Environment]::GetEnvironmentVariable("WT_SESSION") <# Windows Terminal #> `
		-or [Environment]::GetEnvironmentVariable("TERMINAL_EMULATOR") -eq "JetBrains-JediTerm" <# JetBrains IDE terminal #> `
		) {
	# the $PROFILE directory is symlinked to the repo in my configuration, resolve the real target
	Import-Module -DisableNameChecking "$((Get-Item $PSScriptRoot).ResolveLinkTarget($true))\profile_full"
} else {
	# function to load the full profile manually, if needed
	function full-profile {
		Import-Module -DisableNameChecking "$((Get-Item $PSScriptRoot).ResolveLinkTarget($true)))\profile_full"
	}
}
