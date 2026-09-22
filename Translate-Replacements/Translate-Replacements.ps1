<#
	.SYNOPSIS
		Connects to Lab On Demand and executes Extract-Instructions.ps1.
	
	.DESCRIPTION
		Logs into the Studio platform using Connect-LabOnDemand.
		If the connection succeeds, calls Extract-Instructions.ps1 and:
		
		- Passes SourceLabProfile
		- Passes SourceInstructionsSet
		- Passes OutputPath
		- Displays all output produced by Extract-Instructions.ps1
		- Captures the returned string value
	
	.PARAMETER SourceLabProfileId
		A description of the SourceLabProfileId parameter.
	
	.PARAMETER SourceInstructionsSetId
		A description of the SourceInstructionsSetId parameter.
	
	.PARAMETER TargetLabProfileId
		A description of the TargetLabProfileId parameter.
	
	.PARAMETER TargetInstructionsSetId
		A description of the TargetInstructionsSetId parameter.
	
	.PARAMETER ClaudeModel
		A description of the ClaudeModel parameter.
	
	.PARAMETER OutputPath
		A description of the OutputPath parameter.
	
	.PARAMETER ListIndentSize
		A description of the ListIndentSize parameter.
	
	.PARAMETER MaxCharsPerChunk
		A description of the MaxCharsPerChunk parameter.
	
	.PARAMETER sessionToken
		A description of the sessionToken parameter.
	
	.PARAMETER FindList
		A description of the FindList parameter.
	
	.PARAMETER CaseSensitivity
		A description of the CaseSensitivity parameter.
	
	.PARAMETER SourceLabProfile
		A description of the SourceLabProfile parameter.
	
	.PARAMETER SourceInstructionsSet
		A description of the SourceInstructionsSet parameter.
	
	.PARAMETER TargetLabProfile
		A description of the TargetLabProfile parameter.
	
	.PARAMETER TargetInstructionsSet
		A description of the TargetInstructionsSet parameter.
	
	.NOTES
		Requires Skillable LOD.Core module and a valid Studio login.
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2026 v5.10.272
		Created on:   	9/2/2026 9:46 AM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:		Translate-Replacements.ps1
		===========================================================================
#>
[CmdletBinding()]
param
(
	[Parameter(Mandatory = $true)]
	[int]$SourceLabProfileId,
	[int]$SourceInstructionsSetId = 0,
	[Parameter(Mandatory = $true)]
	[int]$TargetLabProfileId,
	[int]$TargetInstructionsSetId = 0,
	[string]$ClaudeModel = "claude-sonnet-5",
	[string]$OutputPath,
	[int]$ListIndentSize = 5,
	[int]$MaxCharsPerChunk = 100000,
	$sessionToken
)

$curDate = Get-Date -Format 'yyyyMMdd_HHmmss'

function Build-InstructionsFile {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[int]$LabProfileId,
		[int]$InstructionsId = 0,
		[Parameter(Mandatory = $true)]
		[string]$ScriptPath,
		[string]$ScriptName,
		[string]$OutputPath,
		[switch]$GetReplacements
	)
	
	$retVal = $null
	
	# ######################################################
	Write-Host "Executing Extract-Instructions.ps1 for Source $LabProfileId..." -ForegroundColor Cyan
	Write-Host ""
	
	try {
		
		# Capture all output while still displaying it in the console.
		#		$scriptOutput = & $buildScript -LabProfileId $LabProfileId -InstructionsSetId $InstructionsSetId -OutputName $ScriptName -OutputPath $outputPath 2>&1
		$test = "-LabProfileId $($LabProfileId) -InstructionsSetId $($InstructionsId) -OutputName $($ScriptName) -OutputPath $($outputPath) -GetReplacements"
		Write-Host "  Params: $($test)"
		if ($GetReplacements) {
			$scriptOutput = & $ScriptPath -LabProfileId $LabProfileId -InstructionsSetId $InstructionsId -OutputName $ScriptName -OutputPath $outputPath -GetReplacements 2>&1
		} else {
			$scriptOutput = & $ScriptPath -LabProfileId $LabProfileId -InstructionsSetId $InstructionsId -OutputName $ScriptName -OutputPath $outputPath 2>&1
		}
		
		# Echo all output from the child script.
		$scriptOutput | ForEach-Object {
			Write-Host $_
		}
		
		# Assume the final object returned by the script is the string result.
		$retValue = $scriptOutput | Select-Object -Last 1
		
		Write-Host ""
		Write-Host "Extract-Instructions.ps1 returned:" -ForegroundColor Green
		Write-Host "  $retValue"
		
	} catch {
		Write-Host "ERROR executing Extract-Instructions.ps1:" -ForegroundColor Red
		Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
	}
	
	return [string]$retValue
}


Write-Host "Connecting to Studio..." -ForegroundColor Cyan
try {
	Connect-LabOnDemand -SessionToken $sessionToken
} catch {
	try {
		Connect-LabOnDemand
	} catch {
		Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
		return
	}
}

Write-Host "Connected successfully." -ForegroundColor Green
Write-Host ""

# Determine location of Extract-Instructions.ps1
$buildScript = Join-Path $PSScriptRoot 'Extract-Instructions.ps1'

if (-not (Test-Path $buildScript)) {
	Write-Host "ERROR: Unable to locate '$buildScript'" -ForegroundColor Red
	return
}

$srcPath = Build-InstructionsFile -ScriptPath $buildScript -OutputPath $OutputPath -LabProfileId $SourceLabProfileId -InstructionsId $SourceInstructionsSetId -ScriptName "Src" -GetReplacements
Write-Host "Source File: $srcPath"

$trgPath = Build-InstructionsFile -ScriptPath $buildScript -OutputPath $OutputPath -LabProfileId $TargetLabProfileId -InstructionsId $TargetInstructionsSetId -ScriptName "Trg"
Write-Host "Target File: $trgPath"

# Retrieve the Replacements from the Source Lab Profile
$repFile = $srcPath -replace '_(\d{8}_\d{6})\.md$', '-REP_$1.csv'
Write-Host "Replacements File: $repFile"

# Determine location of Extract-Instructions.ps1
$ReplacementsScript = Join-Path $PSScriptRoot 'Apply-Replacements.ps1'
if (-not (Test-Path $ReplacementsScript)) {
	Write-Host "ERROR: Unable to locate '$ReplacementsScript'" -ForegroundColor Red
	return
}

# Launch the Apply-Replacements Script
$buildScript = Join-Path $PSScriptRoot 'Apply-Replacements.ps1'
try {
#	$test = "$($buildScript) -InstructionsFile $($srcPath) -TranslationFile $($trgPath) -ReplacementsFile $($repFile) -ClaudeModel $($ClaudeModel) -ReportRepLine -OutputName 'REP' -OutputPath $($outputPath)"
	$replacementsFile = & $buildScript -InstructionsFile $srcPath -TranslationFile $trgPath -ReplacementsFile $repFile -ClaudeModel $ClaudeModel -ReportRepLine -OutputName 'REP' -OutputPath $outputPath 2>&1
	# Echo all output from the child script.
	$replacementsFile | ForEach-Object {
		Write-Host $_
	}
	
	# Assume the final object returned by the script is the string result.
	$retValue = $replacementsFile | Select-Object -Last 1
	
	Write-Host ""
	Write-Host "Apply-Replacements.ps1 returned:" -ForegroundColor Green
	Write-Host "  $retValue"
} catch {
	Write-Host "ERROR executing Apply-Replacements.ps1:" -ForegroundColor Red
	Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
}
