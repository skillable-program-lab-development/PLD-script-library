<#
	.SYNOPSIS
		Add a folder of images to Skillable Studio Lab Profile Instructions 
	
	.DESCRIPTION
		Add all images from a folder to a Lab Profile
	
	.PARAMETER LabProfile
		A description of the LabProfile parameter.
	
	.PARAMETER ImageFolder
		A description of the ImageFolder parameter.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2025 v5.9.261
		Created on:   	3/12/2026 2:27 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	add-images.ps1
		===========================================================================
#>
param
(
	[Parameter(Mandatory = $true)]
	[int]$LabProfile,
	[Parameter(Mandatory = $true)]
	[int]$InstSetId,
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[string]$ImageFolder
)

# #####################################################
# M A I N L I N E
# #####################################################

# Validate that the ImageFolder exists and is a directory
if (-not (Test-Path -Path $ImageFolder -PathType Container)) {
	Write-Error "The ImageFolder path $($ImageFolder) is not a valid directory."
	exit 1
}

# Get image files from the folder
# Adjust extensions here if needed

$imageFiles = Get-ChildItem -Path "$($ImageFolder)" -File | Where-Object { $_.Extension -match '\.(png|jpg|jpeg|bmp|gif)$' }

#$imageFiles = Get-ChildItem -Path "$($ImageFolder)" -File -Include *.png, *.jpg, *.jpeg, *.bmp, *.gif

if ($imageFiles.Count -eq 0) {
	Write-Warning "No image files found in '$ImageFolder'."
	exit 0
}

# Log in to Skillable Studio
try {
	Write-Output "Attempting to log in to Skillable Studio"
	if (-not $global:LODSessionToken) {
		Connect-LabOnDemand -ERRORAction 'Continue'
		Set-Variable -Name 'LODSessionToken' -Value $(Get-LODSessionToken) -Force -Option AllScope -Scope Global
	} else {
		Connect-LabOnDemand -SessionToken $global:LODSessionToken -ErrorAction Continue
	}
	
	Write-Output "  Login Successful"
	
} catch {
	Write-Output "  FAILED TO CONNECT"
	Write-Output "    Details: $($_.Exception.Message)"
	exit 1
}

$x = 0
$y = 0
foreach ($image in $imageFiles) {
	$x++
	
	# Set the ImageFile variable to full path + filename
	$ImageFile = $image.FullName
	
	try {
		# Run the custom command
		$result = Add-LODLabProfileInstructionsFile -LabProfileId $LabProfile -InstructionsSetId $InstSetId -FileName $ImageFile -Overwrite -ErrorAction Stop
		
		# If the command did not throw, treat as success
		Write-Output "SUCCESS: $($x): Uploaded '$ImageFile'" -ForegroundColor Green
	} catch {
		Write-Output "FAILURE: $($x): Could not upload '$ImageFile'" -ForegroundColor Red
		Write-Output "  Error: $($_.Exception.Message)" -ForegroundColor Red
		$y++
	}
}

# End Run
Write-Output "Completed importing images"
Write-Output "--------------------------"
Write-Output " Total Images:   $($x)"
Write-Output " Total Failures: $($y)"
Write-Output ""
Write-Output " Lab Profile:    $($LabProfile)"
Write-Output " Inst Set ID:    $($InstSetId)"
Write-Output ""
Write-Output "NOTE: You will have to update the image path in the Lab Instructions to point to the correct Snstructions Set"