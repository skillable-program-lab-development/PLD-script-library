<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		A description of the file.
	
	.PARAMETER InstructionsFile
		A description of the InstructionsFile parameter.
	
	.PARAMETER TranslationFile
		A description of the TranslationFile parameter.
	
	.PARAMETER ReplacementsFile
		A description of the ReplacementsFile parameter.
	
	.PARAMETER ReportRepLine
		A description of the ReportRepLine parameter.
	
	.PARAMETER OutputPath
		A description of the OutputPath parameter.
	
	.PARAMETER OutputName
		A description of the OutputName parameter.
	
	.PARAMETER ClaudeModel
		A description of the ClaudeModel parameter.
	
	.PARAMETER OutputFile
		A description of the OutputFile parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2026 v5.10.272
		Created on:   	9/8/2026 1:15 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:		Apply-Replacements.ps1
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true)]
	[string]$InstructionsFile,
	[Parameter(Mandatory = $true)]
	[string]$TranslationFile,
	[Parameter(Mandatory = $true)]
	[string]$ReplacementsFile,
	[switch]$ReportRepLine,
	[string]$ClaudeModel = "claude-sonnet-5",
	[string]$OutputPath,
	[string]$OutputName = "Temp"
)

class rptLines {
	[string]$Text
	[bool]$Enabled
	[int]$Line
	
	conResult([string]$Text, [bool]$Enabled, [int]$Line) {
		$this.Text = $Text
		$this.Enabled = $Enabled
		$this.Line = $Line
	}
}

class Swaps {
	[string]$Text1
	[string]$Swap1
	[bool]$IsRegex
	[bool]$IsCaseSensitive
	[bool]$IsEnabled
	[string]$Text2
	[string]$Swap2
	[string]$Notes
	
	conResult([string]$Text1, [string]$Swap1, [bool]$IsRegex, [bool]$IsCaseSensitive, [bool]$IsEnabled, [string]$Text2, [string]$Swap2, [string]$Notes) {
		$this.Text1 = $Text1
		$this.Swap1 = $Swap1
		$this.IsRegex = $IsRegex
		$this.IsCaseSensitive = $IsCaseSensitive
		$this.IsEnabled = $IsEnabled
		$this.Notes = $Notes
	}
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check if the Instructions File is available
if (Test-Path -LiteralPath $InstructionsFile) {
	# Read the Instructions into Memory
	Write-Host "Retrieving the Instructions File." -ForegroundColor Green
	Write-Host "  $($InstructionsFile)" -ForegroundColor Green
	$inst = Get-Content -Path $InstructionsFile -Encoding UTF8 -Raw
	
	# Check if the Replacements File is available
	if (Test-Path -LiteralPath $ReplacementsFile) {
		# Read the Replacements file into Memory
		Write-Host "Retrieving the Replacements File." -ForegroundColor Green
		Write-Host "  $($ReplacementsFile)" -ForegroundColor Green
		$swap = Import-Csv -Path $ReplacementsFile -Encoding UTF8
		
		# Read the Translation into Memory
		if (Test-Path -LiteralPath $TranslationFile) {
			Write-Host "Retrieving the Translation File." -ForegroundColor Green
			Write-Host "  $($TranslationFile)" -ForegroundColor Green
			$tran = Get-Content -Path $TranslationFile -Encoding UTF8 -Raw
		} 
		
		
		# Check for the Output Path
		if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
			# Create the output path
			New-Item -ItemType Directory -Path $OutputPath | Out-Null
		}
		
		# Delete the output file if it exists
		if (Test-Path -LiteralPath (Join-Path -Path $OutputPath -ChildPath $OutputName)) {
			Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath $OutputName)
		}
		
		# Apply the replacements to the Instructions File
		$outFile = $inst
		# Create the Proper CSV
		$outResult = [System.Collections.Generic.List[rptLines]]::new()
		$y = 0
		$SwapLine = ""
		$swapResults = [System.Collections.Generic.List[object]]::new()
		foreach ($item in $swap) {
			if ($item.Enabled -eq "True") {
				# Execute the replacement of values
				if ($item.Regex -eq "True") {
					if ($item.CaseSensitive -eq "True") {
						$outFile = $outFile -creplace $item.Text, $item.Replacement
					} else {
						$outFile = $outFile -ireplace $item.Text, $item.Replacement
					}
				} else {
					
					# Get the Text-Swap Translation
					# WK
					$buildScript = Join-Path $PSScriptRoot 'Get-SwapTranslation.ps1'
					try {
						if ($tran.ToString().Length -eq 0) { $tran = " " }
#						$test = "$($buildScript) -EnglishText $($outFile) -TranslatedText $($tran) -SearchPhrase $($item.Text) -Model $($ClaudeModel) -CaseSensitive"
						if ($item.CaseSensitive -eq "True") {
#							[PSCustomObject]$SwapLine = & $buildScript -EnglishText $outFile -TranslatedText $tran -SearchPhrase $item.Text -Model $ClaudeModel -CaseSensitive 2>&1
							$result = & $buildScript -EnglishText $outFile -TranslatedText $tran -SearchPhrase $item.Text -Model $ClaudeModel -CaseSensitive 2>&1
						} else {
#							[PSCustomObject]$SwapLine = & $buildScript -EnglishText $outFile -TranslatedText $tran -SearchPhrase $item.Text -Model $ClaudeModel 2>&1
							$result = & $buildScript -EnglishText $outFile -TranslatedText $tran -SearchPhrase $item.Text -Model $ClaudeModel 2>&1
						}
						# Echo all output from the child script.
						Write-Host ""
						
						Write-Host "Get-SwapTranslation.ps1 returned:" -ForegroundColor Green
#						Write-Host "  $SwapLine" -ForegroundColor Green
						Write-Host "  $result" -ForegroundColor Green
						
						$swapResults.Add($result)
					} catch {
						Write-Host "ERROR executing Get-SwapTranslation.ps1:" -ForegroundColor Red
						Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
					}
					
					# Replace the text in the outFile
					if ($item.CaseSensitive -eq "True") {
						$outFile = ([string]$outFile).Replace($item.Text, $item.Replacement)
					} else {
						#						$outFile = $outFile -creplace $item.Text $item.Replacement
						#						$outFile = ([string]$outFile).Replace($item.Text, $item.Replacement, [StringComparison]::OrdinalIgnoreCase)
						#						$outFile = $outFile -creplace $item.Text, [Regex]::Escape($item.Replacement)
						#						$outFile = $outFile -creplace $item.Text, [Regex]::($item.Replacement)
						$outFile = [regex]::Replace(
							$outFile,
							[regex]::Escape($item.Text),
							$item.Replacement,
							[System.Text.RegularExpressions.RegexOptions]::IgnoreCase
						)
					}
				}
				
				# Check for the requirement to report Text Swaps by Line #
				if ($ReportRepLine) {
					$x = 1
					foreach ($Line in $outFile -split "`r?`n") {
						if ($Line -like "*$($item.Text)*") {
							$tmpResult = [rptLines]::new()
							$tmpResult.Text = $item.Text
							$tmpResult.Enabled = $true
							$tmpResult.Line = $x
							$outResult.Add($tmpResult)
							$x++
							$y++
						}
					}
					if ($x -eq 1) {
						$tmpResult = [rptLines]::new()
						$tmpResult.Text = $item.Text
						$tmpResult.Enabled = $true
						$tmpResult.Line = 0
						$outResult.Add($tmpResult)
					}
				}
				
				Write-Host "Replacement is found" -ForegroundColor Green
				Write-Host "  Text: $($item.Text)"
				
			} else {
				if ($ReportRepLine) {
					$tmpResult = [rptLines]::new()
					$tmpResult.Text = $item.Text
					$tmpResult.Enabled = $false
					$tmpResult.Line = 0
					$outResult.Add($tmpResult)
				}
				
				Write-Host "Replacement is not enabled" -ForegroundColor Cyan
				Write-Host "  Text: $($item.Text)"
			}
		}
		
		# Output the CSV report
		$dateStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
		$outTemp = Join-Path -Path $OutputPath -ChildPath "Translated-$($OutputName)_$($dateStamp).csv"
		if ($swapResults.Count -gt 0) {
			$swapResults | Export-Csv -Path $outTemp -NoTypeInformation -Encoding UTF8
			$buildScript = Join-Path $PSScriptRoot 'ConvertTo-TranslationReportHtml.ps1'
			if (Test-Path $buildScript) {
				$result = & $buildScript -Path $outTemp -Open -NoPause 2>&1
			} else {
				Write-Host "WARNING: Could not locate the HTML Output script 'ConvertTo-TranslationReportHtml.ps1'."
			}
		}
		
		# Create the actual output path
		$resolvedOutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
		$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
		
		# Write out the Replacement Lines file
		if ($ReportRepLine){
			if ($y -gt 0) {
				$outResult
				$tmpSrcPath = Join-Path $resolvedOutputPath "$($OutputName)-Lines_$dateStamp.csv"
#				[System.IO.File]::WriteAllText($tmpSrcPath, $outFile, $utf8NoBom)
				$outResult | Export-CSV -Path $tmpSrcPath -NoTypeInformation -Encoding UTF8 -Force

				Write-Host "Text-Swap Lines report saved to $($tmpSrcPath)" -ForegroundColor Green
			} else {
				Write-Host "No Text-Swap values were found in the instructions" -ForegroundColor Cyan
			}
		}
		
		# Write out the Final Instructions
		$tmpSrcPath = Join-Path $resolvedOutputPath "$($OutputName)_$dateStamp.md"
		
#		$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
#		[System.IO.File]::WriteAllText($tmpSrcPath, $outFile, $utf8NoBom)
		$outFile | Export-CSV -Path $tmpSrcPath -NoTypeInformation -Encoding UTF8 -Force
		
		Write-Host "Replaced instructions saved to: $tmpSrcPath" -ForegroundColor Green
	} else {
		throw "Could not find the Replacements File: $($ReplacementsFile)"
	}
} else {
	throw "Could not find the Instructions File: $($InstructionsFile)"
}

return $tmpSrcPath