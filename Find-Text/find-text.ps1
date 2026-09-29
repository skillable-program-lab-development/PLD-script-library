<#
	.SYNOPSIS
		The find-text.ps1 utility will search one or more Lab Series & Lab Profiles to determine where and how often one or more terms appear and report this result
	
	.DESCRIPTION
		Examine Lab Profiles and determine if the input text if found in the instructions, GH, LCA scripts, Activity scripts, or ACP
	
	.PARAMETER LabSeriesList
		A comma separated list of Lab Series ID's
	
	.PARAMETER LabProfileList
		A comma separated list of Lab Profile ID's
	
	.PARAMETER FindList
		A comma separated list of terms to be found in the Lab Profile and associated objects like an ACP. To require multiple terms to exist at the same time separate the specific terms with double ampersands (&&).
	
	.PARAMETER FindType
		What kind of match is required
	
	.PARAMETER CaseType
		What Case Type evaluation should be performed
	
	.PARAMETER checkACPs
		A description of the checkACPs parameter.
	
	.PARAMETER checkLCAs
		A description of the checkLCAs parameter.
	
	.PARAMETER checkActivities
		A description of the checkActivities parameter.
	
	.PARAMETER checkInstructionsAndSwaps
		A description of the checkInstructionsAndSwaps parameter.
	
	.PARAMETER DevComplete
		A description of the DevComplete parameter.
	
	.PARAMETER checkACP
		A description of the checkACP parameter.
	
	.PARAMETER checkLCA
		A description of the checkLCA parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.243
		Created on:   	12/09/2025 2:24 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	find-text
		===========================================================================
#>
param
(
	[Parameter(ParameterSetName = 'Series',
			   Mandatory = $true)]
	[string]$LabSeriesList,
	[Parameter(ParameterSetName = 'Profiles',
			   Mandatory = $true)]
	[string]$LabProfileList,
	[Parameter(ParameterSetName = 'Profiles',
			   Mandatory = $true)]
	[Parameter(ParameterSetName = 'Series',
			   Mandatory = $true)]
	[string]$FindList,
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[ValidateSet('Exact', 'exact', 'EXACT', 'StartsWith', 'startswith', 'Startswith', 'STARTSWITH', 'EndsWith', 'endswith', 'Endswith', 'ENDSWITH', 'Contains', 'contains', 'CONTAINS', IgnoreCase = $true)]
	[string]$FindType = 'Contains',
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[ValidateSet('None', 'none', 'NONE', 'Lower', 'lower', 'LOWER', 'Upper', 'upper', 'UPPER', 'Camel', 'camel', 'CAMEL', 'Any', 'any', 'ANY', IgnoreCase = $true)]
	[string]$CaseType = 'None',
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[switch]$DevComplete,
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[switch]$checkACPs,
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[switch]$checkLCAs,
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[switch]$checkActivities,
	[Parameter(ParameterSetName = 'Profiles')]
	[Parameter(ParameterSetName = 'Series')]
	[switch]$checkInstructionsAndSwaps
)

class FindResult {
#	[string]$LabSeries
#	[int]$LabProfile
#	[string]$Location
#	[string]$Term
#	[int]$Found
	[string]$LabSeries
	[string]$LabSeriesName
	[int]$LabProfile
	[string]$LabProfileName
	[string]$Location
	[string]$Term
	[int]$Found
}

$outResult = [System.Collections.Generic.List[FindResult]]::new()
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

$seriesNameCache = @{
}

Function Get-SeriesName {
	Param ($seriesId)
	$key = [string]$seriesId
	If ([string]::IsNullOrEmpty($key)) {
		Return ''
	}
	If (-not $script:seriesNameCache.ContainsKey($key)) {
		Try {
			$s = Invoke-WithRetry {
				Get-LODLabSeries -ID $key
			}
			$script:seriesNameCache[$key] = $s.Name
		} Catch {
			Write-Note -note "  WARNING: Could not resolve Lab Series name for ID $($key)"
			$script:seriesNameCache[$key] = '(lookup failed)'
		}
	}
	Return $script:seriesNameCache[$key]
}

Function Invoke-WithRetry {
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

function Get-TermFrequency {
	param (
		[string]$Text,
		$Terms,
		[string]$MatchType = "Contains",
		[string]$CaseMode = "None"
	)
	
	# Normalize text case as requested
	switch ($CaseMode) {
		"Lower" {
			$Text = $Text.ToLower()
		}
		"Upper" {
			$Text = $Text.ToUpper()
		}
		"Camel" {
			# Convert to Title Case using current culture
			$Text = (Get-Culture).TextInfo.ToTitleCase($Text.ToLower())
		}
		default {
		} # None = no change
	}
	
	foreach ($term in $Terms) {
		# Apply same case normalization to search terms
		$normalizedTerm = switch ($CaseMode) {
			"Lower" {
				$term.ToLower()
			}
			"Upper" {
				$term.ToUpper()
			}
			"Camel" {
				(Get-Culture).TextInfo.ToTitleCase($term.ToLower())
			}
			default {
				$term
			}
		}
		
		# Count matches
		if ($normalizedTerm -like "*&&*") {
			$pat = $normalizedTerm.ToString() -split "&&"
			$cnt = 0
			$count = 1
			$fnd = $true
			foreach ($item in $pat) {
				$itm = ([string]$item).Trim()
				if ($CaseMode -eq "Any") {
					$cnt += ([regex]::Matches($Text.ToLower(), ([string]$itm).ToLower())).Count
				} else {
					$cnt += ([regex]::Matches($Text, $itm)).Count
				}
#				if ($cnt -eq 0) {
#					$fnd = $false
#					$count = 0
#					break
#				}
				$termCnt = If ($CaseMode -eq "Any") {
					([regex]::Matches($Text.ToLower(), $itm.ToLower())).Count
				} Else {
					([regex]::Matches($Text, $itm)).Count
				}
				If ($termCnt -eq 0) {
					$count = 0; Break
				}
			}
		} Else {
			# Build regex based on MatchType
			$escaped = [regex]::Escape($normalizedTerm)
			$escaped = ([regex]::Escape($normalizedTerm)).Trim()
			
			#			$escaped.Trim()
			$pattern = Switch ($MatchType) {
				"Exact"      {
					"^\b$escaped\b$"
				} # full exact match
				"StartsWith" {
					"\b$escaped"
				} # term at start of a word
				"EndsWith"   {
					"$escaped\b"
				} # term at end of a word
				"Contains"   {
					$escaped
				} # anywhere in the text
			}
			
			If ($CaseMode -eq "Any") {
				$count = ([regex]::Matches($Text.ToLower(), ([string]$pattern).ToLower())).Count
			} Else {
				$count = ([regex]::Matches($Text, $pattern)).Count
			}
		}
		#		$count = ([regex]::Matches($Text, [regex]::Escape($term), 'IgnoreCase')).Count
		
		# Return structured row
		[pscustomobject]@{
			Term	   = $term
			Normalized = $normalizedTerm
			MatchType  = $MatchType
			CaseMode   = $CaseMode
			Found	   = $count
		}
	}
}

Function Add-FindResult ($Location, $Row) {
	$tmpResult.Add([FindResult]@{
			LabSeries	   = $seriesId
			LabSeriesName  = $seriesName
			LabProfile	   = $labId
			LabProfileName = $labName
			Location	   = $Location
			Term		   = $Row.Term
			Found		   = $Row.Found
		})
}

Function Process-LabProfile {
	[CmdletBinding()]
	param
	(
		$seriesId,
		$seriesName,
		$labId
	)
	
	# Create the FindList Object
	$lstTerms = $FindList -split ","
	
	# Set the indicator variables
	$inhParent = "N"
	$inhEnvironment = $false
	$inhContent = $false
	$fndExternal = $false
	$cont = $false
	
	# Dev Status Lookup Table
	$labStatus = @{
		1 = "In Development"
		5 = "Awaiting Verification"
		7 = "In Verification"
		8 = "Verification Failed"
		10 = "Complete"
	}
	
	# Get the Lab Profile Details
	try {
		$labProfile = Invoke-WithRetry {
			Get-LODLabProfile -ID $labId
		} 
		$labName = $labProfile.Name
#		if ($seriesName.Length -eq 0) {
#			$seriesName = $labProfile.SeriesId
#		}
		If ([string]::IsNullOrEmpty($seriesId)) {
			$seriesId = $labProfile.SeriesId
		}
		If ([string]::IsNullOrEmpty($seriesName)) {
			$seriesName = Get-SeriesName $seriesId
		}
		Write-Note -note "Processing Profile: ($($labProfile.Number)) $($labName)"
		$cont = $true
	} catch {
		Write-Note -note "ERROR on Get-LODLabProfile -ID $($labId)"
		Write-Note -note "ERROR: $($_.Exception.Message)"
	}
	
	if ($cont) {
		# If the Lab Profile is enabled increment that counter
		if ($labProfile.Enabled) {
			# Record the Inheritance Properties
			$inhParent = if ([string]::IsNullOrEmpty($labProfile.ParentId)) {
				""
			} else {
				$labProfile.ParentId
			}
			$inhEnvironment = if ($labProfile.InheritEnvironment -eq "True") {
				$true
			} else {
				$false
			}
			$inhContent = if ($labProfile.InheritContent -eq "True") {
				$true
			} else {
				$false
			}
			$devStatus = $labStatus[$labProfile.CurrentDevelopmentStatusId]
			
			# Check to make sure the Lab Profile is an Azure Cloud profile
#			if ($labProfile.CloudPlatform -eq 10) {
#				$isAzure = "Y"
#				$lodsContent = "N"
#				# Cloud Platforms
#				# 10 - Azure
#				# 11 - AWS
#				# 12 - GCP
#				# 13 - Unknown
			
			# Only examine Lab Profiles that are in a "Complete" Dev Status
			# when the DevComplete parameter is specified
			if (($DevComplete -and ($devStatus -eq "Complete")) -or (-not $DevComplete)) {
				# Prepare the output Result value
				$tmpResult = [System.Collections.Generic.List[FindResult]]::new()
				
				if ($checkACPs){
					###########################################
					# FIND TERMS - ACPs
					###########################################
					# Check to make sure the Lab Profile is an Azure Cloud profile
					if ($labProfile.CloudPlatform -eq 10) {
						foreach ($acp in $labProfile.CloudSubscriptionInstancePoliciesJson) {
							$acpRecord = Invoke-WithRetry {
								Get-LODAccessControlPolicy -ID $acp.Id
							}
							$tmpInst = Get-TermFrequency -Text $acpRecord.PolicyJson -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
							foreach ($row in $tmpInst) {
								#							foreach ($Term in $lstTerms) {
								if ($row.Found -gt 0) {
#									$tmpResult.Add([FindResult]@{
#											LabSeries  = $seriesName
#											LabProfile = $labId
#											Location   = "ACP ($($ACP.Id) - $($ACP.Name))"
#											Term	   = $row.Term
#											Found	   = $row.Found
#										}
#									)
									Add-FindResult -Location "ACP ($($ACP.Id) - $($ACP.Name))" -Row $row
								}
								Write-Note -note "  Term:  $($row.Term)"
								Write-Note -note "  Loc:   ACP ($($ACP.Id) - $($ACP.Name))"
								Write-Note -note "  Found: $($row.Found) times"
								#							}
							}
						}
					}
				}
				
				if ($checkLCAs) {
				###########################################
				# FIND TERMS - Life Cycle Activities (LCAs)
				###########################################
				# LCAs
				# Only examine non-inherited LCAs
					if (-not $labProfile.InheritLifeCycleActions) {
						# Update the output with the counts from the LCAs
						foreach ($LCA in $labProfile.LifeCycleActionsJson) {
							# only examine scripts
							if ($LCA.ActionType -in 30, 40, 50) {
								$tmpInst = Get-TermFrequency -Text $LCA.Script -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
								foreach ($row in $tmpInst) {
									#								foreach ($Term in $lstTerms) {
									if ($row.Found -gt 0) {
#										$tmpResult.Add([FindResult]@{
#												LabSeries  = $seriesName
#												LabProfile = $labId
#												Location   = "LCA ($($LCA.Id) - $($LCA.Name))"
#												Term	   = $row.Term
#												Found	   = $row.Found
#											}
										#										)
										Add-FindResult -Location "LCA ($($LCA.Id) - $($LCA.Name))" -Row $row
									}
									Write-Note -note "  Term:  $($row.Term)"
									Write-Note -note "  Loc:   LCA ($($LCA.Id) - $($LCA.Name))"
									Write-Note -note "  Found: $($row.Found) times"
									#								}
								}
							}
						}
					}
				}
				
				if ($checkActivities) {
				###########################################
				# FIND TERMS - Automated Activities
				###########################################
				# Automated Activity Scripts
				$AutoActivities = Invoke-WithRetry {
					Get-LODLabProfileActivity -LabProfileId $labId
				}
					foreach ($Act in $AutoActivities) {
						# only examine scripts
						if ($Act.Scripts.Count -gt 0) {
							foreach ($actScript in $Act.Scripts) {
								$tmpInst = Get-TermFrequency -Text $actScript.Script -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
								foreach ($row in $tmpInst) {
									#								foreach ($Term in $lstTerms) {
									if ($row.Found -gt 0) {
#										$tmpResult.Add([FindResult]@{
#												LabSeries  = $seriesName
#												LabProfile = $labId
#												Location   = "Activity ($($Act.Id) - $($Act.Name)) Script ($actScript.Id)"
#												Term	   = $row.Term
#												Found	   = $row.Found
#											}
#										)
									Add-FindResult -Location "Activity ($($Act.Id) - $($Act.Name)) Script $($actScript.Id)" -Row $row									}
									Write-Note -note "  Term:  $($row.Term)"
									Write-Note -note "  Loc:   Activity ($($Act.Id) - $($Act.Name)) Script $($actScript.Id)"
									Write-Note -note "  Found: $($row.Found) times"
									#								}
								}
							}
						}
					}
				}
				
				if ($checkInstructionsAndSwaps) {
				###########################################
				# FIND TERMS - Instructions & Text Swaps
				###########################################
				
				# Retrieve the Instructions Sets for the Lab Profile
				try {
					write-note -note "Getting Instructions Set List for Lab: $($labId)"
					$instructionsSets = Invoke-WithRetry {
						Get-LODLabProfileInstructionsSets -LabProfileId $labId
					} 
					Write-Note -note "  Successfully retrievied the Instructions Set List for Lab: $($labId)"
					Write-Note -note "  Count of Instructions Set to process: $($instructionsSets.InstructionsSets.Count)"
				} catch {
					Write-Note -note "ERROR on (Get-LODLabProfileInstructionsSets -LabProfileId $labId).instructionsSets. May be Locked."
					Write-Note -note "ERROR: $($_.Exception.Message)"
				}
					
					if ($cont) {
						$updInstructions = $false
						for ($x = 0; $x -lt $instructionsSets.InstructionsSets.Count; $x++) {
							# Initialize the Instructions variables
							$contSet = $true
							$outActId = ""
							$outActName = ""
							$lstActName = [System.Collections.Generic.List[string]]::new()
							
							# If the Lab contents are not inherited then continue
							if (-not $inhContent) {
								# If the Instructions Set is enabled then continue
								if ($instructionsSets.InstructionsSets[$x].enabled) {
									# Retrieve the Instructions
									Write-Note -note "  Processing Instructions Set: $($instructionsSets.InstructionsSets[$x].Id)"
									try {
										$inst = Invoke-WithRetry {
											Get-LODLabProfileInstructions -LabProfileId $labId -InstructionsSetId $instructionsSets.InstructionsSets[$x].Id
										}
										
										###########################################
										# FIND TERMS - Instructions
										###########################################
										# Instructions - Static
										# Update the output with the counts from the Instructions
										$tmpInst = Get-TermFrequency -Text $inst.Instructions -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
										foreach ($row in $tmpInst) {
											#										foreach ($Term in $lstTerms) {
											if ($row.Found -gt 0) {
#												$tmpResult.Add([FindResult]@{
#														LabSeries  = $seriesName
#														LabProfile = $labId
#														Location   = "Instructions ($($inst.instructionsSetId))"
#														Term	   = $row.Term
#														Found	   = $row.Found
#													}
#												)
												Add-FindResult -Location "Instructions ($($inst.instructionsSetId))" -Row $row
											}
											Write-Note -note "  Term:  $($row.Term)"
											Write-Note -note "  Loc:   Instructions ($($inst.instructionsSetId))"
											Write-Note -note "  Found: $($row.Found) times"
											#										}
										}
										
										# Update the output with the counts from the Instructions Replacements
										# TextSwap - Text
										foreach ($rep in $inst.Replacements) {
											$tmpInst = Get-TermFrequency -Text $rep.Text -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
											foreach ($row in $tmpInst) {
												#											foreach ($Term in $lstTerms) {
												if ($row.Found -gt 0) {
#													$tmpResult.Add([FindResult]@{
#															LabSeries  = $seriesName
#															LabProfile = $labId
#															Location   = "Instructions ($($inst.instructionsSetId)) - Replacements (Text: $($rep.Text))"
#															Term	   = $row.Term
#															Found	   = $row.Found
#														}
#													)
													Add-FindResult -Location "Instructions ($($inst.instructionsSetId)) - Replacements (Text: $($rep.Text))" -Row $row
												}
												Write-Note -note "  Term:  $($row.Term)"
												Write-Note -note "  Loc:   Instructions ($($inst.instructionsSetId)) - Replacements (Text: $($rep.Text))"
#												Write-Note -note "  Loc:   Instructions ($($inst.instructionsSetId)) - Replacements (Text: $($rep.Replacement))"
												Write-Note -note "  Found: $($row.Found) times"
												#											}
											}
										}
										
										# TextSwap - Replacement
										foreach ($rep in $inst.Replacements) {
											$tmpInst = Get-TermFrequency -Text $rep.Replacement -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
											foreach ($row in $tmpInst) {
												#											foreach ($Term in $lstTerms) {
												if ($row.Found -gt 0) {
#													$tmpResult.Add([FindResult]@{
#															LabSeries  = $seriesName
#															LabProfile = $labId
#															Location   = "Instructions ($($inst.instructionsSetId)) - Replacements (Replacement: $($rep.Text))"
#															Term	   = $row.Term
#															Found	   = $row.Found
#														}
#													)
													Add-FindResult -Location "Instructions ($($inst.instructionsSetId)) - Replacements (Replacement: $($rep.Replacement))" -Row $row
												}
												Write-Note -note "  Term:  $($row.Term)"
												Write-Note -note "  Loc:   Instructions ($($inst.instructionsSetId)) - Replacements (Replacement: $($rep.Replacement))"
												Write-Note -note "  Found: $($row.Found) times"
												#											}
											}
										}
										
										# Instructions - GitHub
										# Split the instructions into an array by lines
										$lines = $inst.instructions -split "`n"
										# Examine each line for the Cloud Password
										$skipIt = $false
										for ($z = 0; $z -lt $lines.Count; $z++) {
											# Only evaluate lines that are not blank
											if (-not [string]::IsNullOrEmpty($lines[$z].Trim())) {
												# Check to see if the line is actually an external include
												if ($lines[$z].Trim() -match '^<!--.*-->$') {
													# If the line is commented out then skip it
													$skipIt = $true
												} elseif (($lines[$z].trim() -like '<!--*') -and ($lines[$z].trim() -notmatch '-->')) {
													# If the is the start of a multi-line comment then skip it
													$skipIt = $true
												} elseif ($skipIt -and ($lines[$z].trim() -notlike '<!--*') -and ($lines[$z].trim() -match '-->')) {
													# If we have previously started a comment and are now ending it then don't skip it
													$skipIt = $false
												} elseif ((-not $fndExternal) -and (-not $skipIt) -and ($lines[$z].trim() -match '^!INSTRUCTIONS\s?\[.*\)$')) {
													# If we are not in a comment and the line contains an instruction include download it and examine it
													# For reporting purposes check if the URL points to LODSContent
													if ($lines[$z].ToLower().Contains('lodscontent')) {
														$lodsContent = "Y"
													}
													# Check to see if the line contains a URL
													if ($lines[$z].trim() -match '\[.*?\]\((https?://.+)\)') {
														#																if ($lines[$z].trim() -match '\((https?://[^)]+)\)') {
														$url = $matches[1]
													}
													# Replace the language code if required
#													$url = $url.Replace("@lab.LanguageCode", $instructionsSets.InstructionsSets[$z].LanguageShortName)
													$url = $url.Replace("@lab.LanguageCode", $instructionsSets.InstructionsSets[$x].LanguageShortName)
													try {
														$timeStamp = Get-Date -Format "MMddyy_HHmmss"
														$outUpdate += "`n$($timeStamp):       Retrieving External Instructions: $($url)"
														
														Write-Output "Making Web request on URL: $($url)"
														$downloadedContent = Invoke-WebRequest -Uri $url -UseBasicParsing
													} catch {
														Write-Output "ERROR on Invoke-WebRequest -Uri $($url) -UseBasicParsing"
														Write-Output "ERROR: $($_.Exception.Message)"
														
														$timeStamp = Get-Date -Format "MMddyy_HHmmss"
														$outUpdate += "`n$($timeStamp):       ERROR: Retrieving External Instructions: $($url)`n                     Details:$($_.Exception.Message)"
													}
													
													# Count the number of times the text is found in the GitHub Included instructions
													#												$srchInclude1 = ($downloadedContent | Select-String -Pattern $pattern1 -AllMatches).Matches.Count
													$tmpInst = Get-TermFrequency -Text $downloadedContent -Terms $lstTerms -MatchType $FindType -CaseMode $CaseType
													foreach ($row in $tmpInst) {
														#													foreach ($Term in $lstTerms) {
														if ($row.Found -gt 0) {
#															$tmpResult.Add([FindResult]@{
#																	LabSeries  = $seriesName
#																	LabProfile = $labId
#																	Location   = "Instructions - GitHub ($($inst.instructionsSetId)) - $url"
#																	Term	   = $row.Term
#																	Found	   = $row.Found
#																}
#															)
															Add-FindResult -Location "Instructions - GitHub ($($inst.instructionsSetId)) - $url" -Row $row
														}
														Write-Note -note "  Term:  $($row.Term)"
														Write-Note -note "  Loc:   Instructions - GitHub ($($inst.instructionsSetId)) - $url"
														Write-Note -note "  Found: $($row.Found) times"
														#													}
													}
												}
											}
										}
									} catch {
										Write-Note -note "  ERROR on Get-LODLabProfileInstructions -LabProfileId $($labId) -InstructionsSetId $($instructionsSets.InstructionsSets[$x].Id)"
										Write-Note -note "    ERROR: $($_.Exception.Message)"
										$contSet = $false
									}
									
								} else {
									Write-Note -note "      Instructions Set not enabled: $($instructionsSets.InstructionsSets[$x].Id) $($instructionsSets.InstructionsSets[$x].DisplayId)"
								}
							} else {
								Write-Note -note "      Instructions are inherited for Lab ID: $($labId)"
							}
						}
					}
				}
				
				# Write out the result, if any, for this Lab
				if ($tmpResult.Count -gt 0) {
					foreach ($row in $tmpResult) {
						$outResult.Add($row)
					}
					$tmpResult = $null
				}
			} else {
				# The Dev Status is not set to 'Complete'
				Write-Note -note "      Dev Status is not 'Complete'. Skipping Lab Profile: ($($labProfile.Id)) $($labProfile.Name)"
			}
			
		} else {
			# This lab is not enabled. Set dummy row values
			Write-Note -note "        This lab is not enabled: $($labId)"
		}
	}
}

<#
	.SYNOPSIS
		Get-ScriptDirectory returns the proper location of the script.
	
	.DESCRIPTION
		A detailed description of the Get-ScriptDirectory function.
	
	.OUTPUTS
		System.String
	
	.NOTES
		Returns the correct path within a packaged executable.
#>
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

# =========================================
# M A I N  L I N E
# =========================================

# Ensure that the input text list is not a 0-length list
Write-Note -note "DEBUG: find-text.ps1 started"
if ($FindList.Length -gt 0) {
	
	# Log in to Skillable Studio
	Write-Note -note "START - Processing Lab Series & Profiles"
	try {
		if (-not $global:LODSessionToken) {
			Connect-LabOnDemand -ERRORAction 'Continue'
			Write-Note -note "Login successful"
			
			Set-Variable -Name 'LODSessionToken' -Value $(Get-LODSessionToken) -Force -Option AllScope -Scope Global
		} else {
			Connect-LabOnDemand -SessionToken $global:LODSessionToken
		}
			
	} catch {
		Write-Note -note "FAILED TO CONNECT"
		Write-Note -note "  Details: $($_.Exception.Message)"
	}
	
	# If a list of Lab Series' is provided then find the Lab Profiles for each and process them
	if ($LabSeriesList.Length -gt 0) {
		Write-Note -note "###################################################"
		Write-Note -note "# Lab Series List: $($LabSeriesList)"
		Write-Note -note "# Find List: $($FindList)"
		Write-Note -note "# Find Type: $($FindType)"
		Write-Note -note "# Case Type: $($CaseType)"
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
						Write-Note -note "Retrieving list of profiles on Series: $($LabSeries) $($curSeries.Name)"
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
#							Process-LabProfile -seriesName "($($LabSeries)) $($curSeries.Name)" -labId $Lab.Id
							Process-LabProfile -seriesId $curSeries.Id -seriesName $curSeries.Name -labId $Lab.Id
						}
					} catch {
						Write-Note -note "Error on Process-LabProfile -LabSeriesId $($curSeries.Id)"
						Write-Note -note "Error: $($_.Exception.Message)"
					}
				} else {
					Write-Note -note "Current Series is Disabled: $($tmpSeries) $($curSeries.Name)"
				}
			} catch {
				Write-Note -note "Current Series is Disabled: $($tmpSeries) $($curSeries.Name)"
			}
#			Write-Note -note "$([System.Math]::Round(($x / $arrLabSeries.Count) * 100))% COMPLETE"
		}
		
		# End processing
		Write-Note -note "END - Processing Lab Series & Profiles"
	} else {
		# Otherwise process all the supplied Lab Profiles
		Write-Note -note "START - Processing Lab Profiles"
		Write-Note -note "###################################################"
		Write-Note -note "# Lab Profile List: $($LabProfileList)"
		Write-Note -note "# Find List: $($FindList)"
		Write-Note -note "# Find Type: $($FindType)"
		Write-Note -note "# Case Type: $($CaseType)"
		Write-Note -note "###################################################"
		
		# Build the Profile List
		$arrLabProfiles = $LabProfileList -split ","
		
		foreach ($Id in $arrLabProfiles) {
			$curId = $Id
#			Update-LabProfile -labId $Id
			Process-LabProfile -labId $Id
		}
		
		# End processing
		Write-Note -note "END - Processing Lab Profiles"
	}
	
	# Create the CSV Report Name and path
	$timestamp = Get-Date -Format "yyyMMdd_HHmmss"
	# Set the output Directory
	$outPath = Get-ScriptDirectory
	# Replace path if using "Program Files"
	if ($outPath -like "C:\Program Files\*") {
		# Replace the output folder with a writable folder
		$newPath = $outPath -Replace 'Program Files', 'temp'
		#create the output folder
		New-Item -Path $newPath -ItemType Directory -Force | Out-Null
	} else {
		$newPath = $outPath
	}
	$rptName = "$($newPath)\Find-Text_Report_$($timestamp).csv"
	
	if ($outResult.Count -gt 0) {
#		Write-Note -hideTimeStamp -note ""
#		Write-Note -hideTimeStamp -note "###################################################"
#		Write-Note -hideTimeStamp -note "# RESULTS"
#		Write-Note -hideTimeStamp -note "###################################################"
		
#		foreach ($row in $outResult) {
#			Write-Note -hideTimeStamp -note "$($row.LabSeries),$($row.LabProfile),$($row.Location),$($row.Term),$($row.Count)"
#		}
#		Write-Note -hideTimeStamp -note "###################################################"
		
#		# Set the file and Header
#		Set-Content -Path $rptName
		# Append the data
		$outResult | Export-Csv -Path $rptName -NoTypeInformation -Encoding UTF8
	} else {
#		# Create the Report
#		try {
#			Out-File -FilePath $rptName -Append "The Search terms were not found.`r`n  Lab Profile List: $($LabProfileList)`r`n  Find List: $($FindList)`r`n  Find Type: $($FindType)`r`n  Case Type: $($CaseType)" -Encoding UTF8
#		} catch {
#			Write-Note -note "The Search terms were not found.`r`n  Lab Profile List: $($LabProfileList)`r`n  Find List: $($FindList)`r`n  Find Type: $($FindType)`r`n  Case Type: $($CaseType)"
#		}
		
		# No matches: log the details, then write a header-only CSV so that
		# Report-FindText.ps1 imports zero rows and the combined schema stays clean
		$searchScope = If ($LabSeriesList.Length -gt 0) {
			"Lab Series List: $($LabSeriesList)"
		} Else {
			"Lab Profile List: $($LabProfileList)"
		}
		Write-Note -note "The Search terms were not found."
		Write-Note -note "  $($searchScope)"
		Write-Note -note "  Find List: $($FindList)"
		Write-Note -note "  Find Type: $($FindType)"
		Write-Note -note "  Case Type: $($CaseType)"
		
		Try {
			# ConvertTo-Csv emits a header line and a data line; keep only the header
			$csvHeader = ([FindResult]::new() | ConvertTo-Csv -NoTypeInformation)[0]
			Set-Content -Path $rptName -Value $csvHeader -Encoding UTF8
		} Catch {
			Write-Note -note "ERROR writing empty report $($rptName): $($_.Exception.Message)"
		}
	}
	Write-Note -note "Report written to: $($rptName)"
} else {
	Write-Note -note "There must be at least 1 value to search for"
}