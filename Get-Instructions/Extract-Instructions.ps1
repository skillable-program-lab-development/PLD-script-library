<#
	.SYNOPSIS
		Builds a local Markdown instructions file with GitHub instruction includes expanded.
	
	.DESCRIPTION
		Retrieves a Lab Profile through Skillable LOD.Core, selects the requested
		Instructions Set, finds !INSTRUCTIONS[](...) include directives (if necessary), downloads
		each referenced raw GitHub Markdown file (if necessary), and replaces the include directive
		with the downloaded Markdown (if necessary).
		
		The completed Markdown is saved as tmpSrc_<CurrentDate>.md and the full path
		is written to the success output stream for the calling script.
	
	.PARAMETER LabProfileId
		A description of the LabProfileId parameter.
	
	.PARAMETER InstructionsSetId
		A description of the InstructionsSetId parameter.
	
	.PARAMETER ExpandIncludes
		A description of the ExpandIncludes parameter.
	
	.PARAMETER OutputName
		A description of the OutputName parameter.
	
	.PARAMETER OutputPath
		A description of the OutputPath parameter.
	
	.PARAMETER Token
		A description of the Token parameter.
	
	.PARAMETER CurrentDate
		A description of the CurrentDate parameter.
	
	.PARAMETER Write-Note -Note
		A description of the Write-Note -Note parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2026 v5.10.272
		Created on:   	9/4/2026 3:56 PM
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
	[switch]$ExpandIncludes,
	[string]$OutputName = "Expanded",
	[string]$OutputPath,
	$Token
)

Set-StrictMode -Version Latest
#$ErrorActionPreference = 'Stop'
[datetime]$CurrentDate = (Get-Date)

# Define Colors 
$reset = "$([char]27)[0m"
$cyan = "$([char]27)[36m"
$darkcyan = "$([char]27)[46m"
$red = "$([char]27)[31m"
$green = "$([char]27)[32m"


function Write-Note {
	[CmdletBinding()]
	param
	(
		$note,
		[switch]$hideTimeStamp,
		[string]$ForeColor
	)
	
	$timeStamp = Get-Date -Format "MM/dd/yy_HH:mm:ss"
	
	if ($hideTimeStamp) {
		if ($ForeColor) {
			$color = "`${$($ForeColor)}"
#			Write-Output "$($color)$($note)`${reset}"
			Write-Output "$($ForeColor)$($note)$($reset)"
		} else {
			Write-Output "$($note)"
		}
	} else {
		if ($ForeColor) {
			$color = "`${$($ForeColor)}"
#			Write-Output "$($timeStamp):  $($color)$($note)`${reset}"
			Write-Output "$($timeStamp):  $($ForeColor)$($note)$($reset)"
		} else {
			Write-Output "$($timeStamp):  $($note)"
		}
	}
}

function Get-ScriptDirectory {
	[OutputType([string])]
	param ()
	
	$retVal = ""
	if ($null -ne $hostinvocation) {
		$retVal = Split-Path $hostinvocation.MyCommand.path
	} else {
		$retVal = Split-Path $script:MyInvocation.MyCommand.Path
	}
	
	return $retVal
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

# Set the default folder
if (-not $OutputPath) {
	$OutputPath = Get-ScriptDirectory
}

#Write-Note -Note "Connecting to Studio..." -ForegroundColor Cyan
try {
	if ($Token) {
		Connect-LabOnDemand -SessionToken $Token
	} else {
		Connect-LabOnDemand
	}
} catch {
	#	Write-Note -Note "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
#	Write-Note -Note "  ERROR: $($_.Exception.Message)" -ForeColor $red
	Write-Note -Note "  ERROR: $($_.Exception.Message)" 
	return
}

try {
	if (-not (Get-Command Get-LODLabProfileInstructionsSets -ErrorAction SilentlyContinue)) {
		throw 'Get-LODLabProfileInstructionsSets was not found. Import LOD.Core before running this script.'
	}
	
#	Write-Note -Note "Retrieving Instructions Set details from Lab Profile $LabProfileId..." -ForegroundColor Cyan
#	Write-Note -Note "Retrieving Instructions Set details from Lab Profile $LabProfileId..." -ForeColor $cyan
	Write-Note -Note "Retrieving Instructions Set details from Lab Profile $LabProfileId..." 
	
	try {
		$inst = Get-LODLabProfileInstructionsSets -LabProfileId $LabProfileId
		$set = $null
		if ($InstructionsSetId -eq 0) {
#			Write-Note -Note "Retrieving the default Instructions Set details from Lab Profile $LabProfileId..." -ForegroundColor Cyan
#			Write-Note -Note "Retrieving the default Instructions Set details from Lab Profile $LabProfileId..." -ForeColor $cyan
			Write-Note -Note "Retrieving the default Instructions Set details from Lab Profile $LabProfileId..." 
			$set = $inst.instructionsSets[0]
		} else {
#			Write-Note -Note "Retrieving Instructions Set $($InstructionsSetId) details from Lab Profile $LabProfileId..." -ForegroundColor Cyan
#			Write-Note -Note "Retrieving Instructions Set $($InstructionsSetId) details from Lab Profile $LabProfileId..." -ForeColor $cyan
			Write-Note -Note "Retrieving Instructions Set $($InstructionsSetId) details from Lab Profile $LabProfileId..."
			foreach ($in in $inst.instructionsSets) {
				if ($InstructionsSetId -eq $in.Id) {
					$set = $in
				}
			}
		}
	} catch {
		throw "Could not retrieve the Instructions Sets. ERROR: $($_.Exception.Message)"
	}
	
	if (-not (Get-Command Get-LODLabProfileInstructions -ErrorAction SilentlyContinue)) {
		throw 'Get-LODLabProfileInstructions was not found. Import LOD.Core before running this script.'
	}
	
#	Write-Note -Note "Retrieving Instructions $($set.id) from Lab Profile $LabProfileId..." -ForegroundColor Cyan
#	Write-Note -Note "Retrieving Instructions $($set.id) from Lab Profile $LabProfileId..." -ForeColor $cyan
	Write-Note -Note "Retrieving Instructions $($set.id) from Lab Profile $LabProfileId..."
	
	$inst = Get-LODLabProfileInstructions -LabProfileId $LabProfileId -InstructionsSetId $set.Id
	
	if ($null -eq $inst) {
		throw "No instructions were returned for Lab Profile $LabProfileId and Instructions Set $($set.Id)."
	}
	
	if ($null -eq $inst.instructions) {
		throw "The object returned by Get-LODLabProfileInstructions does not contain an instructions property."
	}
	
	# WK
	$expandedInstructions = [string]$inst.instructions
	
	if ($ExpandIncludes) {
		# Replace @lab.LanguageCode values
		$expandedInstructions = $expandedInstructions -ireplace "@lab.LanguageCode", $set.LanguageShortName
		$expandedInstructions = $expandedInstructions -ireplace [regex]::Escape("@lab.LanguageCode"), $set.LanguageShortName
		
		# Supports !INSTRUCTIONS[](...), !INSTRUCTIONS [ ](...), and mixed casing.
		# Each include must occupy its own line.
		$includePattern = '(?im)^[\t ]*!instructions[\t ]*\[[\t ]*\][\t ]*\([^\r\n]+\)[\t ]*$'
		$includeMatches = [regex]::Matches($expandedInstructions, $includePattern)
		$downloadCache = @{
		}
		
#		Write-Note -Note "Found $($includeMatches.Count) instructions include(s)." -ForegroundColor Cyan
#		Write-Note -Note "Found $($includeMatches.Count) instructions include(s)." -ForeColor $cyan
		Write-Note -Note "Found $($includeMatches.Count) instructions include(s)." 
		
		foreach ($includeMatch in $includeMatches) {
			$includeLine = $includeMatch.Value
			$includeUrl = Get-IncludeUrl -IncludeLine $includeLine
			
#			Write-Note -Note "Retrieving included instructions: $includeUrl" -ForegroundColor DarkCyan
#			Write-Note -Note "Retrieving included instructions: $includeUrl" -ForeColor $darkcyan
			Write-Note -Note "Retrieving included instructions: $includeUrl"
			
			if (-not $downloadCache.ContainsKey($includeUrl)) {
				try {
					$response = Invoke-WebRequest -Uri $includeUrl -UseBasicParsing
					$downloadCache[$includeUrl] = [string]$response.Content
				} catch {
					$downloadCache[$includeUrl] = "ERR: $($includeLine)"
				}
			}
			
			$replacement = $downloadCache[$includeUrl].TrimEnd("`r", "`n")
			$expandedInstructions = $expandedInstructions.Replace($includeLine, $replacement)
			
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
	
#	Write-Note -Note "Expanded instructions saved to: $tmpSrcPath" -ForegroundColor Green
#	Write-Note -Note "Expanded instructions saved to: $tmpSrcPath" -ForeColor $green
	Write-Note -Note "Expanded instructions saved to: $tmpSrcPath"
	
	# Return only the full filename on the success output stream.
	Write-Output $tmpSrcPath
} catch {
	Write-Error "Build-WithReplacements.ps1 failed: $($_.Exception.Message)"
	throw
}


