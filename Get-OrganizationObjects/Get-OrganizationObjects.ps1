<#
	.SYNOPSIS
		A brief description of the  file.
	
	.DESCRIPTION
		Retrive the Lab Profiles that belong to a specific Organization
	
	.PARAMETER OrganizationList
		A description of the OrganizationList parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2025 v5.9.261
		Created on:   	4/17/2026 11:22 AM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	Get-OrganizationObjects.ps1
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true)]
	[string]$OrganizationList
)

$curId = 0
#$lstLabProfiles = New-Object System.Collections.Generic.List[object]
$cntOrgs = 0
$script:cntLines = 0
$script:cntFound = 0

# Define the CSV report and Log file
$timestamp = Get-Date -Format "yyyMMdd_HHmmss"
$rptName = "OrgObjects_Report_$($timestamp).csv"
$logName = "OrgObjects_Report_$($timestamp).log"

class OrgResult {
	[int]$OrgId
	[string]$OrgName
	[int]$LabSeriesId
	[string]$LabSeriesName
	[int]$LabProfileId
	[string]$LabProfileNumber
	[string]$LabProfileName
	[int]$SubId
	[string]$SubName
	
	conResult([int]$OrgId, [string]$OrgName, [int]$LabSeriesId, [string]$LabSeriesName, [int]$LabProfileId, [string]$LabProfileNumber, [string]$LabProfileName, [int]$SubId, [int]$SubName) {
		$this.OrgId = $OrgId
		$this.OrgName = $OrgName
		$this.LabSeriesId = $LabSeriesId
		$this.LabSeriesName = $LabSeriesName
		$this.LabProfileId = $LabProfileId
		$this.LabProfileNumber = $LabProfileNumber
		$this.LabProfileName = $LabProfileName
		$this.SubId = $SubId
		$this.SubName = $SubName
	}
}
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
		Add-Content -Path $logName -Value "$($note)"
	} else {
		Write-Output "$($timeStamp):  $($note)"
		Add-Content -Path $logName -Value "$($timeStamp):  $($note)"
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


function Convert-ToIntArray {
	param (
		[Parameter(Mandatory)]
		[string]$Value
	)
	
	$Value = $Value.Trim()
	
	if ($Value -notmatch '^\d+([,\s\r\n]+\d+)*$') {
		throw "Invalid number list format"
	}
	
	return $Value -split '[,\s\r\n]+' | ForEach-Object {
		[int]$_
	} | Sort-Object -Unique
}

function Process-Organization {
	[CmdletBinding()]
	param
	(
		$OrgId
	)
	
	# Set the indicator variables
	$cont = $false
	
	# Get the Lab Profile Details
	try {
		# Currently "ByOrganization" Only works on Wayne's laptop
#		$orgProfile = Invoke-WithRetry {
#			Search-LODLabProfile -OrganizationId $OrgId
#		}
		$orgProfile = Search-LODLabProfile -OrganizationId $OrgId
		Write-Note -note "Processing Org Profile: $($OrgId)"
		Write-Note -note "  Lab Profiles in Org: $($orgProfile.Count)"
		Write-Note -note "================================="
		$cont = $true
	} catch {
		Write-Note -note "  ERROR on Search-LODLabProfile -ByOrganization $($OrgId)"
		Write-Note -note "  ERROR: $($_.Exception.Message)"
	}
	
	if ($cont) {
		# Cycle through all of the Lab Profiles for this Organization
		foreach ($lab in $orgProfile) {
			$script:cntLines++
			Write-Note -note "  Line: $($script:cntLines)"
			
			# Initialize the fields
			# Add the info to the output array
			$tmpResult = [OrgResult]::new()
			$tmpResult.OrgId = 0
			$tmpResult.OrgName = ""
			$tmpResult.LabSeriesId = 0
			$tmpResult.LabSeriesName = ""
			$tmpResult.LabProfileId = 0
			$tmpResult.LabProfileNumber = ""
			$tmpResult.LabProfileName = ""
			$tmpResult.SubId = 0
			$tmpResult.SubName = ""
			
			# Only process Labs that are actually in the Organization and not in a parent or child org
			if ($lab.OrganizationId -eq $OrgId) {
				# Retrieve the Lab Profile Information
				Write-Note -note "  Retrieving Lab Profile Details for Lab ID: $($lab.Id)"
				$labProfile = Invoke-WithRetry {
					# Currently "ByOrganization" Only works on Wayne's laptop
					Get-LODLabProfile -ID $lab.Id
				}
				Write-Note -note "    SUCCESS"
				# Retrieve the Lab Series Information
				if ($labProfile.SeriesId){
					Write-Note -note "  Retrieving Lab Series Details for Lab Series: $($labProfile.SeriesId)"
					$labSeries = Invoke-WithRetry {
						# Currently "ByOrganization" Only works on Wayne's laptop
						Get-LODLabSeries -ID $labProfile.SeriesId
					}
					Write-Note -note "    SUCCESS"
#					$SeriesId = $labSeries.Id
#					$SeriesName = $labSeries.Name
				} else {
#					$SeriesId = 0
#					$SeriesName = ""
				}
				Write-Note -note "  Lab Profile Output:"
				Write-Note -note "    Requested Organization:   ($($OrgId))"
				Write-Note -note "    Lab Profile Organization: ($($lab.OrganizationId)) $($lab.OrganizationName)"
				
				# Add the info to the output array
#			     $tmpResult = [OrgResult]::new()
				$tmpResult.OrgId = $lab.OrganizationId
				$tmpResult.OrgName = $lab.OrganizationName
				$tmpResult.LabSeriesId = $LabSeries.Id
				$tmpResult.LabSeriesName = $LabSeries.Name
				$tmpResult.LabProfileId = $lab.Id
				$tmpResult.LabProfileNumber = $lab.Number
				$tmpResult.LabProfileName = $lab.Name
				$tmpResult.SubId = $labProfile.CloudSubscriptionPoolId
				$tmpResult.SubName = $labProfile.CloudSubscriptionPoolName
				
				$outResult.add($tmpResult)
				$script:cntFound++
				Write-Note -note "  Lab Profile ($($lab.Id)): Organization ($($lab.OrganizationId)) added to the report"
			} else {
				Write-Note -note "  NOTE: Lab Profile not in required Organization"
				Write-Note -note "    Requested Organization:   ($($OrgId))"
				Write-Note -note "    Lab Profile Organization: ($($lab.OrganizationId)) $($lab.OrganizationName)"
				Write-Note -note "  Lab Profile ($($lab.Id)): Organization ($($lab.OrganizationId)) NOT added to the report"
			}
		}
	}
}


# =========================================
# M A I N  L I N E
# =========================================

# Set up the output list
$outResult = [System.Collections.Generic.List[OrgResult]]::new()

# Create the Log File
New-Item -Path $logName -ItemType File -Force | Out-Null

# Build the Organization List
#$arrOrgs = $OrganizationList -split ","

# NOTE: If using Excel convert the id column into a comma separated list using
# =TEXTJOIN(",",TRUE,A2:A393)

# Convert the input list into an actual array if it is simply a list
$arrOrgs = Convert-ToIntArray -Value $OrganizationList

# Log in to Skillable Studio
try {
	Write-Note -note "Attempting to connect to Skillable Studio"
	Connect-LabOnDemand -ERRORAction 'Continue'
} catch {
	Write-Note -note "FAILED TO CONNECT"
	Write-Note -note "  Details: $($_.Exception.Message)"
	throw "Failed to connect to Skillable Studio. Details: $($_.Exception.Message)"
}

# Process all the supplied Organizations
Write-Note -note "START - Processing Organizations"
Write-Note -note "###################################################"
Write-Note -note "# Organization List: $($arrOrgs)"
Write-Note -note "# Deduped Org Count: $($arrOrgs.Count)"
Write-Note -note "###################################################"

foreach ($Id in $arrOrgs) {
	$curId = $Id
	$cntOrgs++
	Process-Organization -OrgId $Id
}

# End processing
Write-Note -note "END - Processing Lab Profiles"
Write-Note -note "Total Orgs Processed:  $($cntOrgs)"
Write-Note -note "Total Lines Processed: $($script:cntLines)"

# Add the data to the report
if ($outResult.Count -gt 0) {
	# Append the data
	$outResult | Export-Csv -Path $rptName -NoTypeInformation -Encoding UTF8 -Force
} else {
	# Create the Report
	Out-File -FilePath $rptName -Append "NO DATA FOUND" -Encoding UTF8 -Force
}

