#Requires -Version 5.1
<#
	.SYNOPSIS
		Converts a translation phrase-check CSV into a self-contained, interactive HTML report.
	
	.DESCRIPTION
		Reads a CSV produced by the translation phrase-check process (columns SearchPhrase,
		CaseSensitive, Status, Message, ErrorMessage, TranslatedPhrase, SourceOccurrenceCount,
		TranslationOccurrenceCount, SourceLines, TranslationLines) and writes a single HTML file.
		
		The report uses only HTML, CSS and vanilla JavaScript. Nothing is downloaded at view time:
		no CDNs, web fonts, frameworks or external files. The table is rendered as static,
		HTML-encoded markup, so the report is readable (and printable) even with JavaScript off.
		JavaScript adds search, status filters, a count-mismatch filter, column sorting and
		expand/collapse for long phrases.
		
		Input can be supplied by parameter, by pipeline (Get-ChildItem *.csv | ...), by dropping
		files onto the companion .cmd wrapper, or interactively via a file picker when no path is given.
	
	.PARAMETER Path
		One or more CSV files to convert. Accepts pipeline input and FileInfo objects.
	
	.PARAMETER OutputPath
		Optional. A target .html file (single input only) or an existing/new directory.
		Defaults to the input file's folder and name, with an .html extension.
	
	.PARAMETER Title
		Optional. Report heading and browser tab title. Default: "Translation phrase check".
	
	.PARAMETER Open
		Opens each generated report in the default browser.
	
	.PARAMETER PassThru
		Emits a System.IO.FileInfo object for each report written, for use in a pipeline.
	
	.PARAMETER NoPause
		Suppresses the "press Enter" pause that normally appears when the script is launched
		from Explorer, so the console window doesn't vanish before you can read the output.
	
	.EXAMPLE
		.\ConvertTo-TranslationReportHtml.ps1 .\Translated-REP.csv -Open
	
	.EXAMPLE
		Get-ChildItem C:\Reports\*.csv | .\ConvertTo-TranslationReportHtml.ps1 -OutputPath C:\Reports\html
	
	.OUTPUTS
		None by default. System.IO.FileInfo for each report written when -PassThru is used.
	
	.NOTES
		Additional information about the file.
#>
[CmdletBinding()]
param
(
	[Parameter(ValueFromPipeline = $true,
			   ValueFromPipelineByPropertyName = $true,
			   ValueFromRemainingArguments = $true,
			   Position = 0)]
	[Alias('FullName', 'FilePath', 'CsvPath')]
	[string[]]$Path,
	[ValidateNotNullOrEmpty()]
	[string]$OutputPath,
	[ValidateLength(1, 200)]
	[ValidateNotNullOrEmpty()]
	[string]$Title = 'Translation phrase check',
	[switch]$Open,
	[switch]$PassThru,
	[switch]$NoPause
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $RequiredColumns = @(
        'SearchPhrase', 'CaseSensitive', 'Status', 'Message', 'ErrorMessage', 'TranslatedPhrase',
        'SourceOccurrenceCount', 'TranslationOccurrenceCount', 'SourceLines', 'TranslationLines'
    )

    # Known statuses get a friendly label and a visual tone. Unknown statuses are humanized
    # automatically and rendered with a neutral tone, so new statuses never break the report.
    $StatusMap = @{
        'Found'                 = @{ Label = 'Found';              Tone = 'ok'    }
        'NotFoundInSource'      = @{ Label = 'Not in source';      Tone = 'warn'  }
        'NotFoundInTranslation' = @{ Label = 'Not in translation'; Tone = 'warn'  }
        'NotFound'              = @{ Label = 'Not found';          Tone = 'warn'  }
        'Error'                 = @{ Label = 'Error';              Tone = 'error' }
    }
    $ToneOrder = @{ 'error' = 0; 'warn' = 1; 'neutral' = 2; 'ok' = 3 }

    $script:InputPaths = New-Object System.Collections.Generic.List[string]
    $script:Failures   = 0
    $Utf8NoBom         = New-Object System.Text.UTF8Encoding($false)

    #region Helpers
    function Test-LaunchedFromExplorer {
        if ($NoPause) { return $false }
        $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ((Test-Path Variable:IsWindows) -and $IsWindows)
        if (-not $onWindows) { return $false }
        try {
            $parentId = (Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
            return ((Get-Process -Id $parentId -ErrorAction Stop).ProcessName -eq 'explorer')
        }
        catch { return $false }
    }

    function Select-CsvFile {
        # Only reached when no path was supplied. Tries a GUI picker, then falls back to a prompt.
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Title       = 'Select translation CSV file(s)'
            $dialog.Filter      = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $dialog.Multiselect = $true
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.FileNames }
            return @()
        }
        catch {
            $answer = Read-Host 'Path to the CSV file (leave blank to cancel)'
            if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
            return @($answer)
        }
    }

    function ConvertTo-HtmlText([AllowNull()][string]$Text) {
        if ([string]::IsNullOrEmpty($Text)) { return '' }
        # Normalize line endings; CSS white-space: pre-wrap preserves the remaining newlines.
        return [System.Net.WebUtility]::HtmlEncode(($Text -replace "`r`n?", "`n"))
    }

    function Get-StatusInfo([AllowNull()][string]$Status) {
        $key = if ($null -eq $Status) { '' } else { $Status.Trim() }
        if ($key -eq '') { return @{ Key = '(none)'; Label = 'No status'; Tone = 'neutral' } }
        if ($StatusMap.ContainsKey($key)) {
            return @{ Key = $key; Label = $StatusMap[$key].Label; Tone = $StatusMap[$key].Tone }
        }
        $label = ($key -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ').ToLowerInvariant()
        $label = $label.Substring(0, 1).ToUpperInvariant() + $label.Substring(1)
        return @{ Key = $key; Label = $label; Tone = 'neutral' }
    }

    function ConvertTo-Count([AllowNull()][string]$Value, [string]$Column, [int]$RowNumber) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return 0 }
        $n = 0
        if ([int]::TryParse($Value.Trim(), [ref]$n)) { return $n }
        Write-Warning "Row $RowNumber : '$Column' value '$Value' isn't a whole number. Showing it as 0."
        return 0
    }

    function ConvertTo-LineChips([AllowNull()][string]$Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return '<span class="none">None</span>' }
        $chips = foreach ($line in ($Value -split '[,;\s]+' | Where-Object { $_ -ne '' })) {
            '<span class="line">' + (ConvertTo-HtmlText $line) + '</span>'
        }
        return '<span class="lines">' + ($chips -join '') + '</span>'
    }

    function Resolve-OutputFile([string]$CsvFile, [int]$InputCount) {
        $defaultName = [System.IO.Path]::GetFileNameWithoutExtension($CsvFile) + '.html'
        if (-not $OutputPath) {
            return Join-Path ([System.IO.Path]::GetDirectoryName($CsvFile)) $defaultName
        }
        $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath.Trim().Trim('"'))
        $ext    = [System.IO.Path]::GetExtension($target)
        $isDir  = (Test-Path -LiteralPath $target -PathType Container) -or ($ext -eq '')
        if ($isDir) {
            if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
            return Join-Path $target $defaultName
        }
        if ($InputCount -gt 1) {
            throw "OutputPath '$OutputPath' is a file, but $InputCount input files were supplied. Pass a folder instead."
        }
        if ($ext -notin '.html', '.htm') {
            throw "OutputPath '$OutputPath' must end in .html or .htm (or be a folder)."
        }
        $parent = [System.IO.Path]::GetDirectoryName($target)
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        return $target
    }
    #endregion Helpers
	
	#region Static page assets (single-quoted here-strings: no PowerShell interpolation)
	# --bg: #FFFCF1 = Skillable Green
	# --bg: #00FF00 = Neon Lime Green
	# --bg: #00FFFF = Pure Electric Cyan
    $Css = @'
:root {
  color-scheme: light dark;
  --bg: #00FFFF; --surface: #FFFFFF; --ink: #0A3E28; --muted: #136945; --rule: #D9D6C8;
  --ok-bg: #136945; --ok-ink: #FFFCF1;
  --warn-bg: #FFE38B; --warn-ink: #0A3E28;
  --err-bg: #7000FF; --err-ink: #FFFCF1;
  --flag: #7000FF; --focus: #7000FF; --row-hover: #FFEFBC;
  --serif: "Tiempos Headline", Georgia, "Times New Roman", serif;
  --sans: "Labil Grotesk", "Segoe UI", system-ui, -apple-system, Roboto, Arial, sans-serif;
  --mono: Consolas, "Cascadia Mono", Menlo, monospace;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0A3E28; --surface: #0D4A30; --ink: #FFFCF1; --muted: #B9E6CF; --rule: #2A6A4C;
    --ok-bg: #24ED9B; --ok-ink: #0A3E28; --flag: #FFE38B; --focus: #24ED9B; --row-hover: #136945;
  }
}
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.5 var(--sans); }
.wrap { max-width: 1400px; margin: 0 auto; padding: 2rem clamp(1rem, 3vw, 2.5rem) 3rem; }
header h1 { font: 400 clamp(1.75rem, 3vw, 2.5rem)/1.15 var(--serif); margin: 0 0 .35rem; }
header p { margin: 0; color: var(--muted); }
.visually-hidden { position: absolute !important; width: 1px; height: 1px; margin: -1px; padding: 0; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0; }
:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }

/* Summary: one proportional bar, with a filter button per status underneath */
.summary { margin: 1.75rem 0 1.25rem; }
.bar { display: flex; height: 14px; border-radius: 7px; overflow: hidden; background: var(--rule); }
.bar span { display: block; min-width: 3px; }
.legend { display: flex; flex-wrap: wrap; gap: .5rem; margin: .75rem 0 0; padding: 0; list-style: none; }
.legend button, .legend .static {
  display: inline-flex; align-items: center; gap: .5rem; font: inherit; color: inherit;
  background: var(--surface); border: 1px solid var(--rule); border-radius: 999px; padding: .3rem .85rem .3rem .45rem;
}
.legend button { cursor: pointer; }
.legend button[aria-pressed="false"] { opacity: .55; text-decoration: line-through; }
.legend b { font-variant-numeric: tabular-nums; }
.swatch { width: .9rem; height: .9rem; border-radius: 50%; flex: none; }
.swatch.flagged { background: transparent; border: 2px solid var(--flag); }

/* Toolbar only appears when JavaScript is running */
.toolbar { display: none; flex-wrap: wrap; align-items: end; gap: .75rem 1.25rem; margin-bottom: .75rem; }
.js .toolbar { display: flex; }
.toolbar label { display: grid; gap: .2rem; font-size: .875rem; color: var(--muted); }
.toolbar input[type="search"] {
  font: inherit; color: var(--ink); background: var(--surface); border: 1px solid var(--rule);
  border-radius: 6px; padding: .45rem .7rem; width: min(28rem, 80vw);
}
.toolbar .check { display: flex; align-items: center; gap: .45rem; color: var(--ink); font-size: .95rem; }
.toolbar input[type="checkbox"] { width: 1.05rem; height: 1.05rem; accent-color: var(--focus); }
.btn { font: inherit; color: var(--ink); background: transparent; border: 1px solid var(--ink); border-radius: 6px; padding: .4rem .9rem; cursor: pointer; }
.btn:hover { background: var(--row-hover); }
#result-count { margin: 0 0 .5rem; font-size: .875rem; color: var(--muted); }

/* Table */
.table-scroll { overflow-x: auto; border: 1px solid var(--rule); border-radius: 10px; background: var(--surface); }
table { width: 100%; min-width: 900px; border-collapse: collapse; }
caption { text-align: left; }
th, td { padding: .7rem .85rem; text-align: left; vertical-align: top; border-bottom: 1px solid var(--rule); }
thead th { font-weight: 600; font-size: .875rem; white-space: nowrap; background: var(--bg); }
tbody tr:last-child td { border-bottom: 0; }
tbody tr:hover td { background: var(--row-hover); }
th .sort { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; display: inline-flex; gap: .35rem; align-items: center; }
th .sort::after { content: ""; width: 0; height: 0; border: 4px solid transparent; border-top-color: currentColor; opacity: .3; margin-top: 4px; }
th[aria-sort="ascending"] .sort::after { border-top-color: transparent; border-bottom-color: currentColor; opacity: 1; margin-top: -4px; }
th[aria-sort="descending"] .sort::after { opacity: 1; }
.col-status { width: 12rem; } .col-count { width: 8.5rem; } .col-lines { width: 11rem; }
.phrase { white-space: pre-wrap; overflow-wrap: anywhere; max-width: 70ch; }
.clamped { display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
.toggle { font: inherit; font-size: .8125rem; color: var(--muted); background: none; border: 0; padding: .25rem 0 0; text-decoration: underline; cursor: pointer; }
.empty-cell { color: var(--muted); font-style: italic; }
.chip { display: inline-block; font-size: .8125rem; font-weight: 600; line-height: 1.2; padding: .25rem .6rem; border-radius: 999px; white-space: nowrap; }
.tone-ok { background: var(--ok-bg); color: var(--ok-ink); }
.tone-warn { background: var(--warn-bg); color: var(--warn-ink); }
.tone-error { background: var(--err-bg); color: var(--err-ink); }
.tone-neutral { background: transparent; color: var(--ink); border: 1px solid var(--ink); }
.chip.flag { background: transparent; color: var(--flag); border: 1.5px solid var(--flag); margin-top: .4rem; }
.case { display: block; margin-top: .4rem; font-size: .8125rem; color: var(--muted); }
.error-text { display: block; margin-top: .4rem; font-size: .875rem; color: var(--err-bg); font-weight: 600; }
@media (prefers-color-scheme: dark) { .error-text { color: #FFE38B; } }
details { margin-top: .4rem; font-size: .8125rem; color: var(--muted); }
details summary { cursor: pointer; }
details p { margin: .3rem 0 0; white-space: pre-wrap; overflow-wrap: anywhere; color: var(--ink); }
.counts { font-variant-numeric: tabular-nums; white-space: nowrap; }
.counts dl { margin: 0; display: grid; grid-template-columns: auto auto; gap: .1rem .6rem; }
.counts dt { color: var(--muted); font-size: .8125rem; } .counts dd { margin: 0; text-align: right; }
.lines { display: flex; flex-wrap: wrap; gap: .25rem; }
.line { font: .8125rem/1.4 var(--mono); padding: .05rem .4rem; border: 1px solid var(--rule); border-radius: 4px; }
.none { color: var(--muted); font-size: .875rem; }
.lines-group + .lines-group { margin-top: .45rem; }
.lines-group small { display: block; color: var(--muted); font-size: .75rem; margin-bottom: .15rem; }
.no-results td { text-align: center; padding: 2.5rem 1rem; color: var(--muted); }
footer { margin-top: 1.5rem; font-size: .8125rem; color: var(--muted); }

@media (prefers-reduced-motion: reduce) { * { transition: none !important; animation: none !important; } }
@media print {
  :root { --bg: #fff; --surface: #fff; --row-hover: transparent; }
  .toolbar, .toggle, #result-count { display: none !important; }
  .clamped { display: block; -webkit-line-clamp: unset; overflow: visible; }
  .table-scroll { overflow: visible; border: 0; }
  table { min-width: 0; font-size: 10pt; }
  tr { break-inside: avoid; }
  details { display: block; } details > * { display: block; }
}
'@

    $Js = @'
(function () {
  'use strict';
  var table = document.getElementById('results');
  if (!table) { return; }
  var tbody = table.tBodies[0];
  var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr[data-status]'));
  var emptyRow = tbody.querySelector('.no-results');
  var search = document.getElementById('filter-text');
  var flagOnly = document.getElementById('filter-flag');
  var reset = document.getElementById('filter-reset');
  var countOut = document.getElementById('result-count');
  var statusButtons = Array.prototype.slice.call(document.querySelectorAll('[data-filter-status]'));
  var sortState = { key: null, dir: 0 };

  rows.forEach(function (row, i) {
    row._index = i;
    row._text = row.textContent.toLowerCase();
  });

  function activeStatuses() {
    var set = {};
    statusButtons.forEach(function (b) {
      if (b.getAttribute('aria-pressed') === 'true') { set[b.getAttribute('data-filter-status')] = true; }
    });
    return set;
  }

  function applyFilters() {
    var terms = search.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    var statuses = activeStatuses();
    var onlyFlagged = flagOnly.checked;
    var shown = 0;
    rows.forEach(function (row) {
      var visible = statuses[row.getAttribute('data-status')] === true &&
        (!onlyFlagged || row.hasAttribute('data-flagged')) &&
        terms.every(function (t) { return row._text.indexOf(t) !== -1; });
      row.hidden = !visible;
      if (visible) { shown++; }
    });
    emptyRow.hidden = shown !== 0;
    countOut.textContent = 'Showing ' + shown + ' of ' + rows.length + ' rows';
  }

  function sortValue(row, key) {
    var v = row.getAttribute('data-sort-' + key) || '';
    return (key === 'srccount' || key === 'trcount' || key === 'tone') ? Number(v) : v.toLowerCase();
  }

  function applySort() {
    var key = sortState.key, dir = sortState.dir;
    var ordered = rows.slice().sort(function (a, b) {
      if (!key || dir === 0) { return a._index - b._index; }
      var x = sortValue(a, key), y = sortValue(b, key);
      var c = (typeof x === 'number') ? x - y : x.localeCompare(y);
      return (c === 0 ? a._index - b._index : c) * dir;
    });
    var frag = document.createDocumentFragment();
    ordered.forEach(function (r) { frag.appendChild(r); });
    frag.appendChild(emptyRow);
    tbody.appendChild(frag);
    Array.prototype.forEach.call(table.tHead.querySelectorAll('th[data-sort-key]'), function (th) {
      var state = (th.getAttribute('data-sort-key') === key && dir !== 0) ? (dir === 1 ? 'ascending' : 'descending') : 'none';
      th.setAttribute('aria-sort', state);
    });
  }

  Array.prototype.forEach.call(table.tHead.querySelectorAll('th[data-sort-key]'), function (th) {
    th.querySelector('button').addEventListener('click', function () {
      var key = th.getAttribute('data-sort-key');
      if (sortState.key !== key) { sortState = { key: key, dir: 1 }; }
      else { sortState.dir = sortState.dir === 1 ? -1 : (sortState.dir === -1 ? 0 : 1); }
      applySort();
    });
  });

  statusButtons.forEach(function (b) {
    b.addEventListener('click', function () {
      b.setAttribute('aria-pressed', b.getAttribute('aria-pressed') === 'true' ? 'false' : 'true');
      applyFilters();
    });
  });

  var timer;
  search.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(applyFilters, 120); });
  flagOnly.addEventListener('change', applyFilters);
  reset.addEventListener('click', function () {
    search.value = '';
    flagOnly.checked = false;
    statusButtons.forEach(function (b) { b.setAttribute('aria-pressed', 'true'); });
    sortState = { key: null, dir: 0 };
    applySort();
    applyFilters();
    search.focus();
  });

  // Collapse long phrases to four lines, with an accessible toggle only where text overflows.
  Array.prototype.forEach.call(document.querySelectorAll('.phrase'), function (el, i) {
    el.classList.add('clamped');
    if (el.scrollHeight <= el.clientHeight + 1) { el.classList.remove('clamped'); return; }
    if (!el.id) { el.id = 'phrase-' + i; }
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'toggle';
    btn.setAttribute('aria-controls', el.id);
    btn.setAttribute('aria-expanded', 'false');
    btn.textContent = 'Show full text';
    btn.addEventListener('click', function () {
      var expand = el.classList.contains('clamped');
      el.classList.toggle('clamped', !expand);
      btn.setAttribute('aria-expanded', String(expand));
      btn.textContent = expand ? 'Show less' : 'Show full text';
    });
    el.insertAdjacentElement('afterend', btn);
  });

  window.addEventListener('beforeprint', function () {
    Array.prototype.forEach.call(document.querySelectorAll('details'), function (d) { d.open = true; });
  });

  applyFilters();
}());
'@
    #endregion Static page assets
}

process {
    foreach ($p in $Path) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { $script:InputPaths.Add($p.Trim().Trim('"')) }
    }
}

end {
    $fromExplorer = Test-LaunchedFromExplorer

    if ($script:InputPaths.Count -eq 0) {
        foreach ($picked in @(Select-CsvFile)) { $script:InputPaths.Add($picked) }
        if ($script:InputPaths.Count -eq 0) {
            Write-Warning 'No CSV file was selected. Nothing to do.'
            if ($fromExplorer) { [void](Read-Host 'Press Enter to close') }
            return
        }
    }

    foreach ($inputPath in $script:InputPaths) {
        try {
            #region Validate input
            try { $csvFile = (Resolve-Path -LiteralPath $inputPath -ErrorAction Stop).ProviderPath }
            catch { throw "File not found: '$inputPath'." }

            if (-not (Test-Path -LiteralPath $csvFile -PathType Leaf)) { throw "'$csvFile' is a folder, not a CSV file." }
            if ([System.IO.Path]::GetExtension($csvFile) -ne '.csv') {
                Write-Warning "'$([System.IO.Path]::GetFileName($csvFile))' doesn't have a .csv extension. Attempting to read it as CSV anyway."
            }
            if ((Get-Item -LiteralPath $csvFile).Length -eq 0) { throw "'$csvFile' is empty." }

            try { $rows = @(Import-Csv -LiteralPath $csvFile -Encoding UTF8 -ErrorAction Stop) }
            catch { throw "Couldn't parse '$csvFile' as CSV: $($_.Exception.Message)" }

            if ($rows.Count -eq 0) { throw "'$csvFile' has a header row but no data rows." }

            $columns = @($rows[0].PSObject.Properties.Name)
            $missing = @($RequiredColumns | Where-Object { $columns -notcontains $_ })
            if ($missing.Count -gt 0) {
                throw ("'$([System.IO.Path]::GetFileName($csvFile))' is missing required column(s): $($missing -join ', '). " +
                       "Found: $($columns -join ', ').")
            }
            $extra = @($columns | Where-Object { $RequiredColumns -notcontains $_ })
            if ($extra.Count -gt 0) { Write-Verbose "Ignoring extra column(s): $($extra -join ', ')" }

            $outFile = Resolve-OutputFile -CsvFile $csvFile -InputCount $script:InputPaths.Count
            #endregion Validate input

            #region Build rows and summary
            $statusCounts = [ordered]@{}   # key -> @{ Label; Tone; Count }
            $flaggedCount = 0
            $rowHtml = New-Object System.Text.StringBuilder
            $rowNumber = 1

            foreach ($r in $rows) {
                $rowNumber++   # data rows start on line 2 of the file
                $info = Get-StatusInfo $r.Status
                if (-not $statusCounts.Contains($info.Key)) {
                    $statusCounts[$info.Key] = @{ Label = $info.Label; Tone = $info.Tone; Count = 0 }
                }
                $statusCounts[$info.Key].Count++

                $srcCount = ConvertTo-Count $r.SourceOccurrenceCount 'SourceOccurrenceCount' $rowNumber
                $trCount  = ConvertTo-Count $r.TranslationOccurrenceCount 'TranslationOccurrenceCount' $rowNumber
                $flagged  = ($info.Key -eq 'Found') -and ($srcCount -ne $trCount)
                if ($flagged) { $flaggedCount++ }

                $caseSensitive = ("$($r.CaseSensitive)".Trim() -eq 'True')
                $source = if ($null -eq $r.SearchPhrase) { '' } else { $r.SearchPhrase }

                # Status cell
                $statusCell = '<span class="chip tone-' + $info.Tone + '">' + (ConvertTo-HtmlText $info.Label) + '</span>'
                if ($flagged) { $statusCell += '<br><span class="chip flag">Counts differ</span>' }
                if ($caseSensitive) { $statusCell += '<span class="case">Case-sensitive match</span>' }
                if (-not [string]::IsNullOrWhiteSpace($r.ErrorMessage)) {
                    $statusCell += '<span class="error-text">' + (ConvertTo-HtmlText $r.ErrorMessage) + '</span>'
                }
                if (-not [string]::IsNullOrWhiteSpace($r.Message)) {
                    $statusCell += '<details><summary>Message</summary><p>' + (ConvertTo-HtmlText $r.Message) + '</p></details>'
                }

                $sourceCell = if ([string]::IsNullOrEmpty($source)) { '<span class="empty-cell">Empty</span>' }
                              else { '<div class="phrase">' + (ConvertTo-HtmlText $source) + '</div>' }
                $transCell  = if ([string]::IsNullOrWhiteSpace($r.TranslatedPhrase)) { '<span class="empty-cell">No translation</span>' }
                              else { '<div class="phrase" lang="und">' + (ConvertTo-HtmlText $r.TranslatedPhrase) + '</div>' }

                $countsCell = '<dl><dt>Source</dt><dd>' + $srcCount + '</dd><dt>Translation</dt><dd>' + $trCount + '</dd></dl>'
                $linesCell  = if ([string]::IsNullOrWhiteSpace($r.SourceLines) -and [string]::IsNullOrWhiteSpace($r.TranslationLines)) {
                                  '<span class="none">None</span>'
                              }
                              else {
                                  '<div class="lines-group"><small>Source</small>' + (ConvertTo-LineChips $r.SourceLines) + '</div>' +
                                  '<div class="lines-group"><small>Translation</small>' + (ConvertTo-LineChips $r.TranslationLines) + '</div>'
                              }

                $sortSource = ConvertTo-HtmlText (($source -replace '\s+', ' ').Trim())
                if ($sortSource.Length -gt 120) { $sortSource = $sortSource.Substring(0, 120) }

                [void]$rowHtml.Append('<tr data-status="').Append((ConvertTo-HtmlText $info.Key)).Append('"')
                if ($flagged) { [void]$rowHtml.Append(' data-flagged=""') }
                [void]$rowHtml.Append(' data-sort-tone="').Append($ToneOrder[$info.Tone]).Append('"')
                [void]$rowHtml.Append(' data-sort-source="').Append($sortSource).Append('"')
                [void]$rowHtml.Append(' data-sort-srccount="').Append($srcCount).Append('"')
                [void]$rowHtml.Append(' data-sort-trcount="').Append($trCount).Append('">')
                [void]$rowHtml.Append('<td>').Append($statusCell).Append('</td>')
                [void]$rowHtml.Append('<td>').Append($sourceCell).Append('</td>')
                [void]$rowHtml.Append('<td>').Append($transCell).Append('</td>')
                [void]$rowHtml.Append('<td class="counts">').Append($countsCell).Append('</td>')
                [void]$rowHtml.Append('<td>').Append($linesCell).Append('</td>')
                [void]$rowHtml.AppendLine('</tr>')
            }

            # Summary bar and legend, ordered by severity so problems surface first
            $total    = $rows.Count
            $ordered  = $statusCounts.GetEnumerator() | Sort-Object { $ToneOrder[$_.Value.Tone] }, { $_.Value.Label }
            $bar      = New-Object System.Text.StringBuilder
            $legend   = New-Object System.Text.StringBuilder
            $barLabel = @()
            foreach ($entry in $ordered) {
                $pct = [math]::Round(($entry.Value.Count / $total) * 100, 2)
                $pctText = [math]::Round($pct, 0)
                $label = ConvertTo-HtmlText $entry.Value.Label
                $barLabel += "$($entry.Value.Label) $($entry.Value.Count) ($pctText%)"
                [void]$bar.Append('<span class="tone-' + $entry.Value.Tone + '" style="flex-grow:' +
                    $pct.ToString([System.Globalization.CultureInfo]::InvariantCulture) + '"></span>')
                [void]$legend.Append('<li><button type="button" aria-pressed="true" data-filter-status="' +
                    (ConvertTo-HtmlText $entry.Key) + '"><span class="swatch tone-' + $entry.Value.Tone +
                    '"></span>' + $label + ' <b>' + $entry.Value.Count + '</b><span class="visually-hidden"> rows, ' +
                    $pctText + ' percent. Toggle filter.</span></button></li>')
            }
            if ($flaggedCount -gt 0) {
                [void]$legend.Append('<li><span class="static"><span class="swatch flagged"></span>Counts differ <b>' +
                    $flaggedCount + '</b></span></li>')
            }
            #endregion Build rows and summary

            #region Assemble page
            $csvName     = [System.IO.Path]::GetFileName($csvFile)
            $now         = Get-Date
            $titleHtml   = ConvertTo-HtmlText $Title
            $csvNameHtml = ConvertTo-HtmlText $csvName
            $rowWord     = if ($total -eq 1) { 'row' } else { 'rows' }

            $html = New-Object System.Text.StringBuilder
            [void]$html.AppendLine('<!DOCTYPE html>')
            [void]$html.AppendLine('<html lang="en">')
            [void]$html.AppendLine('<head>')
            [void]$html.AppendLine('<meta charset="utf-8">')
            [void]$html.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
            [void]$html.AppendLine('<meta name="generator" content="ConvertTo-TranslationReportHtml.ps1">')
            [void]$html.AppendLine("<title>$titleHtml - $csvNameHtml</title>")
            [void]$html.AppendLine('<script>document.documentElement.className += " js";</script>')
            [void]$html.AppendLine("<style>`n$Css`n</style>")
            [void]$html.AppendLine('</head>')
            [void]$html.AppendLine('<body>')
            [void]$html.AppendLine('<main class="wrap">')
            [void]$html.AppendLine('<header>')
            [void]$html.AppendLine("<h1>$titleHtml</h1>")
            [void]$html.AppendLine("<p>$total $rowWord from <strong>$csvNameHtml</strong>, generated <time datetime=`"$($now.ToString('s'))`">$($now.ToString('yyyy-MM-dd HH:mm'))</time>.</p>")
            [void]$html.AppendLine('</header>')
            [void]$html.AppendLine('<section class="summary" aria-labelledby="summary-heading">')
            [void]$html.AppendLine('<h2 id="summary-heading" class="visually-hidden">Summary by status</h2>')
            [void]$html.AppendLine("<div class=`"bar`" role=`"img`" aria-label=`"$(ConvertTo-HtmlText ($barLabel -join ', '))`">$($bar.ToString())</div>")
            [void]$html.AppendLine("<ul class=`"legend`">$($legend.ToString())</ul>")
            [void]$html.AppendLine('</section>')
            [void]$html.AppendLine('<div class="toolbar" role="search">')
            [void]$html.AppendLine('<label for="filter-text">Search phrases, translations and messages<input type="search" id="filter-text" autocomplete="off" spellcheck="false"></label>')
            [void]$html.AppendLine('<label class="check" for="filter-flag"><input type="checkbox" id="filter-flag">Only rows where counts differ</label>')
            [void]$html.AppendLine('<button type="button" class="btn" id="filter-reset">Reset view</button>')
            [void]$html.AppendLine('</div>')
            [void]$html.AppendLine('<p id="result-count" aria-live="polite"></p>')
            [void]$html.AppendLine('<div class="table-scroll" tabindex="0" role="region" aria-labelledby="results-caption">')
            [void]$html.AppendLine('<table id="results">')
            [void]$html.AppendLine("<caption id=`"results-caption`" class=`"visually-hidden`">Phrase check results from $csvNameHtml</caption>")
            [void]$html.AppendLine('<thead><tr>')
            [void]$html.AppendLine('<th scope="col" class="col-status" data-sort-key="tone" aria-sort="none"><button type="button" class="sort">Status</button></th>')
            [void]$html.AppendLine('<th scope="col" data-sort-key="source" aria-sort="none"><button type="button" class="sort">Source phrase</button></th>')
            [void]$html.AppendLine('<th scope="col">Translated phrase</th>')
            [void]$html.AppendLine('<th scope="col" class="col-count" data-sort-key="srccount" aria-sort="none"><button type="button" class="sort">Occurrences</button></th>')
            [void]$html.AppendLine('<th scope="col" class="col-lines">Lines</th>')
            [void]$html.AppendLine('</tr></thead>')
            [void]$html.AppendLine('<tbody>')
            [void]$html.Append($rowHtml.ToString())
            [void]$html.AppendLine('<tr class="no-results" hidden><td colspan="5">No rows match these filters. Clear the search or select Reset view.</td></tr>')
            [void]$html.AppendLine('</tbody>')
            [void]$html.AppendLine('</table>')
            [void]$html.AppendLine('</div>')
            [void]$html.AppendLine("<footer><p>Source data: $csvNameHtml ($total $rowWord). &ldquo;Counts differ&rdquo; marks Found rows where the source and translation occurrence counts aren&rsquo;t equal.</p></footer>")
            [void]$html.AppendLine('</main>')
            [void]$html.AppendLine("<script>`n$Js`n</script>")
            [void]$html.AppendLine('</body>')
            [void]$html.AppendLine('</html>')
            #endregion Assemble page

            try { [System.IO.File]::WriteAllText($outFile, $html.ToString(), $Utf8NoBom) }
            catch { throw "Couldn't write '$outFile': $($_.Exception.Message) Check that the file isn't open elsewhere and the folder is writable." }

            $summaryText = ($statusCounts.GetEnumerator() | ForEach-Object { "$($_.Value.Label): $($_.Value.Count)" }) -join ', '
            Write-Host "Report created: $outFile" -ForegroundColor Green
            Write-Host "  $total $rowWord ($summaryText; counts differ: $flaggedCount)"

            if ($Open -or $fromExplorer) { Invoke-Item -LiteralPath $outFile }
            if ($PassThru) { Get-Item -LiteralPath $outFile }
        }
        catch {
            $script:Failures++
            Write-Error -Message "Failed to convert '$inputPath': $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    if ($fromExplorer) { [void](Read-Host 'Press Enter to close') }
    if ($script:Failures -gt 0) { exit 1 }
}
