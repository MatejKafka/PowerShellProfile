using module .\Colors.psm1
using module Write-HostColor

Write-HostColor ("PowerShell v" + [string]$PSVersionTable.GitCommitId) `
		-ForegroundColor $UIColors.PowerShellVersion

$NotebookStr = Get-Notebook
if (-not [string]::IsNullOrWhitespace($NotebookStr)) {
	Write-HostColor ""
	Write-HostColor $NotebookStr -NoNewline -ForegroundColor $UIColors.Notebook
}
