<#
	.SYNOPSIS
		Export Lab Instance details to CSV for a list of Lab Profile IDs OR Lab Series IDs.
	
	.DESCRIPTION
		- If -LabProfileIdsCsv is provided, uses that list directly.
		- If -LabSeriesIdsCsv is provided, calls Search-LODLabProfile.ps1 for each series to discover Lab Profile IDs.
		- Then calls Search-LODLabInstance.ps1 for each Lab Profile ID and exports .Results rows to CSV.
		- NOTE: Created by Copilot AI. Validated by Humans. Using AI did not reduce development time for this script.
	
	.PARAMETER LabProfileList
		Comma-separated list of Lab Profile IDs, e.g. "211388,211389"
	
	.PARAMETER LabSeriesList
		Comma-separated list of Lab Series IDs, e.g. "39687,39688"
	
	.PARAMETER OutCsv
		Output CSV file path.
	
	.PARAMETER IncludeProfileMetadata
		If set, adds Lab Profile fields (ProfileName, Enabled, OrganizationId, OrganizationName, Platform) onto each Lab Instance row.
	
	.PARAMETER LaunchType
		A description of the LaunchType parameter.
	
	.EXAMPLE
		.\Export-LODLabInstances.ps1 -LabProfileIdsCsv "211388,211389" -OutCsv ".\instances.csv"
	
	.EXAMPLE
		.\Export-LODLabInstances.ps1 -LabSeriesIdsCsv "39687" -OutCsv ".\instances.csv" -IncludeProfileMetadata
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2025 v5.9.261
		Created on:   	3/15/2026 4:38 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	Get-InstanceList
		===========================================================================
#>
[CmdletBinding(DefaultParameterSetName = 'ByProfiles')]
param
(
	[Parameter(ParameterSetName = 'ByProfiles',
			   Mandatory = $true)]
	[string]$LabProfileList,
	[Parameter(ParameterSetName = 'BySeries',
			   Mandatory = $true)]
	[string]$LabSeriesList,
	[Parameter(Mandatory = $false)]
	[ValidateNotNullOrEmpty()]
	[string]$OutCsv = (Join-Path -Path (Get-Location) -ChildPath ("LabInstanceDetails_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),
	[Parameter(Mandatory = $false)]
	[switch]$IncludeProfileMetadata,
	[ValidateSet('All', 'Last', 'None')]
	[string]$LaunchType = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Parse-IdCsv {
	param (
		[Parameter(Mandatory)]
		[string]$Csv
	)
	
	$ids = $Csv -split ','
	if (-not $ids -or $ids.Count -eq 0) {
		throw "No valid IDs were found in the provided CSV string."
	}
	
	# Deduplicate while preserving order
	$seen = New-Object 'System.Collections.Generic.HashSet[int]'
	$orderedUnique = New-Object 'System.Collections.Generic.List[int]'
	foreach ($id in $ids) {
		if ($seen.Add($id)) {
			[void]$orderedUnique.Add($id)
		}
	}
	
	return $orderedUnique
}

function Invoke-LabProfileSearch {
	param (
		[Parameter(Mandatory)]
		[int]$LabSeriesId
	)
	
	# Call the script and return its output
	Search-LODLabProfile -LabSeriesId $LabSeriesId
}

function Invoke-LabInstanceSearch {
	param (
		[Parameter(Mandatory)]
		[int]$LabProfileId
	)
	
	# Call the script and return its output
	Search-LODLabInstance -LabProfileId $LabProfileId
}

# --- Validate script paths ---
#Ensure-ScriptExists -Path $LabInstanceSearchScript
#if ($PSCmdlet.ParameterSetName -eq 'BySeries') {
#	Ensure-ScriptExists -Path $LabProfileSearchScript
#}

# --- Build Lab Profile ID list ---
$labProfileIds = New-Object 'System.Collections.Generic.List[int]'
$profileById = @{
} # optional enrichment: Id -> profile object

try {
	Connect-LabOnDemand -ERRORAction 'Continue'
} catch {
	Write-Host "FAILED TO CONNECT"
	Write-Host "  Details: $($_.Exception.Message)"
}


if ($PSCmdlet.ParameterSetName -eq 'ByProfiles') {
	$labProfileIds = Parse-IdCsv -Csv $LabProfileList
} else {
	$seriesIds = Parse-IdCsv -Csv $LabSeriesList
	
	Write-Verbose ("Discovering Lab Profiles from Series IDs: {0}" -f ($seriesIds -join ', '))
	
	$seenProfiles = New-Object 'System.Collections.Generic.HashSet[int]'
	
	foreach ($sid in $seriesIds) {
		Write-Host "Retrieving Lab Profiles for SeriesId $sid ..." -ForegroundColor Cyan
		
		$profiles = Invoke-LabProfileSearch -LabSeriesId $sid
		
		if (-not $profiles) {
			Write-Warning "No profiles returned for SeriesId $sid."
			continue
		}
		
		foreach ($p in @($profiles)) {
			if ($null -eq $p.Id) {
				continue
			}
			$prid = [int]$p.Id
			
			if ($seenProfiles.Add($prid)) {
				[void]$labProfileIds.Add($prid)
			}
			
			if ($IncludeProfileMetadata) {
				# Keep the latest object seen for that profile id
				$profileById[$prid] = $p
			}
		}
	}
	
	if ($labProfileIds.Count -eq 0) {
		throw "No Lab Profile IDs were discovered from the provided Series IDs."
	}
}

Write-Host ("Lab Profiles to process: {0}" -f ($labProfileIds -join ', ')) -ForegroundColor Green
Write-Host ("Output CSV: {0}" -f $OutCsv) -ForegroundColor Green

# --- Export Lab Instance Results ---
# We'll stream rows to CSV: first write includes headers, subsequent writes append without headers.
$wroteHeader = $false

# Ensure output directory exists
$outDir = Split-Path -Path $OutCsv -Parent
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
	New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Remove existing file to avoid mixing schemas unless user wants it appended (not requested)
if (Test-Path -LiteralPath $OutCsv) {
	Remove-Item -LiteralPath $OutCsv -Force
}

foreach ($prid in $labProfileIds) {
	Write-Host "Retrieving Lab Instances for LabProfileId $prid ..." -ForegroundColor Cyan
	
	$resp = $null
	try {
		$resp = Invoke-LabInstanceSearch -LabProfileId $prid
	} catch {
		Write-Warning "Failed to retrieve instances for LabProfileId $prid. Error: $($_.Exception.Message)"
		continue
	}
	
	if (-not $resp) {
		Write-Warning "No response returned for LabProfileId $prid."
		continue
	}
	
	# Basic shape: Success, TotalCount, TotalPages, Results
	if ($resp.PSObject.Properties.Name -contains 'Success' -and -not $resp.Success) {
		Write-Warning "Search returned Success=False for LabProfileId $prid."
		continue
	}
	
#	$rows = $null
#	if ($resp.PSObject.Properties.Name -contains 'Results') {
#		$rows = $resp.Results | Sort-Object -Property StartTime -Descending
#	}
#	
#	if (-not $rows) {
#		Write-Host "No Lab Instances found for LabProfileId $prid." -ForegroundColor DarkYellow
#		continue
#	}
	
	####################################
	# Addition of NO Lab Instance Logic - Start
	####################################
	
	
	# Determine count reliably (prefer API TotalCount if present)
	$count = if ($resp.PSObject.Properties.Name -contains 'TotalCount') {
		[int]$resp.TotalCount
	} else {
		if ($resp.PSObject.Properties.Name -contains 'Results' -and $resp.Results) {
			@($resp.Results).Count
		} else {
			0
		}
	}
	
	# If LaunchType is None, we ONLY "report" profiles that have 0 launches
	if ($LaunchType -eq 'None') {
		
		if ($count -gt 0) {
			Write-Host "Skipping LabProfileId $prid because it has $count launch(es)." -ForegroundColor DarkGray
			continue
		}
		
		# Build a single output row indicating zero launches
		$zeroRow = [pscustomobject]@{
			LabProfileId = $prid
			LaunchCount  = 0
		}
		
		if ($IncludeProfileMetadata) {
			$p = $null
			if ($profileById.ContainsKey($prid)) {
				$p = $profileById[$prid]
			}
			
			# Add the same metadata columns you use elsewhere
			$zeroRow | Add-Member -NotePropertyName 'LabProfileName' -NotePropertyValue ($(if ($p) {
						$p.Name
					} else {
						$null
					})) -Force
			$zeroRow | Add-Member -NotePropertyName 'LabProfileEnabled' -NotePropertyValue ($(if ($p) {
						$p.Enabled
					} else {
						$null
					})) -Force
			$zeroRow | Add-Member -NotePropertyName 'LabProfileOrgId' -NotePropertyValue ($(if ($p) {
						$p.OrganizationId
					} else {
						$null
					})) -Force
			$zeroRow | Add-Member -NotePropertyName 'LabProfileOrgName' -NotePropertyValue ($(if ($p) {
						$p.OrganizationName
					} else {
						$null
					})) -Force
			$zeroRow | Add-Member -NotePropertyName 'LabProfilePlatform' -NotePropertyValue ($(if ($p) {
						$p.Platform
					} else {
						$null
					})) -Force
		}
		
		# Export the "0 launches" row
		if (-not $wroteHeader) {
			$zeroRow | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
			$wroteHeader = $true
		} else {
			$zeroRow | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8 -Append
		}
		
		Write-Host "Reported LabProfileId $prid with 0 launches." -ForegroundColor Green
		continue
	}
	
	# Normal (All/Last) behavior continues here
	$rows = $null
	if ($resp.PSObject.Properties.Name -contains 'Results') {
		$rows = $resp.Results | Sort-Object -Property StartTime -Descending
	}
	
	if (-not $rows) {
		Write-Host "No Lab Instances found for LabProfileId $prid." -ForegroundColor DarkYellow
		continue
	}
	
	####################################
	# Addition of NO Lab Instance Logic - End
	####################################
	
	foreach ($r in @($rows)) {
		if (-not $r) {
			continue
		}
		
		if ($IncludeProfileMetadata) {
			$p = $null
			if ($profileById.ContainsKey($prid)) {
				$p = $profileById[$prid]
			}
			
			# Add profile metadata (as note properties) if not already present
			# Note: Add-Member modifies the object in-place, so we clone to avoid side effects.
			$r2 = $r.PSObject.Copy()
			
			$profileName = if ($p) {
				$p.Name
			} else {
				$null
			}
			$enabled = if ($p) {
				$p.Enabled
			} else {
				$null
			}
			$orgId = if ($p) {
				$p.OrganizationId
			} else {
				$null
			}
			$orgName = if ($p) {
				$p.OrganizationName
			} else {
				$null
			}
			$platform = if ($p) {
				$p.Platform
			} else {
				$null
			}
			
			$r2 | Add-Member -NotePropertyName 'LabProfileName' -NotePropertyValue $profileName -Force
			$r2 | Add-Member -NotePropertyName 'LabProfileEnabled' -NotePropertyValue $enabled -Force
			$r2 | Add-Member -NotePropertyName 'LabProfileOrgId' -NotePropertyValue $orgId -Force
			$r2 | Add-Member -NotePropertyName 'LabProfileOrgName' -NotePropertyValue $orgName -Force
			$r2 | Add-Member -NotePropertyName 'LabProfilePlatform' -NotePropertyValue $platform -Force
			
			$r = $r2
		}
		
		if (-not $wroteHeader) {
			$r | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
			$wroteHeader = $true
		} else {
			$r | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8 -Append
		}
		if ($LaunchType.ToLower() -eq "last") {
			break
		}
	}
#	$count = if ($resp.PSObject.Properties.Name -contains 'TotalCount') {
#		$resp.TotalCount
#	} else {
#		(@($rows)).Count
#	}
	Write-Host "Exported $count instance row(s) for LabProfileId $prid." -ForegroundColor Green
}

if (-not $wroteHeader) {
	Write-Warning "No rows were exported. CSV was not created."
} else {
	Write-Host "Done. Lab Instance details exported to: $OutCsv" -ForegroundColor Green
}