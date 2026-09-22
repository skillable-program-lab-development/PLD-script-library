<#
	.SYNOPSIS
		Builds a local Markdown instructions file with GitHub instruction includes expanded.
	
	.DESCRIPTION
		Retrieves a Lab Profile through Skillable LOD.Core, selects the requested
		Instructions Set, finds !INSTRUCTIONS[](...) include directives, downloads
		each referenced raw GitHub Markdown file, and replaces the include directive
		with the downloaded Markdown.
		
		The completed Markdown is saved as tmpSrc_<CurrentDate>.md and the full path
		is written to the success output stream for the calling script.
	
	.PARAMETER LabProfileId
		A description of the LabProfileId parameter.
	
	.PARAMETER InstructionsSetId
		A description of the InstructionsSetId parameter.
	
	.PARAMETER CurrentDate
		A description of the CurrentDate parameter.
	
	.PARAMETER OutputName
		A description of the OutputName parameter.
	
	.PARAMETER OutputPath
		A description of the OutputPath parameter.
	
	.PARAMETER GetReplacements
		A description of the GetReplacements parameter.
	
	.PARAMETER GetVariables
		A description of the GetVariables parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2026 v5.10.272
		Created on:   	9/2/2026 10:13 AM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	Extract-Instructions.ps1
		===========================================================================
#>
[CmdletBinding()]
param
(
	[Parameter(Mandatory = $true)]
	[int]$LabProfileId,
	[int]$InstructionsSetId = 0,
	[datetime]$CurrentDate = (Get-Date),
	[string]$OutputName,
	[Parameter(Mandatory = $true)]
	[string]$OutputPath,
	[switch]$GetReplacements,
	[switch]$GetVariables
)

Set-StrictMode -Version Latest
#$ErrorActionPreference = 'Stop'

class ReplacementJSON {
	[string]$Text
	[string]$Replacement
	[bool]$Regex
	[bool]$CaseSensitive
	[bool]$Enabled
	
	conResult([string]$Text, [string]$Replacement, [bool]$Regex, [bool]$CaseSensitive, [bool]$Enabled) {
		$this.Text = $Text
		$this.Replacement = $Replacement
		$this.Regex = $Regex
		$this.CaseSensitive = $CaseSensitive
		$this.Enabled = $Enabled
	}
}

class VariablesJSON {
	[string]$Name
	[string]$Value
	
	conResult([string]$Name, [string]$Value) {
		$this.Name = $Name
		$this.Value = $Value
	}
}

function Get-IncludeUrl {
	param ([Parameter(Mandatory)]
		[string]$IncludeLine)
	
	$urlMatch = [regex]::Match(
		$IncludeLine,
		'https://raw\.githubusercontent\.com/[^\s\)\]"''<>]+',
		[System.Text.RegularExpressions.RegexOptions]::IgnoreCase
	)
	
	if (-not $urlMatch.Success) {
		throw "No raw GitHub URL was found in include line: $IncludeLine"
	}
	
	[System.Net.WebUtility]::HtmlDecode($urlMatch.Value).TrimEnd(')')
}

#Write-Host "Connecting to Studio..." -ForegroundColor Cyan
#try {
#	Connect-LabOnDemand
#} catch {
#	Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
#	return
#}

try {
	if (-not (Get-Command Get-LODLabProfileInstructionsSets -ErrorAction SilentlyContinue)) {
		throw 'Get-LODLabProfileInstructionsSets was not found. Import LOD.Core before running this script.'
	}
	
	Write-Host "Retrieving Instructions Set details from Lab Profile $LabProfileId..." -ForegroundColor Cyan
	
	try {
		$inst = Get-LODLabProfileInstructionsSets -LabProfileId $LabProfileId
		$set = $null
		if ($InstructionsSetId -eq 0) {
			Write-Host "Retrieving the default Instructions Set details from Lab Profile $LabProfileId..." -ForegroundColor Cyan
			$set = $inst.instructionsSets[0]
		} else {
			Write-Host "Retrieving Instructions Set $($InstructionsSetId) details from Lab Profile $LabProfileId..." -ForegroundColor Cyan
			foreach ($in in $inst.instructionsSets) {
				if ($InstructionsSetId -eq $in.Id) {
					$set = $in
				}
			}
		}
	} catch {
		if ($_.Exception.Message -like "*404*") {
			Write-Host "Could not retrieve the Instructions Sets. ERROR: 404 Could not access URL"
		} else {
			throw "Could not retrieve the Instructions Sets. ERROR: $($_.Exception.Message)"
		}
	}
	
	if (-not (Get-Command Get-LODLabProfileInstructions -ErrorAction SilentlyContinue)) {
		throw 'Get-LODLabProfileInstructions was not found. Import LOD.Core before running this script.'
	}
	
	Write-Host "Retrieving Instructions $($set.id) from Lab Profile $LabProfileId..." -ForegroundColor Cyan
	
	$inst = Get-LODLabProfileInstructions -LabProfileId $LabProfileId -InstructionsSetId $set.Id
	
	if ($null -eq $inst) {
		throw "No instructions were returned for Lab Profile $LabProfileId and Instructions Set $($set.Id)."
	}
	
	if ($null -eq $inst.instructions) {
		throw "The object returned by Get-LODLabProfileInstructions does not contain an instructions property."
	}
	
	$expandedInstructions = [string]$inst.instructions
	
	# Replace @lab.LanguageCode values
	$expandedInstructions = $expandedInstructions -ireplace "@lab.LanguageCode", $set.LanguageShortName
	$expandedInstructions = $expandedInstructions -ireplace [regex]::Escape("@lab.LanguageCode"), $set.LanguageShortName
	
	# Supports !INSTRUCTIONS[](...), !INSTRUCTIONS [ ](...), and mixed casing.
	# Each include must occupy its own line.
	$includePattern = '(?im)^[\t ]*!instructions[\t ]*\[[\t ]*\][\t ]*\([^\r\n]+\)[\t ]*$'
	$includeMatches = [regex]::Matches($expandedInstructions, $includePattern)
	$downloadCache = @{
	}
	
	Write-Host "Found $($includeMatches.Count) instructions include(s)." -ForegroundColor Cyan
	
	foreach ($includeMatch in $includeMatches) {
		$includeLine = $includeMatch.Value
		$includeUrl = Get-IncludeUrl -IncludeLine $includeLine
		
		Write-Host "Retrieving included instructions: $includeUrl" -ForegroundColor DarkCyan
		
		if (-not $downloadCache.ContainsKey($includeUrl)) {
			try {
				$response = Invoke-WebRequest -Uri $includeUrl -UseBasicParsing
				$downloadCache[$includeUrl] = [string]$response.Content
				
				$replacement = $downloadCache[$includeUrl].TrimEnd("`r", "`n")
				$expandedInstructions = $expandedInstructions.Replace($includeLine, $replacement)
			} catch {
				if ($_.Exception.Message -like "*404*") {
					Write-Host "  Retrieval failed due to 404 error. ERROR: $($_.Exception.Message)"
					$expandedInstructions = $expandedInstructions.Replace($includeLine, "Error:404-$($includeLine)")
				} else {
					throw $_.Exception
				}
			}
		}
	}
	
	if (-not (Test-Path -LiteralPath $OutputPath)) {
		$null = New-Item -Path $OutputPath -ItemType Directory -Force
	}
	
	$resolvedOutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
	$dateStamp = $CurrentDate.ToString('yyyyMMdd_HHmmss')
	$tmpSrcPath = Join-Path $resolvedOutputPath "$($OutputName)_$dateStamp.md"
	
	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	[System.IO.File]::WriteAllText($tmpSrcPath, $expandedInstructions, $utf8NoBom)
	
	Write-Host "Expanded instructions saved to: $tmpSrcPath" -ForegroundColor Green
	
	# If the Variables are requested then write out a CSV file for them
	if ($GetVariables) {
		Write-Host "Attempting to extract Variables" -ForegroundColor Green
		if ($inst.variables) {
			Write-Host "  Variables Found" -ForegroundColor Green
			
			$var = $inst.variables | ConvertTo-Json
			
			# Create the Proper CSV
			$outResult = [System.Collections.Generic.List[VariablesJSON]]::new()
			
			foreach ($row in $inst.variables) {
				if (-not ($row -like "#*")) {
					$arr = $row.split(",")
					# Add the info to the output array
					$tmpResult = [VariablesJSON]::new()
					$tmpResult.Name = $arr[0]
					$tmpResult.Value = $arr[1]
					
					$outResult.add($tmpResult)
				}
			}
			# write out the variables
			$tmpVarPath = Join-Path $resolvedOutputPath "$($OutputName)-VAR_$dateStamp.csv"
#			[System.IO.File]::WriteAllText($tmpVarPath, $var, $utf8NoBom)
			$outResult | Export-Csv -Path $tmpVarPath -NoTypeInformation -Encoding UTF8 -Force
			Write-Host "Variables saved to: $tmpVarPath" -ForegroundColor Green
		} else {
			Write-Output "The object returned by Get-LODLabProfileInstructions does not contain any variable."
		}
	}
	
	# If the Replacements are requested then write out a CSV file for them
	if ($GetReplacements) {
		Write-Host "Attempting to extract Replacements" -ForegroundColor Green
		if ($inst.replacements) {
			Write-Host "  Replacements Found" -ForegroundColor Green
			
			$rep = $inst.replacements | ConvertTo-Json
			
			# Create the Proper CSV
			$outResult = [System.Collections.Generic.List[ReplacementJSON]]::new()
			
			foreach ($row in $inst.replacements) {
				# Add the info to the output array
				$tmpResult = [ReplacementJSON]::new()
				$tmpResult.Text = $row.Text
				$tmpResult.Replacement= $row.Replacement
				try { $tmpResult.Regex = $row.Regex } catch { $tmpResult.Regex = $true }
				try { $tmpResult.CaseSensitive = $row.CaseSensitive } catch { $tmpResult.CaseSensitive = $true }
				try { $tmpResult.Enabled = $row.Enabled } catch { $tmpResult.Enabled = $true }
				
				$outResult.add($tmpResult)
				
			}
			
			# write out the Replacements
			$tmpRepPath = Join-Path $resolvedOutputPath "$($OutputName)-REP_$dateStamp.csv"
#			[System.IO.File]::WriteAllText($tmpRepPath, $rep, $utf8NoBom)
			$outResult | Export-CSV -Path $tmpRepPath -NoTypeInformation -Encoding UTF8 -Force
			Write-Host "Text-Swaps saved to: $tmpRepPath" -ForegroundColor Green
		} else {
			Write-Output "The object returned by Get-LODLabProfileInstructions does not contain any Text-Swaps."
		}
	}
	
	# Return only the full filename on the success output stream.
	Write-Output $tmpSrcPath
} catch {
	if ($_.Exception.Message -like "*404*") {
		Write-Host "Extract-Instructions.ps1 failed: Encountered 404 message"
	} else {
		Write-Error "Extract-Instructions.ps1 failed: $($_.Exception.Message)"
		throw
	}
}
