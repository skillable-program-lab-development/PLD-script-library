<#
	.SYNOPSIS
		Combines the Find-Text_Report*.csv files referenced in Find-Text.psf output into a
		single CSV, then renders that combined CSV as a formatted HTML report.
	
	.DESCRIPTION
		Parses the text captured in $txtOutput.Text for "Report written to: <path>.csv" lines,
		imports every referenced Find-Text_Report*.csv, and merges them. The merge uses the
		union of all columns across all reports (so reports with differing schemas still line
		up) and prepends SourceBlock and SourceReport columns for traceability.
		
		The combined CSV is written first; the HTML report is then generated from that file.
		Missing or unreadable reports are listed in the HTML rather than silently skipped.
	
	.PARAMETER OutputText
		The full text of $txtOutput.Text from Find-Text.psf.
	
	.PARAMETER OutputFolder
		Folder for the combined files. Defaults to the folder of the first report found.
	
	.PARAMETER BaseName
		File name prefix for the combined files. Default: Find-Text_Combined
		(deliberately does not match Find-Text_Report*, so reruns never ingest their own output).
	
	.PARAMETER MatchColumn
		Column holding the match count. Used for row highlighting, the "Rows with matches"
		total and the "Only show matches" filter. Auto-detected when omitted
		(Found / Count / Matches / Occurrences / Hits).
	
	.PARAMETER OpenHtml
		Opens the HTML report in the default browser when finished.
	
	.EXAMPLE
		$result = & .\Merge-FindTextReports.ps1 -OutputText $txtOutput.Text -OpenHtml
	
	.OUTPUTS
		PSCustomObject: CombinedCsv, HtmlReport, ReportCount, RowCount, MatchCount, MissingReports
	
	.NOTES
		Additional information about the file.
#>
[CmdletBinding()]
Param
(
	[Parameter(Mandatory = $true)]
	[AllowEmptyString()]
	[string]$OutputText,
	[string]$OutputFolder,
	[string]$BaseName = 'Find-Text_Combined',
	[string]$MatchColumn,
	[switch]$OpenHtml
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$regexOptions = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, Multiline'

Function ConvertTo-HtmlSafe {
	Param ([AllowNull()]
		[object]$Value)
	If ($null -eq $Value) {
		Return ''
	}
	Return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

Function Get-LogValue {
	# Returns the unique values of "# <Label>: <value>" banner lines in the log.
	Param ([string]$Label)
	$pattern = '#[ \t]*' + [regex]::Escape($Label) + ':[ \t]*(?<V>.+?)[ \t\r]*$'
	@([regex]::Matches($OutputText, $pattern, $regexOptions) |
		ForEach-Object {
			$_.Groups['V'].Value.Trim()
		} |
		Select-Object -Unique)
}

#region Parse the form output for report paths
$reportPattern = '^(?:\[Block[ \t]+(?<Block>\d+)/\d+\][ \t]*)?.*?Report written to:[ \t]*(?<Path>.+?\.csv)[ \t\r]*$'

$seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$reports = New-Object System.Collections.Generic.List[object]

ForEach ($m In [regex]::Matches($OutputText, $reportPattern, $regexOptions)) {
	$path = $m.Groups['Path'].Value.Trim().Trim('"')
	If ((($path -split '[\\/]')[-1]) -notlike 'Find-Text_Report*.csv') {
		Continue
	}
	If (-not $seenPaths.Add($path)) {
		Continue
	}
	
	$block = $null
	If ($m.Groups['Block'].Success) {
		$block = [int]$m.Groups['Block'].Value
	}
	
	$reports.Add([pscustomobject]@{
			Block    = $block
			Path	 = $path
			Status   = 'Pending'
			RowCount = 0
		})
}

If ($reports.Count -eq 0) {
	Write-Warning 'No "Report written to: ...Find-Text_Report*.csv" lines were found in the supplied output.'
	Return
}

$reports = @($reports | Sort-Object -Property @{
		Expression = {
			If ($null -eq $_.Block) {
				[int]::MaxValue
			} Else {
				$_.Block
			}
		}
	}, Path)

# Search parameters echoed in the banner lines (used for the HTML header only)
$findLists = Get-LogValue 'Find List'
$findTypes = Get-LogValue 'Find Type'
$caseTypes = Get-LogValue 'Case Type'
$profileIds = @(Get-LogValue 'Lab Profile List' |
	ForEach-Object {
		$_ -split ','
	} |
	ForEach-Object {
		$_.Trim()
	} |
	Where-Object {
		$_
	} |
	Select-Object -Unique)
$seriesIds = @(Get-LogValue 'Lab Series List' |
	ForEach-Object {
		$_ -split ','
	} |
	ForEach-Object {
		$_.Trim()
	} |
	Where-Object {
		$_
	} |
	Select-Object -Unique)
#endregion

#region Import and merge
If ([string]::IsNullOrWhiteSpace($OutputFolder)) {
	$OutputFolder = [System.IO.Path]::GetDirectoryName($reports[0].Path)
}
If (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
	New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

$columns = New-Object System.Collections.Generic.List[string]
$seenCols = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$imported = New-Object System.Collections.Generic.List[object]

ForEach ($r In $reports) {
	If (-not (Test-Path -LiteralPath $r.Path -PathType Leaf)) {
		$r.Status = 'Missing'
		Write-Warning "Report not found: $($r.Path)"
		Continue
	}
	Try {
		$rows = @(Import-Csv -LiteralPath $r.Path -Encoding UTF8)
	} Catch {
		$r.Status = 'Unreadable'
		Write-Warning "Could not read $($r.Path): $($_.Exception.Message)"
		Continue
	}
	
	$r.Status = 'Combined'
	$r.RowCount = $rows.Count
	ForEach ($row In $rows) {
		ForEach ($name In $row.PSObject.Properties.Name) {
			If ($seenCols.Add($name)) {
				$columns.Add($name)
			}
		}
		$imported.Add([pscustomobject]@{
				Report = $r; Row = $row
			})
	}
}

$combined = @(ForEach ($item In $imported) {
		$o = [ordered]@{
			SourceBlock  = $item.Report.Block
			SourceReport = [System.IO.Path]::GetFileName($item.Report.Path)
		}
		ForEach ($c In $columns) {
			$p = $item.Row.PSObject.Properties[$c]
			If ($p) {
				$o[$c] = $p.Value
			} Else {
				$o[$c] = $null
			}
		}
		[pscustomobject]$o
	})

$header = @('SourceBlock', 'SourceReport') + @($columns)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $OutputFolder ('{0}_{1}.csv' -f $BaseName, $stamp)
$htmlPath = [System.IO.Path]::ChangeExtension($csvPath, '.html')

If ($combined.Count -gt 0) {
	$combined | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
} Else {
	# Header-only file so downstream tooling still gets a valid CSV
	Set-Content -LiteralPath $csvPath -Encoding UTF8 -Value (($header | ForEach-Object {
				'"' + $_ + '"'
			}) -join ',')
}
#endregion

#region Build HTML from the combined CSV
$htmlRows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)

If ([string]::IsNullOrWhiteSpace($MatchColumn)) {
	$MatchColumn = [string]($columns |
		Where-Object {
			$_ -match '^(Times)?(Found|Count|Matches|Occurrences|Hits)'
		} |
		Select-Object -First 1)
} ElseIf ($header -notcontains $MatchColumn) {
	Write-Warning "MatchColumn '$MatchColumn' is not in the combined data; match highlighting disabled."
	$MatchColumn = ''
}
$hasMatchCol = -not [string]::IsNullOrWhiteSpace($MatchColumn)

Function Test-IsMatchRow {
	Param ($Row)
	If (-not $hasMatchCol) {
		Return $false
	}
	$n = 0
	Return ([int]::TryParse([string]$Row.$MatchColumn, [ref]$n) -and $n -gt 0)
}

$matchCount = @($htmlRows | Where-Object {
		Test-IsMatchRow $_
	}).Count
$problemCount = @($reports | Where-Object {
		$_.Status -ne 'Combined'
	}).Count
# Distinct profiles/series that produced at least one match.
# Guarded by $header because Set-StrictMode -Version Latest throws on
# a missing property, and an all-empty run has no LabProfile column.
$profilesWithMatches = 0
If ($header -contains 'LabProfile') {
	$profilesWithMatches = @($htmlRows |
		Where-Object {
			Test-IsMatchRow $_
		} |
		ForEach-Object {
			$_.LabProfile
		} |
		Where-Object {
			$_
		} |
		Select-Object -Unique).Count
}

$seriesWithMatches = 0
If ($header -contains 'LabSeries') {
	$seriesWithMatches = @($htmlRows |
		Where-Object {
			Test-IsMatchRow $_
		} |
		ForEach-Object {
			$_.LabSeries
		} |
		Where-Object {
			$_
		} |
		Select-Object -Unique).Count
}
$css = @'
:root{--dg:#0A3E28;--mg:#136945;--mint:#24ED9B;--bmint:#72FFC6;--cream:#FFFCF1;--lyellow:#FFEFBC;--line:#D6DED9}
*{box-sizing:border-box}
body{margin:0;background:var(--cream);color:var(--dg);font-family:Inter,"Segoe UI",Arial,sans-serif;font-size:14px;line-height:1.45}
header{background:var(--dg);color:var(--cream);padding:24px 32px;border-bottom:4px solid var(--mint)}
header h1{font-family:Georgia,"Times New Roman",serif;font-weight:normal;font-size:28px;margin:0 0 6px}
header .sub{font-size:13px;opacity:.85;word-break:break-all}
main{padding:24px 32px}
.cards{display:flex;flex-wrap:wrap;gap:16px;margin-bottom:20px}
.card{background:#fff;border:1px solid var(--line);border-left:5px solid var(--mint);border-radius:6px;padding:12px 18px;min-width:170px}
.card.warn{border-left-color:#C0392B}
.card .n{font-size:28px;font-weight:700}
.card .l{font-size:12px;opacity:.8}
details{background:#fff;border:1px solid var(--line);border-radius:6px;margin:0 0 16px}
summary{cursor:pointer;padding:10px 14px;font-weight:600}
details .inner{padding:0 14px 14px;overflow-x:auto}
table.kv,table.src{border-collapse:collapse;font-size:13px}
table.kv th,table.kv td,table.src th,table.src td{padding:5px 12px 5px 0;text-align:left;vertical-align:top}
table.src th{border-bottom:1px solid var(--line)}
.bad{color:#C0392B;font-weight:600}
.toolbar{display:flex;flex-wrap:wrap;gap:16px;align-items:center;margin:8px 0 12px}
.toolbar input[type=search]{padding:7px 10px;border:1px solid var(--mg);border-radius:4px;min-width:300px;font:inherit}
.toolbar .count{opacity:.75;font-size:13px}
.wrap{overflow:auto;max-height:72vh;background:#fff;border:1px solid var(--line);border-radius:6px}
table.data{border-collapse:collapse;width:100%}
table.data th{position:sticky;top:0;background:var(--mg);color:var(--cream);text-align:left;padding:8px 10px;white-space:nowrap;cursor:pointer;user-select:none}
table.data th.sorted-asc::after{content:" \25B2"}
table.data th.sorted-desc::after{content:" \25BC"}
table.data td{padding:6px 10px;border-top:1px solid var(--line);vertical-align:top;white-space:pre-wrap;word-break:break-word;max-width:520px}
table.data tbody tr:nth-child(even) td{background:#F7F9F6}
table.data tbody tr.match td{background:var(--lyellow)}
table.data td.mcol{text-align:right}
table.data tr.match td.mcol{font-weight:700}
.empty{padding:24px;text-align:center;opacity:.7}
footer{padding:0 32px 24px;font-size:12px;opacity:.7}
'@

$js = @'
(function(){
  var tbl=document.getElementById('data'); if(!tbl) return;
  var tbody=tbl.tBodies[0], rows=Array.prototype.slice.call(tbody.rows);
  var q=document.getElementById('q'), only=document.getElementById('only'), shown=document.getElementById('shown');
  function apply(){
    var t=q.value.toLowerCase(), o=only&&only.checked, n=0;
    rows.forEach(function(r){
      var ok=(!o||r.classList.contains('match'))&&(!t||r.textContent.toLowerCase().indexOf(t)>-1);
      r.style.display=ok?'':'none'; if(ok) n++;
    });
    shown.textContent=n+' of '+rows.length+' rows shown';
  }
  q.addEventListener('input',apply);
  if(only) only.addEventListener('change',apply);
  var ths=tbl.tHead.rows[0].cells;
  Array.prototype.forEach.call(ths,function(th,i){
    th.addEventListener('click',function(){
      var asc=!th.classList.contains('sorted-asc');
      Array.prototype.forEach.call(ths,function(h){h.classList.remove('sorted-asc','sorted-desc');});
      th.classList.add(asc?'sorted-asc':'sorted-desc');
      rows.sort(function(a,b){
        var c=a.cells[i].textContent.trim().localeCompare(b.cells[i].textContent.trim(),undefined,{numeric:true,sensitivity:'base'});
        return asc?c:-c;
      });
      rows.forEach(function(r){tbody.appendChild(r);});
    });
  });
  apply();
})();
'@

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
[void]$sb.AppendLine("<title>Find-Text combined report $stamp</title>")
[void]$sb.AppendLine("<style>$css</style></head><body>")

# Header
[void]$sb.AppendLine('<header><h1>Find-Text combined report.</h1>')
[void]$sb.AppendLine(('<div class="sub">Generated {0} &middot; {1}</div></header>' -f
		(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (ConvertTo-HtmlSafe $csvPath)))
[void]$sb.AppendLine('<main>')

# Summary cards
[void]$sb.AppendLine('<div class="cards">')
#[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Reports combined</div></div>' -f ($reports.Count - $problemCount)))
[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Batches combined</div></div>' -f ($reports.Count - $problemCount)))
#[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Lab profiles searched</div></div>' -f $profileIds.Count))
If ($seriesIds.Count -gt 0) {
	[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Lab series searched</div></div>' -f $seriesIds.Count))
	[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Lab series with matches</div></div>' -f $seriesWithMatches))
}
If ($profileIds.Count -gt 0) {
	[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Lab profiles searched</div></div>' -f $profileIds.Count))
}
[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Lab profiles with matches</div></div>' -f $profilesWithMatches))
[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Total rows</div></div>' -f $htmlRows.Count))
If ($hasMatchCol) {
	[void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l">Rows with matches ({1} &gt; 0)</div></div>' -f $matchCount, (ConvertTo-HtmlSafe $MatchColumn)))
}
If ($problemCount -gt 0) {
	[void]$sb.AppendLine(('<div class="card warn"><div class="n">{0}</div><div class="l">Missing or unreadable reports</div></div>' -f $problemCount))
}
[void]$sb.AppendLine('</div>')

# Search parameters
[void]$sb.AppendLine('<details open><summary>Search parameters</summary><div class="inner"><table class="kv">')
ForEach ($pair In @(
		@('Find list', ($findLists -join '; ')),
		@('Find type', ($findTypes -join '; ')),
		@('Case type', ($caseTypes -join '; ')),
		@('Lab series', ($seriesIds -join ', ')),
		@('Lab profiles', ($profileIds -join ', ')))) {
	$val = $pair[1]; If ([string]::IsNullOrWhiteSpace($val)) {
		$val = '(not found in output)'
	}
	[void]$sb.AppendLine(('<tr><th>{0}</th><td>{1}</td></tr>' -f $pair[0], (ConvertTo-HtmlSafe $val)))
}
[void]$sb.AppendLine('</table></div></details>')

# Source reports (auto-expanded if anything went wrong)
$openAttr = ''; If ($problemCount -gt 0) {
	$openAttr = ' open'
}
[void]$sb.AppendLine(('<details{0}><summary>Source reports ({1})</summary><div class="inner"><table class="src">' -f $openAttr, $reports.Count))
[void]$sb.AppendLine('<tr><th>Block</th><th>Report</th><th>Rows</th><th>Status</th></tr>')
ForEach ($r In $reports) {
	$statusHtml = ConvertTo-HtmlSafe $r.Status
	If ($r.Status -ne 'Combined') {
		$statusHtml = '<span class="bad">' + $statusHtml + '</span>'
	}
	[void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>' -f
			(ConvertTo-HtmlSafe $r.Block), (ConvertTo-HtmlSafe $r.Path), $r.RowCount, $statusHtml))
}
[void]$sb.AppendLine('</table></div></details>')

# Results table
If ($htmlRows.Count -gt 0) {
	[void]$sb.AppendLine('<div class="toolbar"><input type="search" id="q" placeholder="Filter rows...">')
	If ($hasMatchCol) {
		[void]$sb.AppendLine('<label><input type="checkbox" id="only"> Only show matches</label>')
	}
	[void]$sb.AppendLine('<span class="count" id="shown"></span></div>')
	
	[void]$sb.AppendLine('<div class="wrap"><table class="data" id="data"><thead><tr>')
	ForEach ($h In $header) {
		[void]$sb.Append('<th>' + (ConvertTo-HtmlSafe $h) + '</th>')
	}
	[void]$sb.AppendLine('</tr></thead><tbody>')
	
	ForEach ($row In $htmlRows) {
		If (Test-IsMatchRow $row) {
			[void]$sb.Append('<tr class="match">')
		} Else {
			[void]$sb.Append('<tr>')
		}
		ForEach ($h In $header) {
			If ($hasMatchCol -and $h -eq $MatchColumn) {
				[void]$sb.Append('<td class="mcol">')
			} Else {
				[void]$sb.Append('<td>')
			}
			[void]$sb.Append((ConvertTo-HtmlSafe $row.$h) + '</td>')
		}
		[void]$sb.AppendLine('</tr>')
	}
	[void]$sb.AppendLine('</tbody></table></div>')
} Else {
	[void]$sb.AppendLine('<div class="wrap"><div class="empty">No rows were found in the source reports.</div></div>')
}

[void]$sb.AppendLine('</main>')
[void]$sb.AppendLine(('<footer>Source: {0} Find-Text_Report CSV file(s) combined into {1}</footer>' -f
		($reports.Count - $problemCount), (ConvertTo-HtmlSafe ([System.IO.Path]::GetFileName($csvPath)))))
[void]$sb.AppendLine("<script>$js</script></body></html>")

[System.IO.File]::WriteAllText($htmlPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
#endregion

If ($OpenHtml) {
	Start-Process -FilePath $htmlPath
}

[pscustomobject]@{
	CombinedCsv = $csvPath
	HtmlReport  = $htmlPath
	ReportCount = $reports.Count - $problemCount
	RowCount    = $htmlRows.Count
	MatchCount  = $matchCount
	MissingReports = @($reports | Where-Object {
			$_.Status -ne 'Combined'
		} | ForEach-Object {
			$_.Path
		})
}
