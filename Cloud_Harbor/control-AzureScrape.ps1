<#
	.SYNOPSIS
		Tie the get-ResourceScrape.ps1 and process-ResourceScrape.ps1 utilities together
	
	.DESCRIPTION
		This script will accept the subscriptionId, username and password parameters
		and pass them to the get-ResourceScrape.ps1 utility. It will then monitor for
		creation of the Resource Scrape file. Once detected, this script will launch
		the process-ResourceScrape.ps1 utility. Once again, it will monitor for the
		creation of the HTML and ACP files. Once detected, this script will zip all
		the created files into a single compressed file for download by the Jenkins
		automation framework.
	
	.PARAMETER SubscriptionId
		Provide the Azure Subscription ID in the format "yyyy-yyyy-yyyy-yyyy"
	
	.PARAMETER Username
		Provide the Azure Subscription username
	
	.PARAMETER Password
		Provide the Azure Subscription password
	
	.PARAMETER Details
		Show the messages to the console
	
	.PARAMETER Stamp
		Attach the datetime stamp to the output folder and some files
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2023 v5.8.232
		Created on:   	5/7/2024 5:12 PM
		Created by:   	Wayne Klapwyk
		Organization: 	Skillable
		Filename:     	control-AzureScrape
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
	[Parameter(Mandatory = $true)]
	[Alias('p')]
	[string]$Password,
	[Parameter(HelpMessage = 'Path to output files')]
	[Alias('o')]
	[string]$OutPath,
	[Parameter(HelpMessage = 'Show the messages to the console')]
	[Alias('d')]
	[bool]$Details = $false,
	[Parameter(HelpMessage = 'Attach the datetime stamp to the output folder and some files')]
	[Alias('s')]
	[switch]$Stamp
)

<#
	.DESCRIPTION
		Ensure that the Az (Azure) powershell module is installed and available in the environment
	
	.EXAMPLE
				PS C:\> Set-Environment
	
	.NOTES
#>

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
	
	# Write the message to the log file
	Write-Output "$($dte) (id:$($id)) [ctrl] $($msg)" | Out-file $log -append
	
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
	
	$errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$e = $err.Exception
	$msg = $e.Message
	while ($e.InnerException) {
		$e = $e.InnerException
		$msg += "`n" + $e.Message
	}
	Write-log -toConsole $Verbose -id $id -msg "Error $($err.Exception.HResult): $($err.Message)`n  Full Message: $($msg)"
}

#####################################
# M A I N  L I N E
#####################################

# Create the Jenkins Status file
$file = New-Item -Path "$($outDir)\accepted.log" -ItemType File -Force

# Script Version
$myVer = "0.0.1"

# Default the Verbosity of messages to NOT
if ([string]::IsNullOrEmpty($Details)) { $Details = $false }

# Set the Start Time
$startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$timeId = Get-Date -Format "yyyyMMddHHmmss"

# Get subscription ID numeric Digits
$numDigits = $Username -replace '\D', ''

# Get the script directory
$scriptDir = $PSScriptRoot

# Set up the output directory
if ([string]::IsNullOrEmpty($OutPath)) {
	$outDir = "$($scriptDir)\output_$($numDigits)"
} else {
	$outDir = "$($OutPath)"
}

# Add the Time ID if requested
if ($Stamp) { $outDir = "$($outDir)_$($timeId)" }

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $outDir -PathType Container)) {
	New-Item -ItemType Directory -Force -Path $outDir
}

# Define the log file name
$log = "$($outDir)\resourceControl"
if ($Stamp) { $log = "$($log)_$($timeId)" }
$log = "$($log).log"

# Write the program version to the log file/screen
Write-log -toConsole $Details -id 125 -msg "control-AzureScrape.ps1 Version: $($myVer)"

# Create the Control File to help determine if the resource scrape completed successfully
$file = New-Item -Path "$($outDir)\ControlFile.chk" -ItemType File -Force

# Define the argument list to pass to the get-ResourceScrape.ps1 utility
#$argList = "-i `"$($SubscriptionId)`" -u `"$($Username)`" -p `"$($Password)`" -o `"$($outDir)`" -d $false"
$argList = "-i `"$($SubscriptionId)`" -u `"$($Username)`" -p `"$($Password)`" -o `"$($outDir)`" -d"

# Create the Jenkins In Progress Status file
$file = New-Item -Path "$($outDir)\started.log" -ItemType File -Force

# Launch the get-ResourceScrape.ps1 utility
Write-log -toConsole $Details -id 126 -msg "Launching the get-ResourceScrape.ps1 utility"
Invoke-Expression "& `".\get-ResourceScrape.ps1`" $argList"

# Wait for the get-ResourceScrape.ps1 utility to create all the appropriate files
$cntFiles = 0
$cntFiles = (Get-ChildItem -Path "$($outDir)" -File -Filter "resourcescrape_*.json" | Measure-Object).Count
if ($cntFiles -gt 0) {
	$fileResourceScrape = Get-ChildItem -Path "$($outDir)" -File -Filter "resourcescrape_*.json"
}

if (($cntFiles -lt 1) -and (Test-Path -Path "$($outDir)\FlagFile.chk" -PathType Leaf)) {
	# Create the Jenkins Cancelled Status file
	$file = New-Item -Path "$($outDir)\cancelled.log" -ItemType File -Force
	
	# The get-ResourceScrape.ps1 utility did not complete successfully
	Write-log -toConsole $Details -id 101 -msg "The get-ResourceScrape.ps1 utility has NOT completed successfully."
	Write-log -toConsole $Details -id 102 -msg "Skipping execution of the processing utility."
	
} elseif (($cntFiles -lt 1) -and (-not (Test-Path -Path "$($outDir)\FlagFile.chk" -PathType Leaf))) {
	# Create the Jenkins Failed Status file
	$file = New-Item -Path "$($outDir)\failed.log" -ItemType File -Force
	
	# The get-ResourceScrape.ps1 utility did not complete successfully
	Write-log -toConsole $Details -id 134 -msg "The get-ResourceScrape.ps1 utility has FAILED."
	Write-log -toConsole $Details -id 135 -msg "Skipping execution of the processing utility."

} else {
	# Create the Jenkins Partial Success Status file
	$file = New-Item -Path "$($outDir)\partial.log" -ItemType File -Force
	
	# The get-ResourceScrape.ps1 utility completed
	Write-log -toConsole $Details -id 127 -msg "The get-ResourceScrape.ps1 utility has completed successfully."
	
	# Create a compressed file with the ResourceScrape JSON file
	$zipFile = "$($outDir)\resources"
	if ($Stamp) { $zipFile = "$($zipFile)_$($timeId)" }
	$zipFile = "$($zipFile).zip"
	Write-log -toConsole $Details -id 132 -msg "Creating the final ZIP file: $($zipFile)"
	Write-log -toConsole $Details -id 133 -msg "Adding the Resource Scrape to the final ZIP file."
	$compress = @{
		Path = "$($outDir)\$($fileResourceScrape)"
		CompressionLevel = "Optimal"
		DestinationPath = "$($zipFile)"
	}
	Compress-Archive @compress
	
	# Define the argument list to pass to the process-ResourceScrape.ps1 utility
	$argList = "-f `"$($outDir)\$($fileResourceScrape)`" -o `"$($outDir)`" -d $false"
	
	# Launch the process-ResourceScrape.ps1 utility
	Write-log -toConsole $Details -id 128 -msg "The get-ResourceScrape.ps1 utility has completed."
	Write-log -toConsole $Details -id 129 -msg "Launching the process-ResourceScrape.ps1 utility"
	Invoke-Expression "& `".\process-ResourceScrape.ps1`" $argList"
	
	# Wait for the get-ResourceScrape.ps1 utility to create all the appropriate files
	$cntFiles = 0
	$cntFiles = (Get-ChildItem -Path "$($outDir)" -File -Filter "resourcescrape_*.html" | Measure-Object).Count
	$cntFiles = $cntFiles + (Get-ChildItem -Path "$($outDir)" -File -Filter "initialACP*.json" | Measure-Object).Count
	if ($cntFiles -gt 1) {
		$fileResourceReport = Get-ChildItem -Path "$($outDir)" -File -Filter "resourcescrape_*.html"
		$fileResourceAcp = Get-ChildItem -Path "$($outDir)" -File -Filter "initialACP_*.json"
	}
		
	# The process-ResourceScrape.ps1 utility completed
	Write-log -toConsole $Details -id 130 -msg "The process-ResourceScrape.ps1 utility has completed successfully."
	
	$compress = @{
		Path			 = "$($outDir)\$($fileResourceReport)", "$($outDir)\$($fileResourceAcp)", "$($outDir)\resourceControl.log", "$($outDir)\resourceProcessor.log", "$($outDir)\resourceScrape.log"
		CompressionLevel = "Optimal"
		DestinationPath  = "$($zipFile)"
	}
	Compress-Archive @compress -Update
	# Add the initial ACP file to the compressed file 
	Write-log -toConsole $Details -id 131 -msg "Adding the HTML report and Initial ACP to the final ZIP file: $($zipFile)"
	Write-log -toConsole $Details -id 136 -msg "control-AzureScrape.ps1 - Ending Processing"
	
	# Create the Jenkins Full Success Status file
	$file = New-Item -Path "$($outDir)\success.log" -ItemType File -Force
}