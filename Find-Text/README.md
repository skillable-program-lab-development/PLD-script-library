# Find-Text

This folder contains the Find-Text utility, a comprehensive PowerShell-based search tool for locating and reporting on specific text patterns across Skillable Studio Lab Profiles, instructions, scripts, and configuration files.

## Overview

Find-Text enables users to:
- Search for one or more text terms across Lab Series or Lab Profiles
- Find terms in Lab Instructions, Life Cycle Actions (LCAs), Activities, and Access Control Policies (ACPs)
- Support multiple search types and case sensitivity modes
- Generate detailed CSV and HTML reports of findings
- Handle complex multi-term searches with logical operators

## Components

### PowerShell Scripts

- **find-text.ps1** — Main search utility that queries Lab Profiles for specified text terms
- **Report-FindText.ps1** — Combines multiple Find-Text CSV reports into a single formatted HTML report with search and filtering capabilities

### Deployment & UI

- **Find-Text.psf** — PowerShell Studio form file for the Find-Text user interface
- **WKUtils Find-Text.msi** — Installer package for deploying Find-Text

## Features

### Search Capabilities

- **Multi-location search** — Search in:
  - Lab Instructions (static content)
  - Text Swaps/Replacements (substitution rules)
  - External Instructions (GitHub/cloud-hosted)
  - Life Cycle Actions (LCA scripts)
  - Automated Activities (activity scripts)
  - Access Control Policies (ACPs)

- **Multiple search modes**:
  - Exact: Full word match
  - StartsWith: Term at word boundary start
  - EndsWith: Term at word boundary end
  - Contains: Anywhere in text (default)

- **Case sensitivity options**:
  - None: Exact case matching
  - Lower: Normalize to lowercase
  - Upper: Normalize to uppercase
  - Camel: Title case matching
  - Any: Case-insensitive matching

- **Complex queries**:
  - Single terms: `Term1`
  - Multiple terms: `Term1,Term2,Term3`
  - AND logic: Use `&&` separator for compound terms

### Reporting

- **CSV Output** — Detailed results with:
  - Lab Series ID and Name
  - Lab Profile ID and Name
  - Search location (Instructions, LCA, Activity, ACP, etc.)
  - Term searched
  - Occurrence count

- **HTML Reports** — Comprehensive, interactive reports with:
  - Summary statistics (profiles/series with matches, total rows)
  - Search parameters recap
  - Sortable data table
  - Text-based filtering
  - Match highlighting
  - Responsive design

## Usage

### Parameters (find-text.ps1)

```powershell
-LabSeriesList <string>            # Comma-separated Lab Series IDs (ParameterSet: Series)
-LabProfileList <string>           # Comma-separated Lab Profile IDs (ParameterSet: Profiles)
-FindList <string>                 # Comma-separated search terms (required)
-FindType <string>                 # Search mode: Exact|StartsWith|EndsWith|Contains (default: Contains)
-CaseType <string>                 # Case handling: None|Lower|Upper|Camel|Any (default: None)
-DevComplete                       # Only search profiles with "Complete" development status
-checkACPs                         # Search Access Control Policies
-checkLCAs                         # Search Life Cycle Actions
-checkActivities                   # Search Automated Activities
-checkInstructionsAndSwaps         # Search Instructions and Text Swaps (default if no checkXXX specified)
```

### Examples

**Search for a term across multiple Lab Series:**
```powershell
.\find-text.ps1 `
  -LabSeriesList "123,456,789" `
  -FindList "PowerShell,Azure,Resource" `
  -FindType "Contains" `
  -CaseType "Any" `
  -checkInstructionsAndSwaps
```

**Search completed profiles only:**
```powershell
.\find-text.ps1 `
  -LabProfileList "1000,2000,3000" `
  -FindList "TODO,FIXME" `
  -DevComplete `
  -checkLCAs `
  -checkActivities
```

**Search for compound terms (AND logic):**
```powershell
.\find-text.ps1 `
  -LabProfileList "5000" `
  -FindList "Azure&&Subscription" `
  -FindType "Contains" `
  -checkInstructionsAndSwaps -checkACPs
```

### Report Generation (Report-FindText.ps1)

```powershell
$result = & .\Report-FindText.ps1 `
  -OutputText $outputFromFindText `
  -OutputFolder "C:\Reports" `
  -BaseName "Find-Text_Combined" `
  -OpenHtml
```

**Returns:**
- CombinedCsv — Path to merged CSV file
- HtmlReport — Path to formatted HTML report
- ReportCount — Number of successfully combined reports
- RowCount — Total data rows in combined report
- MatchCount — Rows with matches found
- MissingReports — Array of reports that could not be read

## Output Files

### CSV Format
```
LabSeries,LabSeriesName,LabProfile,LabProfileName,Location,Term,Found
123,My Lab Series,1000,Lab Profile A,Instructions (456),PowerShell,5
123,My Lab Series,1000,Lab Profile A,LCA (789 - Setup Script),Azure,3
```

### HTML Report Features
- **Summary cards** — Overview statistics at the top
- **Search parameters** — Recap of search settings used
- **Source reports** — List of input CSV files combined
- **Interactive table** — Sortable columns, text filtering, match highlighting
- **Responsive design** — Works on desktop and mobile devices

## Use Cases

- **Content audits** — Find all references to deprecated technologies across labs
- **Compliance checks** — Verify required keywords or disclaimers appear in lab content
- **Migration tracking** — Find all instances of old URLs or tool names
- **Quality assurance** — Locate incomplete sections (TODO, FIXME comments)
- **Analysis** — Determine which labs use specific features or configurations
- **Replacement prep** — Identify all locations where content needs updating

## Workflow

1. **Configure search** — Specify:
   - Lab Series or Profiles to search
   - Terms to find
   - Search type and case sensitivity
   - Which content areas to examine

2. **Execute search** — Run find-text.ps1
   - Connects to Skillable Studio
   - Queries Lab Profile metadata and content
   - Processes Instructions Sets, LCAs, Activities, ACPs
   - Downloads external/GitHub-hosted instructions
   - Generates CSV report

3. **Generate report** — Run Report-FindText.ps1
   - Combines multiple CSV files
   - Merges data with unified schema
   - Generates interactive HTML report
   - Optionally opens in browser

4. **Analyze results** — Use HTML report to:
   - Sort by any column
   - Filter with free-text search
   - Toggle "only show matches" filter
   - Export data for further analysis

## Requirements

- **Skillable Studio** — Valid connection and authentication
- **PowerShell** — 5.0 or later
- **Skillable PowerShell Module** — LOD cmdlets (Connect-LabOnDemand, Get-LODLabProfile, etc.)
- **Web access** — For downloading external/GitHub-hosted instructions
- **UTF-8 encoding** — CSV and HTML files use UTF-8

## Configuration

The utility is primarily configured through command-line parameters. Configuration options include:

- `FindType` — How to match terms (word boundaries, prefix/suffix, substring)
- `CaseType` — How to handle case sensitivity
- Search scope — Which content areas to examine
- `DevComplete` — Filter by development status

## Error Handling

The script includes:
- Connection retry logic with configurable attempts
- Graceful handling of inaccessible Lab Profiles
- Web request error recovery for external instructions
- Detailed error logging with timestamps
- Fallback for missing or unreadable reports

## Notes

- Lab Series names are cached to reduce API calls
- External instructions (GitHub/cloud-hosted) are downloaded during search
- Labs with inherited instructions are reported but skipped
- ACP searches only apply to Azure cloud profiles
- LCA searches skip inherited Life Cycle Actions
- Generated report files use timestamp-based naming to prevent overwrites
- The HTML report includes a "Source reports" section to track data provenance

## License

Licensed under the GNU General Public License v3.0 (GPLv3)

## Related Project

Find-Text is part of the PLD (Program Lab Development) script library and is designed to support lab content analysis, quality assurance, and maintenance within the Skillable platform.
