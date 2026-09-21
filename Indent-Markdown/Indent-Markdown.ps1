<#
	.SYNOPSIS
		Properly indent an existing Markdown file
	
	.DESCRIPTION
		Accept a markdown file and properly indent the lines between Steps. A new file with the "_indented" suffix will be created.
	
	.PARAMETER MarkdownPath
		The path and filename of the file to be indented. This can be drag and dropped onto the Indent-Markdown.cmd file to launch this script
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2025 v5.9.261
		Created on:   	3/17/2026 2:31 PM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtils
		Filename:     	Indent-Markdown.ps1
        Version:        1.0
		===========================================================================
#>

param (
	[Parameter(
			   Mandatory = $true,
			   Position = 0,
			   ValueFromRemainingArguments = $true
			   )]
	[ValidateScript({
			Test-Path $_ -PathType Leaf
		})]
	[string]$MarkdownPath
)


# Resolve paths
$sourceFile = Resolve-Path $MarkdownPath
$directory = Split-Path $sourceFile
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile)
$extension = [System.IO.Path]::GetExtension($sourceFile)

$targetFile = Join-Path $directory "$baseName`_indented$extension"

# UTF8 without BOM (important for markdown / git)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$reader = New-Object System.IO.StreamReader($sourceFile, $utf8NoBom)
$writer = New-Object System.IO.StreamWriter($targetFile, $false, $utf8NoBom)

try {
	$indent = $false
	$cntLine = 0
	
	while (-not $reader.EndOfStream) {
		$line = $reader.ReadLine()
		
		# Blank line → write as-is
		if ([string]::IsNullOrWhiteSpace($line)) {
			$writer.WriteLine($line)
			continue
		}
		
		# Line starts with '#'
		if ($line -match '^\s*#') {
			$indent = $false
			$writer.WriteLine($line)
			continue
		}
		
		# Line starts with number immediately followed by a period (e.g. 1.)
		if ($line -match '^\s*\d+\.') {
			$indent = $true
			$writer.WriteLine($line)
			continue
		}
		
		# Anything else AND indent is TRUE
		if ($indent) {
			$trimmed = $line.TrimStart()
			$writer.WriteLine("    $trimmed")
		} else {
			$writer.WriteLine($line)
		}
		$cntLine++
	}
} finally {
	$reader.Close()
	$writer.Close()
}

Write-Host "Indented file created:`n$targetFile"
Write-Host "Lines Processed: $($cntLine)"


