<#
	.SYNOPSIS
		Build the Tenant-Based Input Parameters
	
	.DESCRIPTION
		This script will log in to the required Azure subscription and poll
		the Resource Explorer to gather the resources used during a lab. This
		will then be used to create a standardized JSON Resource Scrape file.
	
	.PARAMETER SubscriptionId
		Provide the Azure Subscription ID in the format "yyyy-yyyy-yyyy-yyyy"
	
	.PARAMETER Username
		Provide the Azure Subscription username
	
	.PARAMETER Password
		Provide the Azure Subscription password
	
	.PARAMETER OutPath
		Path to output files
	
	.PARAMETER Details
		Display all messages to the console
	
	.PARAMETER Stamp
		Attach the datetime stamp to the output folder and some files
	
	.PARAMETER TAPToken
		A description of the TAPToken parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2023 v5.8.232
		Created on:   	2/22/2024 2:24 PM
		Created by:   	Wayne Klapwyk
		Organization: 	WKUtils
		Filename:     	get-ResourceScrape
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true,
			   HelpMessage = 'Provide the Azure Subscription ID in the format "yyyy-yyyy-yyyy-yyyy"')]
	[ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
	[Alias('i')]
	[string]$SubscriptionId,
	[Parameter(Mandatory = $true,
			   ValueFromPipeline = $true,
			   HelpMessage = 'Provide the Azure Account Username (as a valid email address)')]
	[ValidatePattern('^([\w-\.]+)@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)|(([\w-]+\.)+))([a-zA-Z]{2,4}|[0-9]{1,3})(\]?)$')]
	[Alias('u')]
	[string]$Username,
	[Parameter(Mandatory = $false)]
	[Alias('p')]
	[string]$Password,
	[Parameter(Mandatory = $false)]
	[Alias('t')]
	[string]$TAPToken,
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
	
	# Create the message for the log file
	#Write-Output "$($dte) (id:$($id)) $($msg)" | Out-file $log -append
	$logMessage = "$($dte) (id:$($id)) $($msg)"
	
	# Display the message to the console if requested
	if ($toConsole) {
		Write-Host "$($dte) (id:$($id)) $($msg)"
	}
	
	    # Buffer log messages and write them in bulk
    $global:logBuffer += $logMessage + "`n"
    if ($global:logBuffer.Length -gt 1000) {
        $global:logBuffer | Out-File $log -Append
        $global:logBuffer = ""
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
	
	$errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	if ($err -eq "Auth") {
		if (Test-Path -Path "$($outDir)\FlagFile.chk" -PathType Leaf) {
			
			Write-log -toConsole $Details -id $id -msg "Your Azure credentials have not been set up or have expired, please run Connect-AzAccount to set up your Azure credentials. SharedTokenCacheCredential authentication unavailable. Token acquisition failed. Ensure that you have authenticated with a developer tool that supports Azure single sign on.`n`nThe Lab has likely ended or is otherwise unavailable. Please wait while processing is completed."
			Remove-Item -Path "$($outDir)\FlagFile.chk"
		}
	} else {
		$e = $err.Exception
		$msg = $e.Message
		while ($e.InnerException) {
			$e = $e.InnerException
			$msg += "`n" + $e.Message
		}
		Write-log -toConsole $Details -id $id -msg "Error $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
	}
}

function Set-Environment {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$inDir
	)
	
	$retVal = $true
	try	{
		# Install the Azure PowerShell module (if you haven't already)
		Write-log -toConsole $Details -id 50 -msg "Verifying the local Powershell Azure environment."

#		If (Get-Module -ListAvailable -Name Az)	{
#			# Check the availability of the Azure Az module
#			Import-Module Az -ErrorAction Stop
#			Write-log -toConsole $Details -id 51 -msg "The Azure Az module is ready for use"
#		} else {
#			# This utility requires the use of the Azure Az Powershell module.
#			Write-log -toConsole $Details -id 52 -msg "This utility requires the use of the Azure Az Powershell module."
#			Write-log -toConsole $Details -id 53 -msg "If you have not done so, please install this module as an administrator before proceeding using these commands:"
#			Write-log -toConsole $Details -id 57 -msg "	 Install-Module -Name Az -Scope CurrentUser -AllowClobber -Force"
#			Write-log -toConsole $Details -id 58 -msg "	 Import-Module -Name Az"
#		}
		
#		if (-not (Get-Module -Name Az)) {
#			Import-Module Az -ErrorAction SilentlyContinue
#		}
		if (Get-Module -ListAvailable -Name Az.Accounts) {
			Write-log -toConsole $Details -id 51 -msg "The Azure Az module is loaded and ready for use"
		} else {
			# This utility requires the use of the Azure Az Powershell module.
			Write-log -toConsole $Details -id 52 -msg "This utility requires the use of the Azure Az Powershell module."
			Write-log -toConsole $Details -id 53 -msg "If you have not done so, please install this module as an administrator before proceeding using these commands:"
			Write-log -toConsole $Details -id 57 -msg "	 Install-Module -Name Az -Scope CurrentUser -AllowClobber -Force"
			Write-log -toConsole $Details -id 58 -msg "	 Import-Module -Name Az"
			$msg = @"
This utility requires the use of the Azure Az Powershell module.
If you have not done so, please install this module as an administrator before proceeding using these commands:

    Install-Module -Name Az -Scope CurrentUser -AllowClobber -Force
    NOTE: If prompted accepted with [A] to accept all and continue 

    Import-Module -Name Az
"@
			[System.Windows.Forms.MessageBox]::Show($msg, 'Az Module Required', 'OK', 'Information')
			
			# Only launch the scrape if the Az module is installed
			$retVal = $false
		}
	} catch {
		Show-Error -err $_ -id 1
		
		$retVal = $false
	}
	
	return $retVal
}

# Function to get API version for a resource type
function Get-ApiVersion {
	param
	(
		[string]$resourceType,
		[string]$providerNamespace,
		$headers
	)
	
	# Providers URL
	$providersUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/$($providerNamespace)?api-version=2021-04-01"
	try {
		# Set TLS version
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		# Get Rest method
#		try {
			$providersResponse = Invoke-RestMethod -Uri $providersUrl -Headers $headers -Method GET
#		} catch {
#			Connect-AzAccount
#			try {
#				$providersResponse = Invoke-RestMethod -Uri $providersUrl -Headers $headers -Method GET
#			} catch {
#				throw $_
#			}
#		}
		# Find the matching resource type
		$resourceTypeEntry = $providersResponse.resourceTypes | Where-Object {
			$_.resourceType -eq $resourceType
		}
		
		# Return the latest API version
		return $resourceTypeEntry.apiVersions[0] # Usually, the first entry is the most recent version
	} catch {
		Write-log -toConsole $Details -id 14 -msg "Invoke-RestMethod Error: $($_.FullyQualifiedErrorId): $($_.Exception.Message)"
		throw "Invoke-RestMethod Error"
		
		# Return the error message
		return "Invoke-RestMethod Error"
	}
	
}

<#
	.SYNOPSIS
		Login to an Azure Account
	
	.DESCRIPTION
		Login to an Azure Account using credentials and a tenant ID
	
	.PARAMETER inUser
		A description of the inUser parameter.
	
	.PARAMETER inPswd
		A description of the inPswd parameter.
	
	.PARAMETER inSubs
		A description of the inSubs parameter.
	
	.EXAMPLE
		PS C:\> Access-AzAccount -inUser 'Value1' -inPswd 'Value2' -inTenant 'Value3'
	
	.NOTES
		
#>

#function Connect-WithTapFallback {
#	param (
#		[Parameter(Mandatory = $true)]
#		[string]$TapToken,
#		# The TAP (Azure AD access token)
#		[Parameter(Mandatory = $true)]
#		[string]$TenantId,
#		# Azure AD tenant ID
#		[Parameter(Mandatory = $true)]
#		[string]$AccountId # UPN (user@domain) or AppId
#	)
#	
#	try {
#		Write-Host "🔑 Attempting to authenticate with TAP token..."
#		$null = Connect-AzAccount -AccessToken $TapToken -Tenant $TenantId -AccountId $AccountId -ErrorAction Stop
#		
#		# Validate context
#		$ctx = Get-AzContext
#		if ($ctx -and $ctx.Subscription) {
#			Write-Host "✅ Connected with TAP token. Subscription:" $ctx.Subscription.Name
#			return $ctx
#		} else {
#			throw "Token authentication succeeded, but no subscription context was found."
#		}
#	} catch {
#		Write-Warning "⚠️ TAP token authentication failed. Falling back to interactive login..."
#		try {
#			$null = Connect-AzAccount -Tenant $TenantId
#			$ctx = Get-AzContext
#			if ($ctx -and $ctx.Subscription) {
#				Write-Host "✅ Connected interactively. Subscription:" $ctx.Subscription.Name
#				return $ctx
#			} else {
#				throw "Password authentication succeeded, but no subscription context was found."
#			}
#		} catch {
#			throw "⚠️ Both TAP token and Password authentication failed."
#		}
#	}
#}

function Access-AzAccount {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$inUser,
		[Parameter(Mandatory = $true)]
		[string]$inPswd,
		[Parameter(Mandatory = $true)]
		[string]$inTAP,
		[Parameter(Mandatory = $true)]
		[string]$inSubs
	)
	
	$retVal = $false
	
	try {
		Write-log -toConsole $Details -id 60 -msg "Attempting AZ Login (Web): $($inSubs)."
		
		#		Write-Host "🔑 Launching Web Login for Azure. Use the Temporary Access Pass (TAP) Token if requested. Otherwise, use the provided password..."
		Update-AzConfig -DefaultSubscriptionForLogin $inSubs -EnableLoginByWam $false
		$context = Connect-AzAccount
		
#		$tnnt = $context.Context.Tenant.id
#		if (Get-AzConfig | Where-Object {
#				$_.Key -eq "EnableLoginByWam"
#			}) {
#			$disWAM = Update-AzConfig -EnableLoginByWam $false
#			$disCon = Disconnect-AzAccount -Username $Username
##			# Provide your Azure account credentials with Password
##			$pswd = ConvertTo-SecureString $inTAP -AsPlainText -Force
##			$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $inUser, $pswd
##			
###			$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Tenant $tnnt
#			$context = Connect-AzAccount
#		}
		
		# Reset the AZ Context
		Write-log -toConsole $Details -id 64 -msg "Attempting to set the AZ Context for subscription: $($SubscriptionId)."
		try {
			$azContext = Set-AzContext -Subscription $SubscriptionId
		} catch {
			$e = $err.Exception
			$msg = $e.Message
			while ($e.InnerException) {
				$e = $e.InnerException
				$msg += "`n" + $e.Message
			}
			Write-log -toConsole $Details -id $id -msg "Set Context Error w/ Web $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
		}
		
		$retVal = $true
	} catch {
		$e = $err.Exception
		$msg = $e.Message
		while ($e.InnerException) {
			$e = $e.InnerException
			$msg += "`n" + $e.Message
		}
		Write-log -toConsole $Details -id $id -msg "Login Error w/ Web $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
		Show-Error -err $_ -id 2
	}
	
#	if ($inTAP.Length -gt 0) {
#		try {
#			# Provide your Azure account credentials with Password
#			$pswd = ConvertTo-SecureString $inTAP -AsPlainText -Force
#			$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $inUser, $pswd
#			
#			# Connect to your Azure account
#			Write-log -toConsole $Details -id 60 -msg "Attempting AZ Login (TAP): $($inSubs)."
##			$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Scope CurrentUser -ErrorAction Continue
##			$context = Connect-AzAccount -AccessToken $inTAP -AccountId $inUser -Subscription $inSubs -Scope CurrentUser -ErrorAction Continue
#			$context = Connect-AzAccount -AccessToken $inTAP -AccountId $inUser -Subscription $inSubs -ErrorAction Continue
#			$tnnt = $context.Context.Tenant.id
#			if (Get-AzConfig | Where-Object {
#					$_.Key -eq "EnableLoginByWam"
#				}) {
#				$disWAM = Update-AzConfig -EnableLoginByWam $false
#				$disCon = Disconnect-AzAccount
#				$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Tenant $tnnt
#			}
#			
#			# Reset the AZ Context
#			Write-log -toConsole $Details -id 64 -msg "Attempting to set the AZ Context for subscription: $($SubscriptionId)."
#			$azContext = Set-AzContext -Subscription $SubscriptionId
#			
#			$retVal = $true
#		} catch {
#			$e = $err.Exception
#			$msg = $e.Message
#			while ($e.InnerException) {
#				$e = $e.InnerException
#				$msg += "`n" + $e.Message
#			}
#			Write-log -toConsole $Details -id $id -msg "Login Error w/ TAP $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
#			Show-Error -err $_ -id 2
#		}
#	} else {
#		# Try to validate with the password first, then the TAP if it is provided
#		try {
#			# Provide your Azure account credentials with Password
#			$pswd = ConvertTo-SecureString $inPswd -AsPlainText -Force
#			$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $inUser, $pswd
#			
#			# Connect to your Azure account
#			Write-log -toConsole $Details -id 60 -msg "Attempting AZ Login (PSWD): $($inSubs)."
#			$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Scope CurrentUser -ErrorAction Continue
#			$tnnt = $context.Context.Tenant.id
#			if (Get-AzConfig | Where-Object { $_.Key -eq "EnableLoginByWam"	}) {
#				$disWAM = Update-AzConfig -EnableLoginByWam $false
#				$disCon = Disconnect-AzAccount
#				$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Tenant $tnnt
#			}
#			
#			# Reset the AZ Context
#			Write-log -toConsole $Details -id 64 -msg "Attempting to set the AZ Context for subscription: $($SubscriptionId)."
#			$azContext = Set-AzContext -Subscription $SubscriptionId
#			
#			$retVal = $true
#		} catch {
#			if ($inTAP.Length -gt 0) {
#				try {
#					# Provide your Azure account credentials with Password
#					$pswd = ConvertTo-SecureString $inTAP -AsPlainText -Force
#					$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $inUser, $pswd
#					
#					# Connect to your Azure account
#					Write-log -toConsole $Details -id 60 -msg "Attempting AZ Login (TAP): $($inSubs)."
#					$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Scope CurrentUser -ErrorAction Continue
#					$tnnt = $context.Context.Tenant.id
#					if (Get-AzConfig | Where-Object {
#							$_.Key -eq "EnableLoginByWam"
#						}) {
#						$disWAM = Update-AzConfig -EnableLoginByWam $false
#						$disCon = Disconnect-AzAccount
#						$context = Connect-AzAccount -Credential $cred -Subscription $inSubs -Tenant $tnnt
#					}
#					
#					# Reset the AZ Context
#					Write-log -toConsole $Details -id 64 -msg "Attempting to set the AZ Context for subscription: $($SubscriptionId)."
#					$azContext = Set-AzContext -Subscription $SubscriptionId
#					
#					$retVal = $true
#				} catch {
#					$e = $err.Exception
#					$msg = $e.Message
#					while ($e.InnerException) {
#						$e = $e.InnerException
#						$msg += "`n" + $e.Message
#					}
#					Write-log -toConsole $Details -id $id -msg "Login Error w/ TAP $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
#					Show-Error -err $_ -id 2
#				}
#			} else {
#				$e = $err.Exception
#				$msg = $e.Message
#				while ($e.InnerException) {
#					$e = $e.InnerException
#					$msg += "`n" + $e.Message
#				}
#				Write-log -toConsole $Details -id $id -msg "Login Error w/ PSWD $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
#				Show-Error -err $_ -id 2
#			}
#		}
#	}
	
	return $retVal
}

function Create-TempFiles {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$inDir
	)
	
	# Create the Flag File
	# This script will query for resources as long as this file exists
	$chkfile = New-Item -Path "$($inDir)\FlagFile.chk" -ItemType File -Force
	
	# Tell the user to delete the Flag File to stop the Resource Scrape utility
	$msg = @"
The get-ResourceScrape utility will now start gathering the resources from your subscription.

To stop this utility before the end of the lab, REMOVE the following File:
    $($inDir)\FlagFile.chk.
"@
	Write-log -toConsole $Details -id 54 -msg $msg
	
	# Create/overwrite the temporary output file with a blank default file
	Remove-Item -Path "$($inDir)\output.tmp" -ErrorAction SilentlyContinue
	Set-Content -Path "$($inDir)\output.tmp" -Value ''
}

function Build-outputRecord {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[object]$inRcd,
		[Parameter(Mandatory = $true)]
		[string]$inTimeStamp,
		[Parameter(Mandatory = $true)]
		[object]$inProps
	)
	
	$retObj = ""
	
	try {
		try {
			$jobj = ""
			$jsnTags = ""
			
			# Set up any tags for the resource
			if ($inRcd.Tags.Keys.Count -gt 0) {
				$retObj = $retObj + "`"["
				$toAdd = ""
				$arrTags = New-Object -TypeName System.Collections.ArrayList
				for ($x = 0; $x -lt $inRcd.Tags.Keys.Count; $x++) {
					# Create the current Tag Key/Value Pair
					$toAdd = "{`"$($inRcd.Tags.Keys[$x])`":`"$($inRcd.Tags.Values[$x])`"}"
					# Add the current Tag into the JSON Object
					$arrTags.Add((ConvertFrom-Json -InputObject $toAdd))
				}
				$jsnTags = $arrTags | ConvertTo-Csv
			}
		} catch { }
		
			# Set up the resource with/without Tags and Properties
			if ($inProps.Count -gt 0) {
				
				# Set up the base resource with Tags
				$targetJSON = @{
					"Timestamp"		    = $inTimeStamp
					"Name"			    = $inRcd.Name
					"ResourceGroupName" = $inRcd.ResourceGroupName
					"ResourceType"	    = $inRcd.ResourceType
					"Location"		    = $inRcd.Location
					"ResourceId"	    = $inRcd.ResourceId
					"Tags"			    = $arrTags
				} | ConvertTo-Json
				
				# Add in the Properties
				$targetJSON | Add-Member -MemberType NoteProperty -Name "ResProperties" -Value $inProps -Force
			
				$retObj = $targetJSON
				
			} else {
				
				# Set up the base resource with Tags and default the Properties to blank
				$retJSON = @{
					"Timestamp"		    = $inTimeStamp
					"Name"			    = $inRcd.Name
					"ResourceGroupName" = $inRcd.ResourceGroupName
					"ResourceType"	    = $inRcd.ResourceType
					"Location"		    = $inRcd.Location
					"ResourceId"	    = $inRcd.ResourceId
					"Tags"			    = $arrTags
					"ResProperties"	    = "[]"
				} | ConvertTo-Json
			
				$retObj = $targetJSON
			}
	} catch {
		Show-Error -err $_ -id 3
		
		# Set the return JSON to blank when an error is encountered
		$retObj = "`"[]`""
	}
	
	# Return the full record
	return $retObj
}

function Is-Unique {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[object]$inRow
	)
	
	$retVal = $true
	
	try {
		# Import the temporary output file
		$csv = Import-Csv "$($outDir)\output.tmp"
		$jsn = Get-Content -Path "$($outDir)\output.tmp" -Raw | ConvertFrom-Json
		
		# Check if the record exists in the JSON object
		Write-log -toConsole $Details -id 102 -msg "Searching output Directory: $($outDir)\output.tmp"
		Write-log -toConsole $Details -id 103 -msg "Checking values:"
		Write-log -toConsole $Details -id 103 -msg "  $($inRow.ResourceName)"
		Write-log -toConsole $Details -id 103 -msg "  $($inRow.ResourceGroupName)"
		Write-log -toConsole $Details -id 103 -msg "  $($inRow.ResourceType)"
		Write-log -toConsole $Details -id 103 -msg "  $($inRow.ResourceLocation)"
		Write-log -toConsole $Details -id 103 -msg "  $($inRow.ResourceId)"
		Write-log -toConsole $Details -id 103 -msg "  $([string]$inRow.ResProperties)"
		
		$recordExists = $jsn | Where-Object {
			$_.ResourceName -eq $inRow.ResourceName -and
			$_.ResourceGroupName -eq $inRow.ResourceGroupName -and
			$_.ResourceType -eq $inRow.ResourceType -and
			$_.ResourceLocation -eq $inRow.ResourceLocation -and
			$_.ResourceId -eq $inRow.ResourceId -and
			[string]$_.ResProperties -eq [string]$inRow.ResProperties
		}
		
		# Output the result
		if ($recordExists) {
			Write-log -toConsole $Details -id 104 -msg "  Record Found: $($recordExists)"
			$retVal = $false
		} else {
			Write-log -toConsole $Details -id 105 -msg "  Record Not Found: $($recordExists)"
		}
	} catch {
		Show-Error -err $_ -id 4
	}
	
	return $retVal
}

function Write-Stats {
	param
	(
		[string]$groupName,
		$groupResCount
	)
	
	# Prepare the stats message
	$msg = @"
Scrape Passes:     $($script:cntPass)

Num of Groups:     $($script:maxGroups)

Current Group:     $($groupName)
Group Resources:   $($groupResCount)

Records Processed: $($script:cntRecords)
"@
	
	# Write the update to teh stats file
	Set-Content -Path $script:cntFile -Value $msg -Force -Encoding UTF8
}

function Run-Scrape {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$inDir
	)
	$retVal = $false

	try {
		# Create a temporary statistics file if it doesn't exist'
		if (-not [System.IO.File]::Exists("$($inDir)\CountFile.cnt")) {
			$script:cntFile = New-Item -Path "$($inDir)\CountFile.cnt" -ItemType File -Force
		} else {
			$script:cntFile = "$($inDir)\CountFile.cnt"
		}
		
		# Query the subscription for resources until the Flag File is removed
		# or for a maximum of 10 hours
		Do {
			# Retrieve the list of Resource Groups in the current Subscription
			try {
				Write-log -toConsole $Details -id 63 -msg "Attempting to retrieve the list of Resource Groups."
				$resourceGroups = Get-AzResourceGroup -ErrorAction Stop
				
#				### Try using the API ###
#				# Define the Azure Resource Explorer API URL
				$subscriptionId = (Get-AzContext).Subscription.Id
				$resourceManagerEndpoint = "https://management.azure.com"
				$resourceGroupsUrl = "$resourceManagerEndpoint/subscriptions/$subscriptionId/resourcegroups?api-version=2021-04-01"
#				
				# Get the Azure AD Bearer Token
				#$accessToken = (Get-AzAccessToken -ResourceUrl https://management.azure.com).Token
				try {
					
					$tokenObj = (Get-AzAccessToken).Token
					
					if ($tokenObj -is [System.Security.SecureString]) {
						$accessToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
							[Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenObj)
						)
					} else {
						$accessToken = $tokenObj
					}
					
#					$accessToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Get-AzAccessToken).Token))
				} catch {
					$e = $_.Exception
					$msg = $e.Message
					while ($e.InnerException) {
						$e = $e.InnerException
						$msg += "`n" + $e.Message
					}
					Write-log -toConsole $Details -id 66 -msg "Access Token Error $($e.HResult): $($e.Message)`n  Full Message: $($msg)"
					
					Show-Error -err "Auth" -id 10
				}
				
				#				
#				# Get the list of resource groups
#				$response = Invoke-RestMethod -Uri $resourceGroupsUrl -Headers @{
#					Authorization = "Bearer $accessToken"
#				} -Method Get
#				
#				# Parse the resource groups
#				$resourceGroups = $response.value
#				### End using the API ###
				
			} catch {
				if (($_.Exception -Match "authentication unavailable") -or ($_.Exception -Match "does not have authorization")) {
					$e = $_.Exception
					$msg = $e.Message
					while ($e.InnerException) {
						$e = $e.InnerException
						$msg += "`n" + $e.Message
					}
					Write-log -toConsole $Details -id 62 -msg "Error $($e.HResult): $($e.Message)`n  Full Message: $($msg)"
					
					Show-Error -err "Auth" -id 10
				}
			}
			
			# Loop through the list of Resource Groups
			$script:maxGroups = $resourceGroups.Count
			foreach ($resourceGroup in $resourceGroups) {
				# Increment the Pass counter
				$script:cntPass++
				
				# Retrieve the list of Resources within each Resource Group
				try {
					$resources = Get-AzResource -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction Stop
					
#					### Try using the API ###
#					# Get resources in the resource group
#					$resourceGroupName = $resourceGroup.Name
#					# Note: The "&expand=properties" retrieves the full list of resource properties
#					$resourcesUrl = "$resourceManagerEndpoint/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/resources?api-version=2021-04-01&expand=properties"
#					$resourceResponse = Invoke-RestMethod -Uri $resourcesUrl -Headers @{
#						Authorization = "Bearer $accessToken"
#					} -Method Get
#					$resources = $resourceResponse.value
#					### End using the API ###
					
				} catch {
#					### We are using the API now.
					try {
						$resources = Get-AzResource -ResourceGroupName $resourceGroup.ResourceGroupName -ExpandProperties -ErrorAction Stop
					} catch {
						if (($_.Exception -Match "authentication unavailable") -or ($_.Exception -Match "does not have authorization")) {
							Show-Error -err "Auth" -id 11
						} else {
							Show-Error -err "Res" -id 11
						}
					}
				}
				
				# Update the Stats file
#				### Using the API has a different Resource Group Name
				Write-Stats -groupName $resourceGroup.ResourceGroupName -groupResCount $resourceGroup.Count
#				Write-Stats -groupName $resourceGroup.Name -groupResCount $resourceGroup.Count
				
				# Build the unified Resource Record
				foreach ($resource in $resources) {
#					### We are using the API now.
					Write-log -toConsole $Details -id 100 -msg "Processing resource: $($resource.ResourceName)"
#					Write-log -toConsole $Details -id 100 -msg "Processing resource: $($resource.Name)"
					try {
#						### The API already returns the expanded properties. This is not necessary
						try {
							$resourceDetails = Get-AzResource -ResourceId $resource.ResourceId -ExpandProperties
						} catch {
							Show-Error -err $_ -id 12
						}
						
						# Get current timestamp
						$timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
						
						# Get the API Version
						$resourceTypeFull = $resource.type # e.g., "Microsoft.Compute/virtualMachines"
						$providerNamespace, $resourceType = $resourceTypeFull -split "/"
						$headers = @{
							'Authorization' = "Bearer $($accessToken)"
							'ContentType'   = "application/json"
						}
						$apiVersion = Get-ApiVersion -resourceType $resourceType -providerNamespace $providerNamespace -headers $headers
						
						# Get the properties for the resource using the API
						$resourceId = $resource.id
						$resourceDetailsUrl = "https://management.azure.com$($resourceId)?api-version=$($apiVersion)"
						$apiDetails = ""
						$apiDetails = Invoke-RestMethod -Uri $resourceDetailsUrl -Headers @{
							Authorization = "Bearer $accessToken"
						} -Method GET
						
						# Create a custom object combining resource and resource group properties
						### We are using the API. It returns different object names
						#$combinedResource = [PSCustomObject]@{
						#	Timestamp			  = $timeStamp
						#	ResourceGroupName	  = $resourceGroup.ResourceGroupName
						#	ResourceGroupLocation = $resourceGroup.Location
						#	ResourceGroupTags	  = $resourceGroup.Tags
						#	ResourceId		      = $resourceDetails.ResourceId
						#	ResourceName		  = $resourceDetails.Name
						#	ResourceType		  = $resourceDetails.ResourceType
						#	ResourceLocation	  = $resourceDetails.Location
						#	ResProperties         = $resourceDetails.Properties
						#	ResourceTags		  = $resourceDetails.Tags
						#}
						$combinedResource = [PSCustomObject]@{
							Timestamp			  = $timeStamp
							ResourceGroupName	  = $resourceGroup.ResourceGroupName
							ResourceGroupLocation = $resourceGroup.Location
							ResourceGroupTags	  = $resourceGroup.Tags
							ResourceId		      = $resource.ResourceId
							ResourceName		  = $resource.Name
							ResourceType		  = $resource.ResourceType
							ResourceLocation	  = $resource.Location
							ResourceSKU		      = $apiDetails.Sku
							ResProperties		  = $resourceDetails.Properties
							APIProperties         = $apiDetails.Properties
							ResourceTags		  = $resource.Tags
						}
#						$combinedResource = [PSCustomObject]@{
#							Timestamp			  = $timeStamp
#							ResourceGroupName	  = $resourceGroup.Name
#							ResourceGroupLocation = $resourceGroup.Location
#							ResourceGroupTags	  = $resourceGroup.Tags
#							ResourceId		      = $resource.Id
#							ResourceName		  = $resource.Name
#							ResourceType		  = $resource.Type
#							ResourceLocation	  = $resource.Location
#							ResourceSKU		      = $resourceDetails.Sku
#							ResProperties		  = $resourceDetails.Properties
#							ResourceTags		  = $resource.Tags
#						}
#						### Using the API
						Write-log -toConsole $Details -id 100 -msg "Checking for a unique value: $($resource.ResourceName)"
#						Write-log -toConsole $Details -id 100 -msg "Checking for a unique value: $($resource.Name)"
						if (Is-Unique -inRow $combinedResource) {
							Write-log -toConsole $Details -id 106 -msg "Unique Record Found. Adding it to the output."
							Write-log -toConsole $Details -id 106 -msg "Resource Record: $($combinedResource)"
							
							# Add the combined object to the array
							Try {
								$combinedResources.add($combinedResource)
							} catch {
								Write-log -toConsole $Details -id 107 -msg "Error Encountered: $($_)"
								Write-log -toConsole $Details -id 107 -msg "Exception: $($_.Exception)"
							}
							
							# Convert the combined resources array to JSON
							$combinedResourcesJson = $combinedResources | ConvertTo-Json -Depth 50
#							Write-log -toConsole $Details -id 107 -msg "Resource JSON Record: $($combinedResourcesJson)"
							
							# Export the Resource result to the JSON file
							try {
								Set-Content -Path "$($inDir)\output.tmp" -Value $combinedResourcesJson
							} catch {
								Write-log -toConsole $Details -id 108 -msg "Error writing Combined Resources JSON to the output.tmp file."
							}
							# Wait a second
							Start-Sleep -Seconds 1
							
							# Increment the resource counter
							$script:cntRecords++
							### Using the API
							#Write-Stats -groupName $resourceGroup.ResourceGroupName -groupResCount $resourceGroup.Count
							Write-Stats -groupName $resourceGroup.Name -groupResCount $resourceGroup.Count
						} else {
							### Using the API
							#Write-log -toConsole $Details -id 59 -msg "Record already exists for the resource: $($resource.ResourceName)"
							Write-log -toConsole $Details -id 59 -msg "Record already exists for the resource: $($resource.Name)"
						}
						
					} catch {
						if (($_.Exception -Match "authentication unavailable") -or ($_.Exception -Match "does not have authorization")) {
							Show-Error -err "Auth" -id 13
						} else {
							Show-Error -err $_ -id 13
						}
					}
				}
			}
		}
		while ([System.IO.File]::Exists("$($inDir)\FlagFile.chk"))
	
	$retVal = $true
		
	} catch {
		Show-Error -err $_ -id 7
		
	}
	
	return $retVal
}

function Show-Results {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$inDir,
		[Parameter(Mandatory = $true)]
		[string]$inFilename
	)
	
	#####################################
	# Determine the record counts
	#####################################
	
	# Read the JSON file (replace 'path/to/your/file.json' with the actual file path)
	$jsonContent = Get-Content -Path "$($inDir)\output.tmp" | Out-String
	
	# Convert JSON to objects
	$resourceObjects = $jsonContent | ConvertFrom-Json
	
	# Initialize an empty hashtable to store unique resource group names and unique resources
	$uniqueResourceGroups = @{ }
	$uniqueResources = @{ }
	
	# Loop through the resource objects
	foreach ($resource in $resourceObjects.Resources) {
		# Extract resource group name
		$resourceGroupName = $resource.ResourceGroupName
		$resourceName = $resource.Name
		
		# Add the resource group name to the hashtable (if not already added)
		if (-not [string]::IsNullOrEmpty($resourceGroupName)) {
			if (-not $uniqueResourceGroups.ContainsKey($resourceGroupName)) {
				$uniqueResourceGroups[$resourceGroupName] = $true
			}
		}
		
		# Add the resource to the hashtable (if not already added)
		if (-not [string]::IsNullOrEmpty($resourceName)) {
			if (-not $uniqueResources.ContainsKey($resourceName)) {
				$uniqueResources[$resourceName] = $true
			}
		}
	}
	
	# Count unique resource groups and unique resources
	$uniqueResourceGroupCount = $uniqueResourceGroups.Count
	$uniqueResourcesCount = $uniqueResources.Count
	
	# Set the End Time
	$endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	
	# Convert start and end times to datetime objects
	$start = [datetime]::ParseExact($startTime, "yyyy-MM-dd HH:mm:ss", $null)
	$end = [datetime]::ParseExact($endTime, "yyyy-MM-dd HH:mm:ss", $null)
	
	# Calculate the duration
	$dur = $end - $start
	
	#####################################
	# Display the results and statistics
	#####################################
	
	# output the count records
	$msg = @"

#####################################
# Processed Records                 #
#-----------------------------------#
# Total Number of passes:     $($script:cntPass)
# Total records examined:     $($script:cntRecords)
# Count of Unique Groups:     $($uniqueResourceGroupCount)
# Count of Unique Resources:  $($uniqueResourcesCount)
#####################################

Start Time:     $($startTime)
End Time:       $($endTime)
Total Duration: $($dur.Hours):$($dur.Minutes):$($dur.Seconds)

Full Resource Scrape file:    $($inDir)\$($inFilename)

*NOTE: The Full Resource Scrape File may contain duplicate resources if the resource is modified during the lab.

#####################################
The get-ResourceScrape.ps1 utility has ended
	
"@
	
	Write-log -toConsole $Details -id 55 -msg $msg
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
# This script requires -Module Az

# Script Version
$myVer = "1.1.8"

# Default the Verbosity of messages to NOT
if ([string]::IsNullOrEmpty($Details)) { $Details = $false }

# Set the Start Time
$startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$timeId = Get-Date -Format "yyyyMMddHHmmss"

# Get subscription ID numeric Digits
$numDigits = $Username -replace '\D', ''

# Get the script directory
#$scriptDir = $PSScriptRoot
#$scriptDir = (Get-Location).Path
$scriptDir = Get-ScriptDirectory

# Set up the output directory
if ([string]::IsNullOrEmpty($OutPath)) {
	$outDir = "$($scriptDir)\output_$($numDigits)"
} else {
	$outDir = "$($OutPath)"
}

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $outDir -PathType Container)) {
	New-Item -ItemType Directory -Force -Path $outDir
}

# Define the log file name
$log = "$($outDir)\resourceScrape"
if ($Stamp) { $log = "$($log)_$($timeId)" }
$log = "$($log).log"

# Initialize an array to hold the combined resource data
$combinedResources = New-Object -TypeName System.Collections.ArrayList

# Write the program version to the log file/screen
Write-log -toConsole $Details -id 55 -msg "get-ResourceScrape.ps1 Version: $($myVer)"

Write-log -toConsole $Details -id 101 -msg "Subscription: $($SubscriptionId)"
Write-log -toConsole $Details -id 101 -msg "Username:     $($Username)"
Write-log -toConsole $Details -id 101 -msg "Password:     $($Password)"
Write-log -toConsole $Details -id 101 -msg "TAP Token:    $($TAPToken)"
Write-log -toConsole $Details -id 101 -msg "Out Path:     $($OutPath)"
Write-log -toConsole $Details -id 101 -msg "Details:      $($Details)"
Write-log -toConsole $Details -id 101 -msg "Timestamp:    $($Stamp)"

if (Set-Environment -inDir $scriptDir) {
	if (Access-AzAccount -inUser $Username -inPswd $Password -inTAP $TAPToken -inSubs $SubscriptionId) {
		Write-log -toConsole $Details -id 61 -msg "Successfully logged in."
		# Initialize the Counters
		$script:cntPass = 0
		$script:cntRecords = 0
		$script:maxGroups = 0
		$script:maxResources = 0
		
		# Create the working files
		Create-TempFiles -inDir $outDir
		
		if (Run-Scrape -inDir $outDir) {
			# Create a copy of the temporary file with the current date & time
			$fileNameDate = "resourceScrape_$($timeId).json"
			Copy-Item -Path "$($outDir)\output.tmp" -Destination "$($outDir)\$($fileNameDate)"
			
			Show-Results -inDir "$($outDir)" -inFilename "$($fileNameDate)"
		} else {
			$errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			Write-log -toConsole $Details -id 56 -msg "An error was encountered during the Resource Scrape process."
		}
	}
}
