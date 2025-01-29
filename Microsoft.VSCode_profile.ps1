$env:PS_SIMPLE_PROMPT = "1"
Import-Module -DisableNameChecking "$((Get-Item $PSScriptRoot).ResolvedTarget)\profile_full"