# Get-Evaluations

This folder contains the Get-Evaluations utility, a PowerShell-based tool for retrieving and reporting evaluation configurations associated with Skillable Studio Lab Profiles.

## Overview

Get-Evaluations enables users to:
- Query one or more Lab Series to extract evaluation information
- Retrieve evaluation IDs assigned to individual Lab Profiles
- Generate organized CSV reports of evaluation assignments
- Support batch processing across multiple Lab Series and Profiles
- Identify which Labs use specific evaluations

## Components

### PowerShell Scripts

- **get-Evaluations.ps1** — Main utility that queries Lab Profiles and extracts evaluation identifiers

## Features

### Data Extraction

Get-Evaluations collects the following information for each Lab Profile:

- **Lab Series** — Parent Lab Series identifier and name
- **Lab Profile** — Lab Profile identifier, ID, and display name
- **Evaluation ID** — The evaluation ID assigned to the profile (if any)

### Filtering & Options

- **Lab Series queries** — Process all profiles within specified Lab Series
- **Lab Profile queries** — Process individual Lab Profiles by ID
- **Null handling** — Reports null/empty evaluation IDs for profiles without evaluations
- **Batch processing** — Handle multiple series/profiles in single run

## Usage

### Parameters (get-Evaluations.ps1)

```powershell
-LabSeriesList <string>     # Comma-separated Lab Series IDs (ParameterSet: Series)
-LabProfileList <string>    # Comma-separated Lab Profile IDs (ParameterSet: Profiles)
```

**Note:** Use either `-LabSeriesList` OR `-LabProfileList`, not both.

### Examples

**Retrieve evaluations for all profiles in Lab Series:**
```powershell
.\get-Evaluations.ps1 -LabSeriesList "123,456,789"
```

**Get evaluation IDs for specific Lab Profiles:**
```powershell
.\get-Evaluations.ps1 -LabProfileList "1000,2000,3000"
```

**Process a single Lab Series:**
```powershell
.\get-Evaluations.ps1 -LabSeriesList "100"
```

**Process a single Lab Profile:**
```powershell
.\get-Evaluations.ps1 -LabProfileList "5000"
```

## Output Format

### CSV Report

Generated with the following columns:

```
LabSeries,LabProfile,EvalId
(123) My Lab Series 1,(1000): Lab Profile A,456
(123) My Lab Series 1,(1001): Lab Profile B,457
(123) My Lab Series 1,(1002): Lab Profile C,
(456) My Lab Series 2,(2000): Lab Profile D,789
```

### Output Details

- **LabSeries** — Series ID and name in format `(ID) Name`
- **LabProfile** — Profile ID and name in format `(ID): Name`
- **EvalId** — Numeric evaluation ID, or empty if no evaluation assigned
- **Empty values** — Profiles without evaluations show blank EvalId field

### Output Files

Reports are saved in the current script directory with timestamp-based naming:
- Format: `Eval_Report_YYYYMMDD_HHMMSS.csv`
- Encoding: UTF-8
- No type information headers

### No Data Scenario

If no results are found, the report contains:
```
NO DATA FOUND
```

## Workflow

1. **Connect** — Authenticate to Skillable Studio
2. **Query** — Retrieve Lab Series or Lab Profiles
3. **Extract** — Get evaluation ID from each profile
4. **Compile** — Aggregate results into collection
5. **Export** — Write CSV report with timestamp
6. **Report** — Display completion message

## Requirements

- **Skillable Studio** — Valid connection and authentication
- **PowerShell** — 5.0 or later
- **Skillable PowerShell Module** — LOD cmdlets:
  - Connect-LabOnDemand
  - Get-LODLabSeries
  - Get-LODLabProfile
  - Search-LODLabProfile
- **Permissions** — Read access to Lab Series and Lab Profiles
- **Storage** — Write access to script directory

## Use Cases

- **Evaluation inventory** — Create catalog of all evaluations in use
- **Audit trail** — Track which profiles use specific evaluations
- **Migration planning** — Identify evaluations that need to be migrated
- **Quality assurance** — Verify evaluation assignment compliance
- **Configuration review** — Document evaluation relationships
- **Troubleshooting** — Identify profiles with missing evaluations

## Error Handling

The script includes:
- Connection retry logic for transient API failures
- Graceful handling of disabled Lab Series
- Detailed logging with timestamps
- Error reporting for individual profile failures
- Continuation on partial failures

## Data Structure

The utility uses the `EvalResult` class to organize results:

```powershell
class EvalResult {
    [string]$LabSeries      # Series identifier
    [string]$LabProfile     # Profile identifier and name
    [int]$EvalId            # Evaluation ID (may be null)
}
```

## Notes

- Evaluation IDs can be null/empty if no evaluation is assigned to a profile
- Disabled Lab Series are reported and skipped
- Processing continues even if individual profiles fail
- Lab Series names are included in output for context
- Profile IDs are formatted as `(ID): Name` for clarity
- Report timestamps use format `YYYYMMDD_HHMMSS` to prevent overwrites

## Limitations

- Only retrieves evaluation IDs; evaluation details must be queried separately
- Does not validate whether evaluation IDs are still active/valid
- Does not report evaluation content or configuration
- Cannot filter profiles by evaluation ID in this utility

## Related Utilities

- **Find-Text** — Search for specific content within profiles
- **Get-ActivityDetails** — Extract Activity metadata
- **Get-Instructions** — Retrieve lab instructions
- **Get-OrganizationObjects** — Query organizational structure

## Troubleshooting

### "FAILED TO CONNECT" Error

Ensure you have:
- Valid Skillable Studio credentials
- Network connectivity to Skillable Studio
- Required PowerShell modules installed
- Proper permissions in Skillable Studio

### Empty Report ("NO DATA FOUND")

Check that:
- Lab Series/Profile IDs are correct
- Specified Series/Profiles exist and are enabled
- You have read access to the resources
- The Lab Series is not empty

### Missing Results

Verify:
- Lab Series/Profiles are enabled in Studio
- Profiles have been fully loaded and indexed
- Series/Profile IDs are properly formatted
- No API connectivity issues

## License

Licensed under the GNU General Public License v3.0 (GPLv3)

## Related Project

Get-Evaluations is part of the PLD (Program Lab Development) script library and is designed to support lab configuration management and auditing within the Skillable platform.
