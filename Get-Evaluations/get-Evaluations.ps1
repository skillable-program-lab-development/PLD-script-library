<#
	.SYNOPSIS
		The get-Evaluations.ps1 utility will search one or more Lab Series & Lab Profiles to retrieve the Evaluation ID used (if any)
	
	.DESCRIPTION
		Retrieve and report the evaluation ID for one or more Lab Profiles
	
	.PARAMETER LabSeriesList
		A comma separated list of Lab Series ID's
	
	.PARAMETER LabProfileList
		A comma separated list of Lab Profile ID's
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.243
		Created on:   	02/27/2025 2:24 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	get-Evaluations
		===========================================================================
#>
param
(
	[Parameter(ParameterSetName = 'Series',
			   Mandatory = $true)]
	[string]$LabSeriesList,
	[Parameter(ParameterSetName = 'Profiles',
			   Mandatory = $true)]
	[string]$LabProfileList
)

class EvalResult {
	[string]$LabSeries
	[string]$LabProfile
	[int]$evalId
	
	conResult([string]$LabSeries, [string]$LabProfile, [int]$evalId) {
		$this.LabSeries = $LabSeries
		$this.LabProfile = $LabProfile
		$this.evalId = $evalId
	}
}

$curId = 0

function Write-Note {
	[CmdletBinding()]
	param
	(
		$note,
		[switch]$hideTimeStamp
	)
	
	$timeStamp = Get-Date -Format "MM/dd/yy_HH:mm:ss"
	
	if ($hideTimeStamp) {
		Write-Output "$($note)"
	} else {
		Write-Output "$($timeStamp):  $($note)"
	}
	
}

function Invoke-WithRetry {
	param
	(
		[scriptblock]$Command,
		[int]$Retries = 1
	)
	
	$attempt = 0
	while ($true) {
		try {
			& $Command
			return # success, exit function
		} catch {
			$attempt++
			if ($attempt -le $Retries) {
				Write-Note -note "    Command failed on lab $($curId). Retrying attempt $attempt of $Retries..."
				Write-Note -note "    Command: $($Command)"
				Write-Warning "Command failed on lab $($curId). Retrying attempt $attempt of $Retries..."
				Write-Warning "  Command: $($Command)"
				Start-Sleep -Seconds 1 # optional backoff
			} else {
				throw # re-raise the error after retries exhausted
			}
		}
	}
}

function Process-LabProfile {
	[CmdletBinding()]
	param
	(
		$seriesName,
		$labId
	)
	
	# Set the indicator variables
	$cont = $false
	
	# Get the Lab Profile Details
	try {
		$labProfile = Invoke-WithRetry {
			Get-LODLabProfile -ID $labId
		} 
		$labName = $labProfile.Name
		if ($seriesName.Length -eq 0) {
			$seriesName = $labProfile.SeriesId
		}
		Write-Note -note "Processing Profile: ($($labProfile.Number)) $($labName)"
		$cont = $true
	} catch {
		Write-Note -note "ERROR on Get-LODLabProfile -ID $($labId)"
		Write-Note -note "ERROR: $($_.Exception.Message)"
	}
	
	if ($cont) {
		# Add the info to the output array
		$tmpResult = [EvalResult]::new()
		$tmpResult.LabSeries = $seriesName
		$tmpResult.LabProfile = "($($labId)): $($labName)"
		$tmpResult.EvalId = $LabProfile.EvaluationId
		
		$outResult.add($tmpResult)
		
	}
}

# =========================================
# M A I N  L I N E
# =========================================

# Set up the output list
$outResult = [System.Collections.Generic.List[EvalResult]]::new()

# Log in to Skillable Studio
try {
	Connect-LabOnDemand -ERRORAction 'Continue'
} catch {
	Write-Note -note "FAILED TO CONNECT"
	Write-Note -note "  Details: $($_.Exception.Message)"
}

# If a list of Lab Series' is provided then find the Lab Profiles for each and process them
if ($LabSeriesList.Length -gt 0) {
	Write-Note -note "START - Processing Lab Series & Profiles"
	Write-Note -note "###################################################"
	Write-Note -note "# Lab Series List: $($LabSeriesList)"
	Write-Note -note "###################################################"
	
	# Build the Series List
	$arrLabSeries = $LabSeriesList -split ","
	$x = 1
	foreach ($LabSeries in $arrLabSeries) {
		# Get the Lab series details
		if ($LabSeries -match '\d+') {
			$tmpSeries = $matches[0]
		} else {
			$tmpSeries = $LabSeries
		}
		try {
			Write-Note -note "Getting details for Lab Series ID: $($tmpSeries)"
			$curId = $tmpSeries
			$curSeries = Invoke-WithRetry {
				Get-LODLabSeries -ID $tmpSeries
			}
			Write-Note -note "Current Series: $($tmpSeries) $($curSeries.Name)"
			Write-Note -note "  SUCCESS: Retrieved Lab Series Details for series: ($($LabSeries)) $($curSeries.Name)"
			
			# Get the list of Lab Profiles 
			if ($curSeries.Enabled -eq "True") {
				try {
					Write-Note -note "Retrieving list of lab profiles on Lab Series: $($LabSeries) $($curSeries.Name)"
					$LabList = Invoke-WithRetry {
						Search-LODLabProfile -LabSeriesId $curSeries.Id
					}
					Write-Note -note "  SUCCESS: Retrieved and Examined Lab Profiles list for series ($($LabList.Count)): ($($LabSeries)) $($curSeries.Name)"
				} catch {
					Write-Note -note "Error on Search-LODLabProfile -LabSeriesId $($curSeries.Id)"
					Write-Note -note "Error: $($_.Exception.Message)"
				}
				try {
					# Process each Lab Profile
					foreach ($Lab in $LabList) {
						$curId = $Lab.Id
						Process-LabProfile -seriesName "($($LabSeries)) $($curSeries.Name)" -labId $Lab.Id
					}
				} catch {
					Write-Note -note "Error on Process-LabProfile -LabSeriesId $($curSeries.Id)"
					Write-Note -note "Error: $($_.Exception.Message)"
				}
				
			} else {
				Write-Note -note "Current Series is Disabled: $($tmpSeries) $($curSeries.Name)"
			}
		} catch {
			Write-Note -note "Could not retrieve the details for the Current Series: $($tmpSeries)"
			Write-Note -note "Error: $($_.Exception.Message)"
		}
	}
	
	# End processing
	Write-Note -note "END - Processing Lab Series & Profiles"
} else {
	# Otherwise process all the supplied Lab Profiles
	Write-Note -note "START - Processing Lab Profiles"
	Write-Note -note "###################################################"
	Write-Note -note "# Lab Profile List: $($LabProfileList)"
	Write-Note -note "###################################################"
	
	# Build the Profile List
	$arrLabProfiles = $LabProfileList -split ","
	
	foreach ($Id in $arrLabProfiles) {
		$curId = $Id
		Process-LabProfile -labId $Id
	}
	
	# End processing
	Write-Note -note "END - Processing Lab Profiles"
}

# Create the CSV report
$timestamp = Get-Date -Format "yyyMMdd_HHmmss"
$rptName = "Eval_Report_$($timestamp).csv"
#"Lab Series,Lab Profile,Eval ID" | Set-Content -Path $rptName -Encoding UTF8

# Add the data to the report
if ($outResult.Count -gt 0) {
    # Append the data
	$outResult | Export-Csv -Path $rptName -NoTypeInformation -Encoding UTF8 -Force
} else {
	# Create the Report
	Out-File -FilePath $rptName -Append "NO DATA FOUND" -Encoding UTF8 -Force
}
