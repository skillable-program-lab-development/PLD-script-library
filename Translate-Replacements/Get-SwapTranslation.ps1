<#
	.SYNOPSIS
		Locates a phrase in an English instructions string and finds its corresponding
		translation in a second-language instructions string, using an AI model to
		identify the translated phrase and deterministic regex matching to count/locate it.
	
	.DESCRIPTION
		Given two large strings (English source, translated target - language unspecified
		and unknown ahead of time), this script:
		1. Finds every occurrence of -SearchPhrase in -EnglishText (regex, respects -CaseSensitive).
		2. If none found, returns immediately - no AI call is made.
		3. Builds a context window around each occurrence and sends ALL of them, together,
		in a single prompt to the specified AI model, asking it to return the exact
		translated phrase as it verbatim appears in -TranslatedText.
		4. Takes that returned phrase and does a deterministic, case-sensitive exact-match
		regex search against -TranslatedText to get the real count and line numbers.
		The AI is used only to identify *what* the translation is; counting and locating
		are always done by the script, not trusted to the model's output.
		
		Only one AI call is made per run, regardless of how many times the phrase occurs
		in the English text.
	
	.PARAMETER EnglishText
		The full English instructions content.
	
	.PARAMETER TranslatedText
		The full translated instructions content (language unknown/unspecified - may be
		Spanish, German, French, Arabic, Portuguese, Japanese, Simplified Chinese,
		Traditional Chinese, Korean, Italian, etc.).
	
	.PARAMETER SearchPhrase
		The English phrase to search for.
	
	.PARAMETER CaseSensitive
		Whether the search of -EnglishText is case sensitive. Default is case-insensitive.
	
	.PARAMETER Model
		The AI model name to pass to the Claude Code CLI (e.g. "claude-sonnet-4-6").
	
	.PARAMETER ContextChars
		Number of characters of context to capture before/after each occurrence when
		building the prompt to the AI model. Default 400.
	
	.OUTPUTS
		PSCustomObject with:
		SearchPhrase, CaseSensitive, Status, Message, ErrorMessage,
		TranslatedPhrase, SourceOccurrenceCount, TranslationOccurrenceCount,
		SourceLines (int[]), TranslationLines (int[])
		
		Status is one of: Found, NotFoundInSource, NotFoundInTranslation, Error
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2026 v5.10.272
		Created on:   	9/14/2026 11:05 AM
		Created by:   	WayneKlapwyk
		Organization: 	WKUtil
		Filename:     	Get-SwapTranslation.ps1
		===========================================================================
#>
[CmdletBinding()]
param
(
	[Parameter(Mandatory = $true)]
	[string]$EnglishText,
	[Parameter(Mandatory = $true)]
	[string]$TranslatedText,
	[Parameter(Mandatory = $true)]
	[string]$SearchPhrase,
	[switch]$CaseSensitive,
	[Parameter(Mandatory = $true)]
	[string]$Model,
	[int]$ContextChars = 400
)

function Get-LineStarts {
    <# Returns a sorted int[] of the character index where each line begins (0-based). #>
	param ([Parameter(Mandatory)]
		[string]$Text)
	
	$starts = [System.Collections.Generic.List[int]]::new()
	$starts.Add(0)
	foreach ($m in [regex]::Matches($Text, "`n")) {
		$starts.Add($m.Index + 1)
	}
	return ,$starts.ToArray()
}

function Get-LineNumberForIndex {
    <# Binary search: 1-based line number containing character $Index. #>
	param (
		[Parameter(Mandatory)]
		[int[]]$LineStarts,
		[Parameter(Mandatory)]
		[int]$Index
	)
	$lo = 0
	$hi = $LineStarts.Length - 1
	while ($lo -lt $hi) {
		$mid = [int][math]::Ceiling(($lo + $hi) / 2.0)
		if ($LineStarts[$mid] -le $Index) {
			$lo = $mid
		} else {
			$hi = $mid - 1
		}
	}
	return $lo + 1
}

function Find-PhraseOccurrences {
    <# Returns occurrence objects (Index, Length, Value, Line) for exact/regex phrase matches. #>
	param (
		[Parameter(Mandatory)]
		[string]$Text,
		[Parameter(Mandatory)]
		[string]$Phrase,
		[bool]$CaseSensitive,
		[Parameter(Mandatory)]
		[int[]]$LineStarts
	)
	$opts = [Text.RegularExpressions.RegexOptions]::None
	if (-not $CaseSensitive) {
		$opts = [Text.RegularExpressions.RegexOptions]::IgnoreCase
	}
	
	$pattern = [regex]::Escape($Phrase)
	$regex = [regex]::new($pattern, $opts)
	
	$results = New-Object System.Collections.Generic.List[object]
	foreach ($m in $regex.Matches($Text)) {
		$results.Add([PSCustomObject]@{
				Index  = $m.Index
				Length = $m.Length
				Value  = $m.Value
				Line   = Get-LineNumberForIndex -LineStarts $LineStarts -Index $m.Index
			})
	}
	return ,$results
}

function Get-ContextWindow {
	param (
		[Parameter(Mandatory)]
		[string]$Text,
		[Parameter(Mandatory)]
		[int]$Index,
		[Parameter(Mandatory)]
		[int]$Length,
		[int]$ContextChars = 400
	)
	$start = [math]::Max(0, $Index - $ContextChars)
	$end = [math]::Min($Text.Length, $Index + $Length + $ContextChars)
	return $Text.Substring($start, $end - $start)
}

function Get-BalancedJsonObject {
    <#
    Extracts the first balanced {...} JSON object from a string, ignoring any text before
    or after it (Claude Code CLI can emit diagnostic/MCP noise alongside the JSON result).
    Brace-counting is string-aware so braces inside quoted values don't confuse it.
    #>
	param ([Parameter(Mandatory)]
		[string]$Text)
	
	$start = $Text.IndexOf('{')
	if ($start -lt 0) {
		return $null
	}
	
	$depth = 0
	$inString = $false
	$escaped = $false
	for ($i = $start; $i -lt $Text.Length; $i++) {
		$ch = $Text[$i]
		if ($inString) {
			if ($escaped) {
				$escaped = $false
			} elseif ($ch -eq '\') {
				$escaped = $true
			} elseif ($ch -eq '"') {
				$inString = $false
			}
			continue
		}
		switch ($ch) {
			'"' {
				$inString = $true
			}
			'{' {
				$depth++
			}
			'}' {
				$depth--
				if ($depth -eq 0) {
					return $Text.Substring($start, $i - $start + 1)
				}
			}
		}
	}
	return $null
}

function Out-Occurrences {
	param
	(
		$Occurrences
	)
	
	$ret = 0
	
	if ($Occurrences.Count -gt 0) {
		try {
			$ret = ($Occurrences | Select-Object -ExpandProperty Line) -join ','
		} catch {
			$ret = 0
		}
	}
	
	return $ret
}

function Invoke-ClaudeHeadless {
    <# Sends $Prompt to Claude Code CLI in headless print mode via a redirected input file,
       returns raw stdout+stderr text read back from a redirected output file. #>
	param (
		[Parameter(Mandatory)]
		[string]$Prompt,
		[Parameter(Mandatory)]
		[string]$Model
	)
	$tempFile = [System.IO.Path]::GetTempFileName()
	$mcpConfigFile = [System.IO.Path]::GetTempFileName()
	$outFile = [System.IO.Path]::GetTempFileName()
	
	try {
		$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
		[System.IO.File]::WriteAllText($tempFile, $Prompt, $utf8NoBom)
		[System.IO.File]::WriteAllText($mcpConfigFile, '{"mcpServers":{}}', $utf8NoBom)
		
		# cmd.exe's own < and > file redirection operates at the OS file-handle level -
		# raw bytes in, raw bytes out - with no PowerShell pipeline marshaling and no
		# dependence on $OutputEncoding, [Console]::OutputEncoding, or
		# StandardInput/StandardOutput property access (all of which have failed above:
		# codepage mangling, missing StandardInputEncoding in .NET Framework, and a
		# console-handle exception in hosts like ISE). This also avoids the
		# "process has exited" race from accessing StandardInput after a fast process exit.
		$cmdLine = "/c claude -p --model $Model --output-format json --strict-mcp-config --mcp-config `"$mcpConfigFile`" -- < `"$tempFile`" > `"$outFile`" 2>&1"
		
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = 'cmd.exe'
		$psi.Arguments = $cmdLine
		$psi.UseShellExecute = $false
		$psi.CreateNoWindow = $true
		
		$process = [System.Diagnostics.Process]::Start($psi)
		$process.WaitForExit()
		
		return [System.IO.File]::ReadAllText($outFile, [System.Text.Encoding]::UTF8)
	} catch {
		# Deliberately avoiding string interpolation with nested subexpressions here,
		# in case that was masking the real exception in the previous attempts.
		$errType = $_.Exception.GetType().FullName
		$errMsg = $_.Exception.Message
		return 'SCRIPT-LEVEL ERROR: ' + $errType + ': ' + $errMsg
	} finally {
		Remove-Item -Path $tempFile, $mcpConfigFile, $outFile -Force -ErrorAction SilentlyContinue
	}
}

function Claude-Login {
	try {
		claude auth login
		Set-Content -Path "cCheck.dte" -Value Get-Date
	} catch {
		Write-Host "This utility requires the use of Claude Code and requires a Claude Pro/Max subscription or an Anthropic Console account with active billing."
		Write-Host "  Error: $($_.Exception.Message)"
		if ($_.Exception.Message -like "*not recognized*") {
			Write-Host "  Install the Claude CLI using:"
			Write-Host "    irm https://claude.ai/install.ps1 | iex"
			Write-Host "  OR"
			Write-Host "    winget install Anthropic.ClaudeCode"
		}
		throw $_.Exception
	}
}

function New-Result {
	param (
		[string]$Status,
		[string]$Message = $null,
		[string]$ErrorMessage = $null,
		[string]$TranslatedPhrase = $null,
		[int]$SourceOccurrenceCount = 0,
		[int]$TranslationOccurrenceCount = 0,
		[string]$SourceLines = $null,
		[string]$TranslationLines = $null
	)
	
	return [PSCustomObject]@{
		SearchPhrase  = $SearchPhrase
		CaseSensitive = [bool]$CaseSensitive
		Status	      = $Status
		Message	      = $Message
		ErrorMessage  = $ErrorMessage
		TranslatedPhrase = $TranslatedPhrase
		SourceOccurrenceCount = $SourceOccurrenceCount
		TranslationOccurrenceCount = $TranslationOccurrenceCount
		SourceLines   = $SourceLines
		TranslationLines = $TranslationLines
	}
}

# ---------------------------------------------------------------------------

# Get the Claude login status
$sts = (claude auth status) | convertfrom-json
if (-not $sts.loggedIn) {
	# Connect to Claude if required
	Write-Host "Attempting to Log In to Claude Code"
	try{
		Claude-Login
		$sts = (claude auth status) | convertfrom-json
		Write-Host "  Successfully logged in to Claude Code as $($sts.email) with a $($sts.subscriptionType) subscription."
		if ($sts.subscriptionType -eq "free") {
			return New-Result -Status 'Error' -ErrorMessage "The Get-SwapTranslation.ps1 script requires a Claude Code paid account."
		}
	} catch {
		return New-Result -Status 'Error' -ErrorMessage $_.Exception.Message
	}
} else {
	Write-Host "Currently logged in to Claude Code as $($sts.email) with a $($sts.subscriptionType) subscription."
	if ($sts.subscriptionType -eq "free") {
		return New-Result -Status 'Error' -ErrorMessage "The Get-SwapTranslation.ps1 script requires a Claude Code paid account."
	}
}

try {
	if (Test-Path -Path $EnglishText) {
		$EnglishText = Get-Content -Path $EnglishText -Encoding UTF8 -Raw
	}
	
	if (Test-Path -Path $TranslatedText) {
		$TranslatedText = Get-Content -Path $TranslatedText -Encoding UTF8 -Raw
	}
	
	if ([string]::IsNullOrWhiteSpace($SearchPhrase)) {
		return New-Result -Status 'Error' -ErrorMessage 'SearchPhrase cannot be empty.'
	}
	
	$sourceLineStarts = Get-LineStarts -Text $EnglishText
	$sourceOccurrences = Find-PhraseOccurrences -Text $EnglishText -Phrase $SearchPhrase `
												-CaseSensitive:([bool]$CaseSensitive) -LineStarts $sourceLineStarts
	$srcOccurrences = Out-Occurrences -Occurrences $sourceOccurrences
	
#	if ((-not $sourceOccurrences) -or ($sourceOccurrences.Count -eq 0)) {
	if ((-not $srcOccurrences) -or ($srcOccurrences -eq 0)) {
		return New-Result -Status 'NotFoundInSource' `
						  -Message "The phrase '$SearchPhrase' was not found in the English (source) string."
	}
	
	# Build one prompt covering every occurrence's context - single AI call regardless of count.
	$contextBlocks = for ($i = 0; $i -lt $sourceOccurrences.Count; $i++) {
		$occ = $sourceOccurrences[$i]
		$window = Get-ContextWindow -Text $EnglishText -Index $occ.Index -Length $occ.Length -ContextChars $ContextChars
		"Occurrence $($i + 1) (source line $($occ.Line)):`n---`n$window`n---"
	}
	$contextText = $contextBlocks -join "`n`n"
	
	$prompt = @"
You are matching a phrase between two documents that contain the same content in
different languages. The first document is in English. The second document is a
translation into an unspecified language (it may be Spanish, German, French, Arabic,
Portuguese, Japanese, Simplified Chinese, Traditional Chinese, Korean, Italian, or
another language - determine it from the text itself).

The English phrase to match is:
"$($SearchPhrase)"

Below are one or more excerpts from the English document, each showing the phrase
in its surrounding context. The same context (by meaning and relative position)
should exist in the translated document below that.

"$($contextText)"

TRANSLATED DOCUMENT:
---
"$($TranslatedText)"
---

Find the phrase in the translated document that corresponds to <the value of the English phrase to match>,
using the surrounding context to locate the correct spot. Respond with ONLY a raw
JSON object (no markdown fences, no commentary) in exactly this shape:

{"found": true, "originalPhrase": "<the value of the English phrase to match>", "translatedPhrase": "<the exact substring exactly as it appears in the translated document>"}

or, if no corresponding phrase can be located in the translated document:

{"found": false, "originalPhrase": "<the value of the English phrase to match>", "translatedPhrase": null}

If you cannot confidently identify a translated phrase, you MUST return {"found": false, "originalPhrase": "<the value of the English phrase to match>", "translatedPhrase": null} - never return the original English phrase as the translatedPhrase value.

The "translatedPhrase" value must be copied verbatim from the translated document -
do not paraphrase, retranslate, or alter punctuation/spacing. The value returned should
match the value found in the "TRANSLATED DOCUMENT" without any modification.
"@
	
	$rawOutput = Invoke-ClaudeHeadless -Prompt $prompt -Model $Model
	$jsonText = Get-BalancedJsonObject -Text $rawOutput
	
	if (-not $jsonText) {
		return New-Result -Status 'Error' `
						  -ErrorMessage "AI model call returned no parseable JSON. Raw output: $rawOutput" `
						  -SourceOccurrenceCount $sourceOccurrences.Count `
						  -SourceLines $srcOccurrences
#						  -SourceLines ($sourceOccurrences.Line)
	}
	
	$envelope = $jsonText | ConvertFrom-Json
	
	# CLI may wrap the model's answer in a result envelope; unwrap if present.
	$payloadText = $null
	if ($envelope.PSObject.Properties.Name -contains 'result' -and $envelope.result -is [string]) {
		$payloadText = Get-BalancedJsonObject -Text $envelope.result
	}
	$payload = if ($payloadText) {
		$payloadText | ConvertFrom-Json
	} else {
		$envelope
	}
	
	if (-not $payload.found -or [string]::IsNullOrWhiteSpace($payload.translatedPhrase)) {
		return New-Result -Status 'NotFoundInTranslation' `
						  -Message "The phrase '$SearchPhrase' was found $($sourceOccurrences.Count) time(s) in the source string, but no corresponding translation could be located in the translated string." `
						  -SourceOccurrenceCount $sourceOccurrences.Count `
						  -SourceLines $srcOccurrences
#						  -SourceLines ($sourceOccurrences.Line)
	}
	
	$translatedPhrase = [string]$payload.translatedPhrase
	
	# Deterministic verification: count/locate the returned phrase ourselves, never trust the
	# model's own counting. Exact-match (case-sensitive) since it's a specific quoted translation.
	$targetLineStarts = Get-LineStarts -Text $TranslatedText
	$targetOccurrences = Find-PhraseOccurrences -Text $TranslatedText -Phrase $translatedPhrase `
												-CaseSensitive:$true -LineStarts $targetLineStarts
	
	$trgOccurrences = 0
	if ($targetOccurrences.Count -gt 0) {
		# Fallback: retry with whitespace normalized, in case of trivial spacing drift.
		$normalizedPhrase = ($translatedPhrase -replace '\s+', ' ').Trim()
		$targetOccurrences = Find-PhraseOccurrences -Text $TranslatedText -Phrase $normalizedPhrase `
													-CaseSensitive:$true -LineStarts $targetLineStarts
		$trgOccurrences = Out-Occurrences -Occurrences $targetOccurrences
	}
	
#	if ($sourceOccurrences.Count -gt 0) {
#		try {
#			$sOccurrences = ($sourceOccurrences | Select-Object -ExpandProperty Line) -join ','
#		} catch {
#			$sOccurrences = 0
#		}
#	} else {
#		$sOccurrences = 0
#	}
	
#	if ($targetOccurrences.Count -gt 0) {
#		try {
#			$tOccurrences = ($targetOccurrences | Select-Object -ExpandProperty Line) -join ','
#		} catch {
#			$tOccurrences = 0
#		}
#	} else {
#		$tOccurrences = 0
#	}
	
	#	if ($targetOccurrences.Count -eq 0) {
#		return New-Result -Status 'NotFoundInTranslation' `
#						  -Message "The AI model identified a translated phrase ('$translatedPhrase'), but it could not be verified with an exact match in the translated string." `
#						  -TranslatedPhrase $translatedPhrase `
#						  -SourceOccurrenceCount $sourceOccurrences.Count `
#						  -SourceLines $sOccurrences
#	}
	
	return New-Result -Status 'Found' `
					  -TranslatedPhrase $translatedPhrase `
					  -SourceOccurrenceCount $sourceOccurrences.Count `
					  -TranslationOccurrenceCount $targetOccurrences.Count `
					  -SourceLines $srcOccurrences `
					  -TranslationLines $trgOccurrences
#					  -SourceLines $sOccurrences `
#					  -TranslationLines $tOccurrences
} catch {
	return New-Result -Status 'Error' -ErrorMessage $_.Exception.Message
}

