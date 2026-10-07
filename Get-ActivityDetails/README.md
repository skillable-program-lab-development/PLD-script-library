# Get-ActivityDetails

This folder contains the Get-ActivityDetails utility, a PowerShell-based tool for extracting and reporting comprehensive metadata about Automated Activities configured in Skillable Studio Lab Profiles.

## Overview

Get-ActivityDetails enables users to:
- Retrieve detailed information about Lab Profile Activities across Lab Series or individual profiles
- Extract Activity metadata without including full script contents
- Generate organized CSV reports of Activity configurations
- Filter Activities by name or other criteria
- Support batch processing across multiple Lab Series and Profiles

## Components

### PowerShell Scripts

- **Get-ActivityDetails.ps1** — Main utility that queries Lab Profiles and extracts Activity metadata

## Features

### Data Extraction

Get-ActivityDetails collects the following information for each Activity:

- **Lab Series** — Parent Lab Series identifier
- **Lab Profile** — Parent Lab Profile identifier  
- **Activity ID** — Unique identifier for the Activity
- **Activity Name** — Display name of the Activity
- **Group ID** — Grouping identifier for organizing related Activities
- **Token Alias** — Token reference used in Lab Profile markup

### Filtering & Options

- **Lab Series queries** — Process all profiles within specified Lab Series
- **Lab Profile queries** — Process individual Lab Profiles by ID
- **Development status filtering** — Option to include only "Complete" status profiles
- **Activity name filtering** — Search for Activities matching specific names
- **Configurable output** — Save results to timestamped CSV files

## Usage

### Parameters (Get-ActivityDetails.ps1)

```powershell
-LabSeriesList <string>            # Comma-separated Lab Series IDs (ParameterSet: Series)
-LabProfileList <string>           # Comma-separated Lab Profile IDs (ParameterSet: Profiles)
-FindList <string>                 # Comma-separated search terms (required)
-FindType <string>                 # Search mode: Exact|StartsWith|EndsWith|Contains (default: Contains)
-CaseType <string>                 # Case handling: None|Lower|Upper|Camel (default: None)
-DevComplete                       # Only process profiles with "Complete" development status
-ActivityName <string>             # Filter Activities by name
```

### Examples

**Extract Activities from multiple Lab Series:**
```powershell
.\Get-ActivityDetails.ps1 `
  -LabSeriesList "123,456,789" `
  -FindList "Activity"
```

**Get Activities from specific Lab Profiles only:**
```powershell
.\Get-ActivityDetails.ps1 `
  -LabProfileList "1000,2000,3000" `
  -FindList "Setup,Verification"
```

**Filter by Activity name and development status:**
```powershell
.\Get-ActivityDetails.ps1 `
  -LabSeriesList "100" `
  -FindList "Activity" `
  -ActivityName "Configuration" `
  -DevComplete
```

## Output Format

### CSV Report

Generated with the following columns:

```
LabSeries,LabProfile,ID,Name,GroupId,TokenAlias
123,1000,456,Deploy-Application,1,Deploy
123,1000,457,Configure-Network,1,Configure
123,2000,458,Verify-Resources,2,Verify
```

### Output Files

Reports are saved with timestamp-based naming:
- Location: Script directory (or temp folder if using Program Files)
- Format: `Get-ActivityDetails_Report_YYYYMMDD_HHMMSS.csv`
- Encoding: UTF-8

## Workflow

1. **Connect** — Authenticate to Skillable Studio
2. **Query** — Retrieve Lab Series/Profiles metadata
3. **Enumerate** — Extract Activity details from each profile
4. **Compile** — Aggregate results into unified dataset
5. **Export** — Write CSV report with timestamp
6. **Report** — Display summary and output path

## Requirements

- **Skillable Studio** — Valid connection and authentication
- **PowerShell** — 5.0 or later
- **Skillable PowerShell Module** — LOD cmdlets (Connect-LabOnDemand, Get-LODLabProfile, Get-LODLabProfileActivity)
- **Permissions** — Read access to Lab Series and Lab Profiles
- **Storage** — Write access to output directory

## Use Cases

- **Activity inventory** — Create complete catalog of all Activities in a lab environment
- **Configuration audits** — Review Activity structure and relationships
- **Migration preparation** — Map Activities for lab duplication or updates
- **Documentation** — Generate reference material for lab structure
- **Compliance** — Verify Activity naming conventions and organization
- **Troubleshooting** — Identify Activities by various attributes

## Error Handling

The script includes:
- Connection retry logic for transient failures
- Graceful handling of inaccessible Lab Profiles
- Detailed logging with timestamps
- Development status validation
- Inheritance tracking (Activities from parent profiles)

## Notes

- Activities include metadata only; script contents are NOT included in output
- Disabled Lab Profiles are skipped with appropriate logging
- Lab Profiles with inherited Activities report their parent relationship
- Activity IDs and Group IDs provide hierarchical organization context
- Token Alias field indicates how the Activity is referenced in lab markup
- Generated reports use CSV format for compatibility with analysis tools

## Limitations

- Script contents of Activities are not extracted (use Find-Text utility for script analysis)
- External/referenced Activities may require manual investigation
- Activity execution order and dependencies not captured in basic metadata

## Related Utilities

- **Find-Text** — Search for specific terms within Activity scripts
- **Get-Instructions** — Extract and analyze lab instructions
- **Cloud Harbor** — Analyze deployed cloud resources from lab activities

## License

Licensed under the GNU General Public License v3.0 (GPLv3)

## Related Project

Get-ActivityDetails is part of the PLD (Program Lab Development) script library and is designed to support lab configuration analysis and maintenance within the Skillable platform.
