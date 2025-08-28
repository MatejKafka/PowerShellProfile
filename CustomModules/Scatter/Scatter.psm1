Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Out-ScatterPlot {
	[CmdletBinding()]
	[Alias("scatter")]
	param(
		[Parameter(ValueFromPipeline)]$InputObject,
		[string]$Title,
		[string]$LabelX,
		[string]$LabelY,
		[switch]$Line,
		[switch]$NoPoint,
		[switch]$YFromZero,
		[switch]$NoLegend
	)

	begin {
		$Args = @()
		if ($Title) {$Args += @("-t", $Title)}
		if ($LabelX) {$Args += @("-x", $LabelX)}
		if ($LabelY) {$Args += @("-y", $LabelY)}

		if ($Line) {$Args += @("-l")}
		if ($NoPoint) {$Args += @("-p")}
		if ($YFromZero) {$Args += @("-0")}
		if ($NoLegend) {$Args += @("-L")}

	    # forward input to the Python script
	    $Pipeline = {python $PSScriptRoot/scatter.py @Args}.GetSteppablePipeline($myInvocation.CommandOrigin)
	    $Pipeline.Begin($PSCmdlet)
	}

	process {
		$Index = $_ | select Index | % Index
		$Value = $_ | select Item | % Item
		if ($null -ne $Index -and $null -ne $Value) {
			$Pipeline.Process("$Index,$Value")
		} else {
			$Pipeline.Process([string]$_)
		}
	}

	end {
		$Pipeline.End()
	}
}

