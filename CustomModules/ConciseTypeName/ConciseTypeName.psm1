Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ConciseTypeMap = @{
	"System.Object" = "Object"
	"System.String" = "String"
	"System.Int32" = "Int"
	"System.UInt32" = "UInt"
	"System.Int64" = "Long"
	"System.UInt64" = "ULong"

	"System.DateTime" = "DateTime"

	"System.Management.Automation.PSObject" = "PSObject"
	"System.Management.Automation.PSCredential" = "PSCredential"
	"System.Management.Automation.ScriptBlock" = "ScriptBlock"

	"System.Collections.Hashtable" = "Hashtable"
	"System.Collections.Generic.KeyValuePair" = "KeyValuePair"
	"System.Collections.Generic.IEnumerable" = "IEnumerable"
	"System.Collections.Generic.Dictionary" = "Dictionary"
	"System.Collections.Generic.List" = "List"
}

function Get-ConciseTypeName {
	[CmdletBinding(DefaultParameterSetName="TypeName")]
	param(
		[Parameter(Mandatory, Position=0, ParameterSetName="TypeName")]
			[string]
		$TypeName,
			[Parameter(Mandatory, Position=0, ParameterSetName="Type")]
			[type]
		$Type,
			[switch]
		$StripSystem
	)

	if ($TypeName) {
		try {
			$Type = [type]$TypeName
		} catch {
			return $TypeName # unknown type, just return it as-is
		}
	}

	if ($Type.IsArray) {
		return (Get-ConciseTypeName $Type.GetElementType()) + "[]"
	}

	$Name = $Type.Name
	# strip generic argument marker
	if ($Name -match "(.*)``\d+") {
		$Name = $Matches[1]
	}

	if ($Type.ReflectedType) {
		# nested type
		$Name = (Get-ConciseTypeName $Type.ReflectedType) + "+" + $Name
	} else {
		if ($Type.Namespace) {
			$Name = $Type.Namespace + "." + $Name
		}

		$Name = $ConciseTypeMap[$Name] ?? $Name

		if ($StripSystem -and $Name.StartsWith("System.")) {
			$Name = $Name.Substring(7)
		}
	}

	if ($Type.GenericTypeArguments.Count -gt 0) {
		$Name += "[" + (($Type.GenericTypeArguments | % {Get-ConciseTypeName $_}) -join ", ") + "]"
	}

	return $Name
}
