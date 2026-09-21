<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER File
		Supply the input file containing the JSON object of the Resource Scrape to be processed.
	
	.PARAMETER showHtml
		If you want to view the HTML output automatically include the showHTML switch parameter
	
	.PARAMETER rulesfile
		Enter the path to the Rules file. The Rules file defines the characteristics of an ACP
	
	.PARAMETER OutPath
		Path to output files
	
	.PARAMETER Details
		Show the messages to the console
	
	.PARAMETER Stamp
		Attach the datetime stamp to the output folder and some files
	
	.PARAMETER PrettyACP
		A description of the PrettyACP parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2023 v5.8.232
		Created on:   	3/12/2024 1:55 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	process-ResourceScrape
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true,
			   HelpMessage = 'Supply the input file containing the JSON object of the Resource Scrape to be processed.')]
	[Alias('f')]
	[string]$file,
	[Parameter(HelpMessage = 'If you want to view the HTML output automatically include the show-HTML switch parameter')]
	[Alias('h')]
	[switch]$showHtml,
	[Parameter(HelpMessage = 'Enter the path to the Rules file. The Rules file defines the characteristics of an ACP')]
	[Alias('r')]
	[string]$rulesFile = 'rules.xml',
	[Parameter(HelpMessage = 'Path to output files')]
	[Alias('o')]
	[string]$OutPath,
	[Parameter(Mandatory = $false,
			   HelpMessage = 'Show the messages to the console')]
	[Alias('d')]
	[switch]$Details = $false,
	[Parameter(HelpMessage = 'Attach the datetime stamp to the output folder and some files')]
	[Alias('s')]
	[switch]$Stamp
)

$outRcd = ""
$typeElems = New-Object -TypeName System.Collections.ArrayList
$propElems = New-Object -TypeName System.Collections.ArrayList
$arrElems = New-Object -TypeName System.Collections.ArrayList
$chkElems = New-Object -TypeName System.Collections.ArrayList
$outElems = New-Object -TypeName System.Collections.ArrayList
$acpList = New-Object -TypeName System.Collections.ArrayList
$acpFile = ""
$script:labId = $null
$script:notFound = 0
$script:resFound = 0

function Write-log {
	[CmdletBinding()]
	param
	(
		$id,
		$msg,
		[bool]$toConsole = $false
	)
	
	# Get the Date/Time
	$dte = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
	
	# Appent the message to the log file
	Write-Output "$($dte) (id:$($id)) $($msg)" | Out-file $log -append
	
	if ($toConsole) {
		Write-Host "$($dte) (id:$($id)) $($msg)"
	}
}

function Show-Error {
	[CmdletBinding()]
	param
	(
		$id,
		[Parameter(Mandatory = $true)]
		$err
	)
	
	# Get the current date/time
	$errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	
	# Retrieve the error message
	$e = $err.Exception
	$msg = $e.Message
	
	# parse the error message
	while ($e.InnerException) {
		$e = $e.InnerException
		$msg += "`n" + $e.Message
	}
	
	# write the update to the log file
	Write-log -toConsole $Details -id $id -msg "Error $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
}

function Format-JsonString {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$json,
		[int]$Depth = 50
	)
	
	if ([string]::IsNullOrWhiteSpace($json)) {
		return $json
	}
	
	try {
		# Primary: parse + reformat
		return ($json | ConvertFrom-Json | ConvertTo-Json -Depth $Depth)
	} catch {
		try {
			# Fix trailing commas and retry
			$fixed = $json -replace ',(\s*[\}\]])', '$1'
			return ($fixed | ConvertFrom-Json | ConvertTo-Json -Depth $Depth)
		} catch {
			# Fallback: return raw JSON
			return $json
		}
	}
}



function Normalize-JsonIndentation {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Json,
		[int]$Indent = 2
	)
	if ([string]::IsNullOrWhiteSpace($Json)) {
		return $Json
	}
	$lines = $Json -split "`r?`n"
	$indents = @()
	foreach ($l in $lines) {
		if ($l -match '^( +)\S') {
			$indents += $matches[1].Length
		}
	}
	$indents = $indents | Where-Object {
		$_ -gt 0
	}
	if (-not $indents -or $indents.Count -eq 0) {
		return $Json
	}
	$base = ($indents | Measure-Object -Minimum).Minimum
	if ($base -le 0) {
		return $Json
	}
	$factor = [double]$Indent / [double]$base
	$newLines = foreach ($l in $lines) {
		if ($l -match '^( +)(.*)$') {
			$len = $matches[1].Length
			$rest = $matches[2]
			$newLen = [int][math]::Round($len * $factor)
			(' ' * $newLen) + $rest
		} else {
			$l
		}
	}
	return ($newLines -join "`n")
}


function Test-IsNotePlaceholderCondition {
	param ($Obj)
	
	try {
		if ($null -eq $Obj) {
			return $false
		}
		
		# Works for both PSCustomObject and hashtable-like objects
		$field = $null
		$equals = $null
		
		if ($Obj -is [System.Collections.IDictionary]) {
			if ($Obj.Contains('field')) {
				$field = [string]$Obj['field']
			}
			if ($Obj.Contains('equals')) {
				$equals = [string]$Obj['equals']
			}
		} else {
			if ($Obj.PSObject.Properties.Name -contains 'field') {
				$field = [string]$Obj.field
			}
			if ($Obj.PSObject.Properties.Name -contains 'equals') {
				$equals = [string]$Obj.equals
			}
		}
		
		# Remove any NOTE placeholder condition objects.
		# (If you only want NOTE+equals:[text], uncomment the equals check.)
		if ($field -ne 'NOTE') {
			return $false
		}
		
		# If you want to ONLY remove the specific NOTE placeholder with equals "[text]", use:
		# if ($equals -ne '[text]') { return $false }
		
		return $true
	} catch {
		return $false
	}
}

#        [Parameter(Mandatory = $true)]
function Remove-NotePlaceholderConditions {
	[CmdletBinding()]
	param (
		$Node,
		# Depth guard to prevent runaway recursion
		[int]$Depth = 0,
		[int]$MaxDepth = 200
	)
	
	if ($null -eq $Node) {
		return $null
	}
	if ($Depth -ge $MaxDepth) {
		return $Node
	}
	
	# IMPORTANT: handle IDictionary BEFORE IEnumerable
	if ($Node -is [System.Collections.IDictionary]) {
		$h = [ordered]@{
		}
		foreach ($k in $Node.Keys) {
			$clean = Remove-NotePlaceholderConditions -Node $Node[$k] -Depth ($Depth + 1) -MaxDepth $MaxDepth
			# Preserve keys even when the cleaned value is $null (only NOTE condition objects are removed)
			$h[$k] = $clean
		}
		return $h
	}
	
	# Arrays / lists (but not strings)
	if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
		$out = @()
		foreach ($item in $Node) {
			if (Test-IsNotePlaceholderCondition $item) {
				continue
			}
			$clean = Remove-NotePlaceholderConditions -Node $item -Depth ($Depth + 1) -MaxDepth $MaxDepth
			if ($null -ne $clean) {
				$out += ,$clean
			}
		}
		return, $out
	}
	
	# PSCustomObject
	if ($Node -is [pscustomobject]) {
		if (Test-IsNotePlaceholderCondition $Node) {
			return $null
		}
		
		$h = [ordered]@{
		}
		foreach ($p in $Node.PSObject.Properties) {
			$clean = Remove-NotePlaceholderConditions -Node $p.Value -Depth ($Depth + 1) -MaxDepth $MaxDepth
			# Preserve properties even when the cleaned value is $null (only NOTE condition objects are removed)
			$h[$p.Name] = $clean
		}
		return $h
	}
	
	# Primitive / scalar
	return $Node
}

function ConvertTo-IndentedHtmlList {
	param (
		[Parameter(Mandatory = $true)]
		[Object]$Object,
		[int]$IndentLevel = 0
	)
	
	# Set the HTML indentation level
	$indentation = ' ' * ($IndentLevel * 4)
	$html = "$indentation<ul>"
	
	# Retrieve and convert the JSON properties
	$objProperties = $object | ConvertTo-Json | ConvertFrom-Json
	
	# Cycle over all the properties
	foreach ($property in $Object.PSObject.Properties) {
		# retrieve the current property name and value
		$propertyName = "$($property.Name)"
		$propertyValue = $property.Value
		
		# Build the HTML element with proper indentation
		$html += "$indentation    <li>$($propertyName): "
		
		if ($propertyValue -is [System.Management.Automation.PSCustomObject]) {
			$html += ConvertTo-IndentedHtmlList -Object $propertyValue -IndentLevel ($IndentLevel + 1)
		} elseif (($propertyValue -is [System.Collections.IEnumerable] -and $propertyValue -isnot [string]) -or ($propertyValue -is [Object])) {
			$html += "<ul>"
			foreach ($item in $propertyValue) {
				$html += "$indentation        <li>$item</li>"
			}
			$html += "$indentation    </ul>"
		} else {
			$html += "$propertyValue"
		}
		$html += "</li>"
	}
	
	$html += "$indentation</ul>"
	
	# Return the built HTML
	return $html
}

function Add-headers {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		$listHeaders
	)
	
	# Build the HTML headers based on the input list
	$retHead = "  <thead><tr>`n"
	$listHeaders | ForEach-Object {
		#		if ([string]::IsNullOrEmpty($_)) {
		if ($_ -eq "first") {
			$retHead += "    <th width=30px>&nbsp;</th>`n"
		} elseif ($_ -eq "last") {
			$retHead += "    <th width=5px>&nbsp;</th>`n"
		} else {
			$retHead += "    <th>$_</th>`n"
		}
	}
	$retHead += "  </tr></thead>`n"
	
	return $retHead
}

# NOTE: The "Set-acp" function has been rewritten and enhanced by MS Copilot AI
# NOTE: Set-acp now returns a native object { allOf = [...] } instead of a JSON string fragment
function Set-acp {
	[CmdletBinding()]
	param (
		$name,
		$row,
		$props
	)
	
	function Get-ResourceGroupFromResourceId {
		param ([string]$ResourceId)
		if ([string]::IsNullOrEmpty($ResourceId)) {
			return $null
		}
		$m = [regex]::Match($ResourceId, "/resourceGroups/([^/]+)/", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
		if ($m.Success) {
			return $m.Groups[1].Value
		}
		return $null
	}
	
	function Get-ValueByPath {
		param (
			[Parameter(Mandatory = $true)]
			$Object,
			[Parameter(Mandatory = $true)]
			[string]$Path
		)
		if ($null -eq $Object -or [string]::IsNullOrEmpty($Path)) {
			return $null
		}
		$segments = $Path -split "\."
		$current = $Object
		foreach ($seg in $segments) {
			if ($null -eq $current) {
				return $null
			}
			if ($seg -match '^(?<p>[^\[]+)\[\*\]$') {
				$prop = $Matches['p']
				try {
					$arr = $current.$prop
				} catch {
					$arr = $null
				}
				if ($arr -is [System.Collections.IEnumerable] -and $arr -isnot [string]) {
					$current = @($arr)
				} else {
					return $null
				}
				continue
			}
			if ($current -is [System.Collections.IEnumerable] -and $current -isnot [string]) {
				$projected = @()
				foreach ($item in $current) {
					if ($null -ne $item -and $item.PSObject.Properties.Name -contains $seg) {
						$projected += $item.$seg
					}
				}
				$current = $projected
				continue
			}
			if ($current.PSObject.Properties.Name -contains $seg) {
				$current = $current.$seg
			} else {
				return $null
			}
		}
		return $current
	}
	
	
	function Convert-ToConcatIfContainsLabInstanceInt {
		param (
			[Parameter(Mandatory = $true)]
			[string]$Text
		)
		
		if ([string]::IsNullOrEmpty($Text)) {
			return $null
		}
		
		# Match any standalone 8-digit integer
		#		$pattern = '\b\d{8}\b'
		$pattern = '\d{8}'
		
		if ($Text -notmatch $pattern) {
			return $null
		}
		
		# Split but KEEP the delimiters (the 8-digit values)
		$parts = [regex]::Split($Text, "($pattern)")
		
		$args = New-Object System.Collections.Generic.List[string]
		
		foreach ($part in $parts) {
			if ([string]::IsNullOrEmpty($part)) {
				continue
			}
			
			if ($part -match "^$pattern$") {
				# This is an 8-digit Lab Instance
				$args.Add('resourcegroup().tags.LabInstance')
			} else {
				# Literal text
				$litEsc = $part -replace "'", "''"
				$args.Add("'$litEsc'")
			}
		}
		
		if ($args.Count -eq 0) {
			return $null
		}
		
		return "[concat($($args -join ','))]"
	}
	
	function Convert-ToConcatIfContainsLabInstance {
		param ([Parameter(Mandatory = $true)]
			[string]$Text,
			[Parameter(Mandatory = $true)]
			[string]$LabInstance)
		if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($LabInstance)) {
			return $null
		}
		if ($Text -notlike "*$LabInstance*") {
			return $null
		}
		$parts = $Text -split [regex]::Escape($LabInstance)
		$args = New-Object System.Collections.Generic.List[string]
		for ($i = 0; $i -lt $parts.Count; $i++) {
			$lit = $parts[$i]
			if (-not [string]::IsNullOrEmpty($lit)) {
				$litEsc = $lit -replace "'", "''"
				$args.Add("'$litEsc'")
			}
			if ($i -lt ($parts.Count - 1)) {
				$args.Add('resourcegroup().tags.LabInstance')
			}
		}
		if ($args.Count -eq 0) {
			$args.Add('resourcegroup().tags.LabInstance')
		}
		return "[concat($($args -join ','))]"
	}
	
	function Build-ResourceGroupMatchValue {
		param ([Parameter(Mandatory = $true)]
			[string]$ResourceGroupName,
			[string]$LabInstance)
		if ([string]::IsNullOrEmpty($ResourceGroupName)) {
			return $null
		}
		if (-not [string]::IsNullOrEmpty($LabInstance) -and $ResourceGroupName -like "*$LabInstance*") {
			$parts = $ResourceGroupName -split [regex]::Escape($LabInstance)
			$prefix = $parts[0]
			$suffix = ''
			if ($parts.Count -gt 1) {
				$suffix = $parts[1]
			}
			$prefEsc = ($prefix -replace "'", "''")
			$sufEsc = ($suffix -replace "'", "''")
			return "[concat('/resourceGroups/$prefEsc',resourcegroup().tags.LabInstance,'$sufEsc/')]"
		}
		return "/resourceGroups/$ResourceGroupName/"
	}
	
	Write-log -toConsole $Details -id 67 -msg "Looking up rules for property: $($name).`n"
	
	if ([string]::IsNullOrEmpty($script:labId)) {
		$script:labId = $null
		try {
			$script:labId = [string]$row.ResourceGroupTags.LabInstance
		} catch {
			$script:labId = $null
		}
	}
	
	$rgFromId = $null
	try {
		$rgFromId = Get-ResourceGroupFromResourceId -ResourceId ([string]$row.ResourceId)
	} catch {
		$rgFromId = $null
	}
	if ([string]::IsNullOrEmpty($rgFromId)) {
		try {
			$rgFromId = [string]$row.ResourceGroupName
		} catch {
			$rgFromId = $null
		}
	}
	
	if (-not (Test-Path -Path $rulesFile -PathType Leaf)) {
		Write-log -toConsole $Details -id 9 -msg "ERROR: Could not find the rules file. File: $($rulesFile)`n"
		return $null
	}
	
	[xml]$rules = Get-Content -Path $rulesFile
	$rule = $rules.resources.resource | Where-Object {
		$_.type -eq $row.ResourceType -and $_.enabled -eq 'true'
	}
	if ($null -eq $rule) {
		return $null
	}
	
	Write-log -toConsole $Details -id 68 -msg "Rule has been found for $($rule.type).`n"
	Write-log -toConsole $Details -id 69 -msg "Rule is enabled.`n"
	
	if ($null -eq $rule.properties) {
		if (-not $typeElems.Contains($rule.type)) {
			[void]$typeElems.Add($rule.type)
		}
		return $null
	}
	
	Write-log -toConsole $Details -id 70 -msg "This rule has properties.`n"
	
	$allOf = @()
	$allOf += [ordered]@{
		field = 'type'; equals = [string]$rule.type
	}
	
	for ($x = 0; $x -lt $rule.properties.field.count; $x++) {
		if ($rule.properties.field[$x].name -eq 'provisioningState' -and $rule.properties.field[$x].value -eq 'Succeeded') {
			continue
		}
		
		$outFieldName = [string]$rule.properties.field[$x].name
		$outFunc = [string]$rule.properties.field[$x].func
		$outVal = $rule.properties.field[$x].value
		
		if ($rule.properties.field[$x].valtype -eq 'field') {
			$path = [string]$rule.properties.field[$x].value
			$resolved = $null
			switch -Regex ($path) {
				'^name$'         {
					$resolved = $row.ResourceName; break
				}
				'^resourceName$' {
					$resolved = $row.ResourceName; break
				}
				'^ResourceId$'   {
					$resolved = $row.ResourceId; break
				}
				default {
					if ($path -like 'sku.*') {
						$resolved = Get-ValueByPath -Object $row.ResourceSKU -Path ($path.Substring(4))
					} else {
						$resolved = Get-ValueByPath -Object $props -Path $path
						if ($null -eq $resolved) {
							try {
								$resolved = Get-ValueByPath -Object $row.APIProperties -Path $path
							} catch {
							}
						}
						if ($null -eq $resolved) {
							try {
								if ($row.PSObject.Properties.Name -contains $path) {
									$resolved = $row.$path
								}
							} catch {
							}
						}
					}
				}
			}
			if ($resolved -is [System.Collections.IEnumerable] -and $resolved -isnot [string]) {
				$resolved = (@($resolved) | Where-Object {
						$_ -ne $null
					} | ForEach-Object {
						"$_"
					}) -join ','
			}
			$outVal = $resolved
		}
		
		if ($outFieldName -eq 'id') {
			if (-not [string]::IsNullOrEmpty($rgFromId)) {
				$outVal = Build-ResourceGroupMatchValue -ResourceGroupName $rgFromId -LabInstance $script:labId
				$outFunc = 'contains'
			}
		}
		
		if ($outVal -is [string] -and -not [string]::IsNullOrEmpty($outVal)) {
			$concat = $null
			try {
				$concat = Convert-ToConcatIfContainsLabInstance -Text $outVal -LabInstance $script:labId
			} catch {
				$concat = $null
			}
			if ($concat) {
				$outVal = $concat
				$outFunc = 'contains'
			} else {
				try {
					$concat = Convert-ToConcatIfContainsLabInstanceInt -Text $outVal
				} catch {
					$outVal = $null
				}
				if ($concat) {
					$outVal = $concat
				}
			}
		}
		
		$cond = [ordered]@{
			field = $outFieldName
		}
		$cond[$outFunc] = $outVal
		$allOf += $cond
	}
	
	return [ordered]@{
		allOf = $allOf
	}
}

function Build-Body {
	[CmdletBinding()]
	param
	(
		$rowData
	)
	
	$retVal = ""
	$cnt = 1
	$rowData | ForEach-Object {
		$object = $_
		if (-not ([string]::IsNullOrEmpty($object.ResourceName))) {
			
			# determine the odd/even nature of the row and use the appropriate CSS class
			$cssStyle = if ($cnt % 2 -eq 0) {
				"background-color: #ffffff;"
			} else {
				"background-color: #B3E5FC;"
			}
			# Precompute a searchable string (for client-side filtering)
			$search = ("$($object.ResourceName) $($object.ResourceLocation) $($object.ResourceGroupName) $($object.ResourceType)" -replace "'", "&#39;")
			# Add the main row
			$retVal += "  <tr class='main-row' style='$cssStyle'>`n"
			$retVal += "    <td><button type='button' id='prop' style='width:80%;align:left;'>+</button></td>`n"
#			$retVal += "    <td><button type='button' id='prop'>⮟</button></td>`n"
#			$retVal += "    <td><button type='button' id='prop'>&#11167;</button></td>`n"
#			$retVal += '    <td><button type="button" id="prop">&#11167;</button></td>`n'
			$retVal += "    <td>$($object.ResourceName)</td>`n"
			$retVal += "    <td>$($object.ResourceLocation)</td>`n"
			$retVal += "    <td>$($object.ResourceGroupName)</td>`n"
			$retVal += "    <td>$($object.ResourceType)</td>`n"
			$retVal += "    <td align=right style='background-color: #ffffff;'>&nbsp</td>`n"
			$retVal += "  </tr>`n"
			
			# Add the extra properties dropdown row
			$retVal += "  <tr class='details-row' style='display:none'>`n"
			$retVal += "    <td>&nbsp;</td><td colspan=5 style='white-space:normal; word-break:break-word; overflow-wrap:anywhere;'>`n"
			$retVal += "      <table><tr style='background-color: #FFFDE7'><td>`n"
			$object | ForEach-Object {
				if (-not ([string]::IsNullOrEmpty($_.ResProperties))) {
					$retVal += "        <ul>`n"
					
					try {
						$jsnProps = $_.ResProperties | ConvertFrom-Json
					} catch {
						$jsnProps = $_.ResProperties | ConvertTo-Json | ConvertFrom-Json
					} finally {
						$retVal += "        <li><strong>Properties:</strong><br>`n          "
						$retVal += ConvertTo-IndentedHtmlList -Object $_.ResProperties
						$retVal += "`n        </li>`n"
						
						# Evaluate the row data for the ACP		
						$chkElems = Set-acp -row $object -props $_.Resproperties -name $_.ResourceName
						if ($null -ne $chkElems) {
							[void]$outElems.Add($chkElems)
						}
					}
					$retVal += "        </ul>`n"
				}
			}
			$retVal += "      </td></tr></table>`n    </td>`n  </tr>`n"
			
			$cnt++
		}
	}
	
	# Close the Table
	$retVal += "</tbody></table>`n`n"
	
	return $retVal
}

function Get-ScriptDirectory {
<#
    .SYNOPSIS
        Get-ScriptDirectory returns the proper location of the script.
 
    .OUTPUTS
        System.String
   
    .NOTES
        Returns the correct path within a packaged executable.
#>
	[OutputType([string])]
	param ()
	if ($null -ne $hostinvocation) {
		Split-Path $hostinvocation.MyCommand.path
	} else {
		Split-Path $script:MyInvocation.MyCommand.Path
	}
}

#####################################
# M A I N  L I N E
#####################################

# Script Version
$myVer = "1.5.0"

# Default the Verbosity of messages to NOT
if ([string]::IsNullOrEmpty($Details)) {
	$Details = $false
}

# Set the Start Time
$startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$timeId = Get-Date -Format "yyyyMMddHHmmss"

# Get the directory path and file name without extension
$inFile = Split-Path $file -leaf
$dir = Split-Path -Path $file -Parent
$noExt = [System.IO.Path]::GetFileNameWithoutExtension($File)

# Get the script directory
$scriptDir = Get-ScriptDirectory

# Set up the output directory
if ([string]::IsNullOrEmpty($OutPath)) {
	$outDir = "$($scriptDir)\output"
} else {
	$outDir = "$($OutPath)"
}

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $outDir -PathType Container)) {
	New-Item -ItemType Directory -Force -Path $outDir
}

# Define the log file name
$log = "$($outDir)\resourceProcessor"
if ($Stamp) {
	$log = "$($log)_$($timeId)"
}
$log = "$($log).log"

# Write the program version to the log file/screen
Write-log -toConsole $Details -id 55 -msg "process-ResourceScrape.ps1 Version: $($myVer)"
Write-log -toConsole $Details -id 57 -msg "Input File: $($inFile)"

# Test for the existence of the Rules file
if (-not ([string]::IsNullOrEmpty($rulesFile))) {
	if (-not (Test-Path -Path $rulesFile -PathType Leaf)) {
		$rulesFile = "$($scriptDir)\rules.xml"
	}
} else {
	$rulesFile = "$($scriptDir)\rules.xml"
}
Write-log -toConsole $Details -id 58 -msg "Using Rules File: $($rulesFile)"

if (Test-Path $file -PathType Leaf) {
	Write-log -toConsole $Details -id 59 -msg "Input File Found. Continuing... `n"
	
	# Read the JSON file Resource Scrape
	$jsonScrape = Get-Content -Path $File -Raw | ConvertFrom-Json
	
	# Start building the HTML table markup
	$htmlTable = "`n<div id='resControls' style='margin:6px 0; display:flex; gap:8px; align-items:center; width:800px; max-width:800px; box-sizing:border-box;'>`n <input id='resSearch' type='text' placeholder='Search resources...' style='flex:1; min-width:0; padding:4px; border:1px solid #CFD8DC; border-radius:4px; box-sizing:border-box;' />`n <button id='btnExpandAll' type='button'>Expand all</button>`n <button id='btnCollapseAll' type='button'>Collapse all</button>`n</div>`n<table id='resTable' style='width:800px; table-layout:fixed;'>`n"
	
	# Get the property names from the first object to use as table headers
	$headers = "first", "Name", "Location", "Resource Group", "Resource Type", "last"
	
	# Add table headers
	Write-log -toConsole $Details -id 61 -msg "Adding Table headers`n"
	$htmlTable += (Add-headers -listHeaders $headers)
	$htmlTable += "`n<tbody>`n"
	
	# Add table rows
	Write-log -toConsole $Details -id 62 -msg "Building the report body`n"
	$htmlTable += (Build-Body -rowData $jsonScrape)
	
	# Build the final initial ACP suggestion
	Write-log -toConsole $Details -id 63 -msg "Building the initial ACP suggestion`n"
	
	# Build ACP as native objects (no string fragments)
	$typeElems = $typeElems | Sort-Object
	$anyOf = @()
	
	if ($outElems.Count -gt 0) {
		$anyOf += @($outElems)
	}
	
	if ($typeElems.Count -gt 0) {
		$anyOf += [ordered]@{
			field = 'type'; 'in' = @($typeElems)
		}
	}
	
	$acpPolicy = [ordered]@{
		'if' = [ordered]@{
			'not' = [ordered]@{
				'anyOf' = $anyOf
			}
		}
		'then' = [ordered]@{
			'effect' = 'deny'
		}
	}
	
	# Serialize ACP JSON (full) and a second copy with NOTE placeholders removed
	#	$acpFormatted = Normalize-JsonIndentation -Json ($acpPolicy | ConvertTo-Json -Depth 50) -Indent 2
	
	$acpFormatted = $acpPolicy | ConvertTo-Json -Depth 50
	$acpFormatted = $acpFormatted -replace '\\u0027', "'"
	$acpFormatted = $acpFormatted -replace 'null', """NOT FOUND IN RESOURCE SCRAPE"""
	$script:notFound = ([regex]::Matches($acpFormatted, "NOT FOUND IN RESOURCE SCRAPE")).Count
	$script:resFound = ([regex]::Matches($acpFormatted, """type""")).Count
	
	$acpFormatted = Normalize-JsonIndentation -Json $acpFormatted -Indent 2
	
	$acpPolicyClean = Remove-NotePlaceholderConditions -Node $acpPolicy
	$acpFormattedClean = Normalize-JsonIndentation -Json ($acpPolicyClean | ConvertTo-Json -Depth 50) -Indent 2
	$acpFormattedClean = $acpFormattedClean -replace 'null', """NOT IN RESOURCE SCRAPE"""
	
	Write-log -toConsole $Details -id 64 -msg "Defining the output files and paths`n"
	$outFile = Join-Path -Path $outDir -ChildPath "$($noExt).html"
	$outACP = (Join-Path -Path $outDir -ChildPath "$($noExt)").Replace("resourceScrape", "initialACP")
	$outACP += ".json"
	$inACPFile = Split-Path $outACP -leaf
	$outACPClean = $outACP.Replace('.json', '_noNote.json')
	$inACPCleanFile = Split-Path $outACPClean -leaf
	
	# Define the HTML document content
	Write-log -toConsole $Details -id 65 -msg "Assembling the HTML document`n"
	#  if (btn) btn.innerText = expanded ? '⮝' : '⮟';
	#  if (btn) btn.innerText = expanded ? '&#11165;' : '&#11167;';
	# line 966
	# 		<strong>Download Initial ACP (no NOTEs)&nbsp;&nbsp;-&nbsp;&nbsp;<a href="$outACPClean" download>$inACPCleanFile</a></strong><br>
	
	$htmlDocument = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>Resource Scrape Results</title>

<style>
    /* Basic table styling */
    table {
        border-collapse: collapse;
        width: 800px;
    }
    th, td {
        border: none;
		padding: 3;
		text-align: left;
		vertical-align:top;
    }

    /* Alternating row colors */
	th {
		background-color: #1E88E5; /* Header Row */
		color: white;
	}

 /* V15 UI constraints */
 #outTable { table-layout: fixed; }
 #resControls { max-width:800px; width:800px; box-sizing:border-box; }
 #resControls input { min-width:0; }
 #resTable { width:800px; table-layout:fixed; }

 /* V16 WRAPPING FIXES */
 #outTable, #resTable { table-layout: fixed; }
 th, td {
   white-space: normal;
   overflow-wrap: anywhere;
   word-break: break-word;
 }
 table td table td {
   white-space: normal;
   overflow-wrap: anywhere;
   word-break: break-word;
 }

</style>
</head>
<body>

<h2 style='text-align:center; background-color:#CFD8DC;'>Resource Scrape Results - $inFile</h2>
<table id='outTable' border=0><tr><td style='width:800px; vertical-align:top;'><strong>Download <a href="$inFile" download>$inFile</a></strong><br>
$htmlTable
</td>
<td>&nbsp;&nbsp;&nbsp;</td>
<td style='width:800px'>
    <strong>Download Initial ACP&nbsp;&nbsp;-&nbsp;&nbsp;<a href="$outACP" download>$inACPFile</a></strong><br>
<div id="acpControls" style="margin:6px 0; display:flex; gap:12px; align-items:center;">
  <label><input type="checkbox" id="chkHideNote"> Hide NOTEs</label>
  <label><input type="checkbox" id="chkHideUnfound"> Hide Unfound fields</label>
  <label>(Unfound Fields: <strong>$script:notFound</strong>)</label>
  <label>(Unique Resources: <strong>$script:resFound</strong>)</label>
  <button id='btnSaveACP'>Save ACP</button>
</div>
<textarea id="acpFullData" style="display:none;">$acpFormatted</textarea>
<textarea id="acpCleanData" style="display:none;">$acpFormattedClean</textarea>
<textarea id="initialACP" name="initialACP" rows="50" cols="100" onkeyup="textAreaAdjust(this)" style="overflow:hidden; overflow-y:scroll;">$acpFormatted</textarea><br>
<strong>ACP Documentation</strong>&nbsp;&nbsp;&nbsp;&nbsp;-&nbsp;&nbsp;&nbsp;<a href="https://docs.skillable.com/docs/azure-access-control-policy-creation" target="_blank">ACP Documentation</a><br>
<strong>Supported ACP Conditions</strong><br>
<ul>
<li>"equals": "stringValue"</li>
<li>"notEquals": "stringValue"</li>
<li>"like": "stringValue"</li>
<li>"notLike": "stringValue"</li>
<li>"match": "stringValue"</li>
<li>"matchInsensitively": "stringValue"</li>
<li>"notMatch": "stringValue"</li>
<li>"notMatchInsensitively": "stringValue"</li>
<li>"contains": "stringValue"</li>
<li>"notContains": "stringValue"</li>
<li>"in": ["stringValue1","stringValue2"]</li>
<li>"notIn": ["stringValue1","stringValue2"]</li>
<li>"containsKey": "keyName"</li>
<li>"notContainsKey": "keyName"</li>
<li>"less": "dateValue" | "less": "stringValue" | "less": intValue</li>
<li>"lessOrEquals": "dateValue" | "lessOrEquals": "stringValue" | "lessOrEquals": intValue</li>
<li>"greater": "dateValue" | "greater": "stringValue" | "greater": intValue</li>
<li>"greaterOrEquals": "dateValue" | "greaterOrEquals": "stringValue" | "greaterOrEquals": intValue</li>
<li>"exists": "bool"</li>
</ul>
</td></tr></table>

<script src='https://code.jquery.com/jquery-3.6.0.min.js'></script>
<script src='https://cdnjs.cloudflare.com/ajax/libs/jquery.tablesorter/2.31.3/js/jquery.tablesorter.min.js'></script>

<script>
function textAreaAdjust(element) {
  element.style.height = "1px";
  element.style.height = (25 + element.scrollHeight) + "px";
}

function getACPBaseText() {
  var hideNote = document.getElementById('chkHideNote');
  var srcId = (hideNote && hideNote.checked) ? 'acpCleanData' : 'acpFullData';
  var src = document.getElementById(srcId);
  return src ? src.value : '';
}

// Companion function: removes any condition object where equals contains the unfound sentinel
function removeUnfoundEqualsNodes(node, isRoot) {
  if (node === null || node === undefined) return node;

  if (Array.isArray(node)) {
    var cleanedArr = [];
    for (var i = 0; i < node.length; i++) {
      var child = removeUnfoundEqualsNodes(node[i], false);
      if (child !== null && child !== undefined) cleanedArr.push(child);
    }
    return cleanedArr;
  }

  if (typeof node === 'object') {
    if (!isRoot && Object.prototype.hasOwnProperty.call(node, 'equals')) {
      var eq = node.equals;
      if (typeof eq === 'string') {
        // Match both the new and legacy sentinel strings
        if (eq.indexOf('NOT IN RESOURCE SCRAPE') !== -1 ||
            eq.indexOf('NOT FOUND IN RESOURCE SCRAPE') !== -1 ||
            eq.indexOf('NOT FOUND IN RESOURCESCRAPE') !== -1) {
          return null;
        }
      }
    }

    var out = {};
    for (var k in node) {
      if (!Object.prototype.hasOwnProperty.call(node, k)) continue;
      var v = removeUnfoundEqualsNodes(node[k], false);
      if (v !== null && v !== undefined) out[k] = v;
    }
    return out;
  }

  return node;
}

function refreshACPTextarea() {
  var ta = document.getElementById('initialACP');
  if (!ta) return;

  var text = getACPBaseText();

  // Always normalize indentation to 2 spaces when possible
  // (This keeps formatting consistent whether toggles are used or not.)
  var parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    parsed = null;
  }

  var hideUnfound = document.getElementById('chkHideUnfound');
  if (parsed !== null && hideUnfound && hideUnfound.checked) {
    parsed = removeUnfoundEqualsNodes(parsed, true);
  }

  if (parsed !== null) {
    text = JSON.stringify(parsed, null, 2);
  }

  ta.value = text;
  textAreaAdjust(ta);
}

function wireACPToggles() {
  var chkNote = document.getElementById('chkHideNote');
  var chkUnfound = document.getElementById('chkHideUnfound');

  if (chkNote) chkNote.addEventListener('change', refreshACPTextarea);
  if (chkUnfound) chkUnfound.addEventListener('change', refreshACPTextarea);
}
function storageKey() {
  return 'resTableExpanded:' + window.location.pathname;
}

function getExpandedSet() {
  try {
    var raw = localStorage.getItem(storageKey());
    if (!raw) return new Set();
    var arr = JSON.parse(raw);
    return new Set(Array.isArray(arr) ? arr : []);
  } catch (e) {
    return new Set();
  }
}

function saveExpandedSet(set) {
  try {
    localStorage.setItem(storageKey(), JSON.stringify(Array.from(set)));
  } catch (e) {}
}

function findDetailsRow(mainRow) {
  var r = mainRow ? mainRow.nextElementSibling : null;
  while (r && !r.classList.contains('details-row')) {
    r = r.nextElementSibling;
  }
  return r;
}

function setRowExpanded(mainRow, expanded) {
  var detailsRow = findDetailsRow(mainRow);
  if (!detailsRow) return;
  detailsRow.style.display = expanded ? 'table-row' : 'none';
  var btn = mainRow.querySelector('button#prop');
  if (btn) btn.innerText = expanded ? '-' : '+';
}

function applyExpandedState() {
  var expanded = getExpandedSet();
  document.querySelectorAll('#resTable tr.main-row').forEach(function(row){
    var key = row.getAttribute('data-key');
    setRowExpanded(row, expanded.has(key));
  });
}

function expandAll() {
  var expanded = new Set();
  document.querySelectorAll('#resTable tr.main-row').forEach(function(row){
    var key = row.getAttribute('data-key');
    expanded.add(key);
    setRowExpanded(row, true);
  });
  saveExpandedSet(expanded);
}

function collapseAll() {
  document.querySelectorAll('#resTable tr.main-row').forEach(function(row){
    setRowExpanded(row, false);
  });
  saveExpandedSet(new Set());
}

// V15: Search that actually works.
function applyFilter(query) {
  query = (query || '').toLowerCase().trim();
  var expanded = getExpandedSet();

  document.querySelectorAll('#resTable tr.main-row').forEach(function(row){
    var hay = (row.getAttribute('data-search') || row.innerText || '').toLowerCase();
    var match = (query.length === 0) || (hay.indexOf(query) !== -1);

    var details = findDetailsRow(row);
    row.style.display = match ? 'table-row' : 'none';

    if (details) {
      if (!match) {
        details.style.display = 'none';
      } else {
        var key = row.getAttribute('data-key');
        details.style.display = expanded.has(key) ? 'table-row' : 'none';
      }
    }
  });
}

function wireUI() {
  var table = document.getElementById('resTable');
  if (!table) return;

  table.addEventListener('click', function(e){
    var btn = e.target.closest('button#prop');
    var mainRow = btn ? btn.closest('tr.main-row') : e.target.closest('tr.main-row');
    if (!mainRow) return;

    if (btn) {
      e.preventDefault();
      e.stopPropagation();
    }

    var key = mainRow.getAttribute('data-key');
    var expanded = getExpandedSet();
    var isExpanded = expanded.has(key);
    if (isExpanded) expanded.delete(key); else expanded.add(key);
    saveExpandedSet(expanded);
    setRowExpanded(mainRow, !isExpanded);
  });

  var btnExpandAll = document.getElementById('btnExpandAll');
  var btnCollapseAll = document.getElementById('btnCollapseAll');
  var search = document.getElementById('resSearch');

  if (btnExpandAll) btnExpandAll.addEventListener('click', function(e){
    e.preventDefault();
    expandAll();
    applyFilter(search ? search.value : '');
  });

  if (btnCollapseAll) btnCollapseAll.addEventListener('click', function(e){
    e.preventDefault();
    collapseAll();
    applyFilter(search ? search.value : '');
  });

  if (search) {
    var t = null;
    search.addEventListener('input', function(){
      if (t) clearTimeout(t);
      t = setTimeout(function(){ applyFilter(search.value); }, 120);
    });
  }
}


function saveInitialACPToJson() {
  const ta = document.getElementById('initialACP');
  if (!ta) return;
  let content = ta.value || '';
  try { content = JSON.stringify(JSON.parse(content), null, 2); } catch {}
  (async () => {
    try {
      const handle = await window.showSaveFilePicker({
        suggestedName: '',
        types: [{ description: 'JSON Files', accept: { 'application/json': ['.json'] } }]
      });
      const writable = await handle.createWritable();
      await writable.write(content);
      await writable.close();
    } catch {}
  })();
}
function wireSaveButton(){
 const btn=document.getElementById('btnSaveACP');
 if(btn){btn.addEventListener('click',saveInitialACPToJson);} }

document.addEventListener('DOMContentLoaded', function(){
  document.querySelectorAll('#resTable tr.details-row').forEach(function(r){ r.style.display = 'none'; });
  applyExpandedState();
  wireUI();
 wireACPToggles();
 wireSaveButton();
  refreshACPTextarea();
  applyFilter('');
});
</script>

</body>
</html>
"@
	
	Write-log -toConsole $Details -id 66 -msg "Writing out the HTML file and initial ACP file`n"
	
	# Save the HTML document to a file
#	$htmlDocument | Out-File -FilePath $outFile -Encoding UTF8
#	[System.IO.File]::WriteAllText($outFile, $htmlDocument, [System.Text.UTF8Encoding]::new($false))
	
	[System.IO.File]::WriteAllText(
		$outFile,
		$htmlDocument,
		[System.Text.UTF8Encoding]::new($true)
	)
	
	
	
	
	
	# Save the initial ACP to a file
	$acpFormatted | Set-Content -Path $outACP -Encoding UTF8
	$acpFormattedClean | Set-Content -Path $outACPClean -Encoding UTF8
	
	# Open the HTML document in the default web browser
	if ($showHtml) {
		Invoke-Item $outFile
	}
} else {
	Write-log -toConsole $Details -id 10 -msg "Input file path is required. Please try again.`nFile: $($file)"
	throw "Invalid file or path. Please try again."
	exit
}
