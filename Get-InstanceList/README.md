# Get-InstanceList

This folder contains the Get-InstanceList utility, a PowerShell-based tool for exporting comprehensive lab instance metadata from Skillable Studio Lab Profiles and Lab Series.

## Overview

Get-InstanceList enables users to:
- Export detailed lab instance information for one or more Lab Profiles
- Discover Lab Profiles from Lab Series and retrieve their instances
- Generate organized CSV reports with instance launch history
- Filter instances by launch type (All, Last, or None)
- Optionally include Lab Profile metadata in instance reports
- Support large-scale batch processing across multiple series and profiles

## Components

### PowerShell Scripts

- **Get-InstanceList.ps1** — Main utility that queries lab instances and exports results to CSV

## Features

### Data Extraction

Get-InstanceList collects comprehensive instance information including:

- **Instance ID** — Unique identifier for the lab instance
- **Lab Profile ID** — Parent Lab Profile identifier
- **Start Time** — When the instance was launched
- **Status** — Current state of the instance
- **Launch Details** — Complete launch history and metadata
- **Optional Profile Metadata** — Profile name, enabled status, organization details, cloud platform

### Query Modes

- **By Lab Profiles** — Direct Lab Profile ID list (fastest)
- **By Lab Series** — Discover profiles within series, then get instances
- **Series-to-Instance pipeline** — Automatic discovery and processing

### Launch Type Filtering

- **All** — Export all instance launches (default)
- **Last** — Export only the most recent launch per profile
- **None** — Export only profiles with zero launches (unused labs)

### Output Options

- **Profile Metadata** — Optionally include Lab Profile fields in each row
- **Timestamped naming** — Automatic CSV naming with execution timestamp
- **Custom output path** — Specify output directory and filename
- **UTF-8 encoding** — Cross-platform compatibility

## Usage

### Parameters (Get-InstanceList.ps1)

```powershell
-LabProfileList <string>         # Comma-separated Lab Profile IDs (ParameterSet: ByProfiles)
-LabSeriesList <string>          # Comma-separated Lab Series IDs (ParameterSet: BySeries)
-OutCsv <string>                 # Output CSV file path (default: LabInstanceDetails_YYYYMMDD_HHMMSS.csv)
-IncludeProfileMetadata          # Add Lab Profile fields to each instance row
-LaunchType <string>             # Filter: All|Last|None (default: All)
```

**Note:** Use either `-LabProfileList` OR `-LabSeriesList`, not both.

### Examples

**Export all instances for specific profiles:**
```powershell
.\Get-InstanceList.ps1 `
  -LabProfileList "211388,211389" `
  -OutCsv ".\instances.csv"
```

**Get instances from Lab Series with profile metadata:**
```powershell
.\Get-InstanceList.ps1 `
  -LabSeriesList "39687,39688" `
  -OutCsv ".\instances.csv" `
  -IncludeProfileMetadata
```

**Find unused labs (no launches):**
```powershell
.\Get-InstanceList.ps1 `
  -LabSeriesList "39687" `
  -LaunchType "None" `
  -OutCsv ".\unused_profiles.csv"
```

**Export only the last launch per profile:**
```powershell
.\Get-InstanceList.ps1 `
  -LabProfileList "211388,211389,211390" `
  -LaunchType "Last" `
  -OutCsv ".\last_launches.csv"
```

## Output Format

### CSV Report Structure

**Basic output (without profile metadata):**
```
LabProfileId,StartTime,Status,UserId,UserName,...
211388,2026-03-15T10:30:00Z,Completed,12345,john.doe@example.com,...
211388,2026-03-14T14:15:00Z,Completed,12346,jane.smith@example.com,...
211389,2026-03-15T09:45:00Z,Running,12347,bob.jones@example.com,...
```

**With profile metadata (`-IncludeProfileMetadata`):**
```
LabProfileId,LabProfileName,LabProfileEnabled,LabProfileOrgId,LabProfileOrgName,LabProfilePlatform,StartTime,Status,...
211388,Azure Fundamentals,True,1001,Acme Corp,Azure,2026-03-15T10:30:00Z,Completed,...
211389,AWS Basics,True,1001,Acme Corp,AWS,2026-03-15T09:45:00Z,Running,...
```

**With LaunchType=Last (most recent only):**
```
LabProfileId,StartTime,Status,UserId,...
211388,2026-03-15T10:30:00Z,Completed,12345,...
211389,2026-03-15T09:45:00Z,Running,12347,...
```

**With LaunchType=None (unused profiles):**
```
LabProfileId,LaunchCount,LabProfileName,LabProfileEnabled,...
211390,0,Database Fundamentals,True,...
211391,0,Python Basics,False,...
```

### Output Files

- **Location:** Current working directory or `-OutCsv` specified path
- **Format:** `LabInstanceDetails_YYYYMMDD_HHMMSS.csv`
- **Encoding:** UTF-8
- **Type Info:** Not included (clean CSV)
- **Auto-creation:** Output directory created if it doesn't exist

## Workflow

1. **Connect** — Authenticate to Skillable Studio
2. **Discover** — If using Lab Series:
   - Query each series for Lab Profiles
   - Deduplicate profile IDs
   - Build unified profile list
3. **Query** — For each Lab Profile:
   - Retrieve instance list via Search-LODLabInstance
   - Sort by StartTime (newest first)
   - Apply LaunchType filter
4. **Enrich** — If `-IncludeProfileMetadata`:
   - Attach profile name, status, organization, platform
5. **Export** — Stream results to CSV:
   - Write headers on first row
   - Append subsequent rows
   - Handle mixed launch counts
6. **Report** — Display summary and output path

## Requirements

- **Skillable Studio** — Valid connection and authentication
- **PowerShell** — 5.0 or later with strict mode support
- **Skillable PowerShell Module** — LOD cmdlets:
  - Connect-LabOnDemand
  - Get-LODLabProfile
  - Search-LODLabProfile
  - Search-LODLabInstance
- **Permissions** — Read access to Lab Instances
- **Storage** — Write access to output directory

## Data Structure

The script processes data through these stages:

```
Lab Series IDs
    ↓
Search-LODLabProfile (per series)
    ↓
Lab Profile IDs (deduplicated)
    ↓
Search-LODLabInstance (per profile)
    ↓
Instance Results (with optional profile metadata)
    ↓
CSV Export (UTF-8)
```

## Features & Capabilities

### ID Deduplication
- Removes duplicate Lab Profile IDs from series discovery
- Preserves order for consistent processing

### Error Handling
- Graceful handling of failed profile/instance queries
- Continues processing on individual failures
- Warnings for skipped/failed profiles
- Detailed error messaging

### Performance
- Streams CSV output (doesn't load entire result set in memory)
- Efficient instance sorting (by StartTime descending)
- Batch processing across multiple profiles/series

### Launch Type Logic

**All (default)** — Export every instance launch
- Use for: Complete audit trail, analysis, compliance

**Last** — One row per profile (most recent launch)
- Use for: Quick status check, trend analysis

**None** — Only profiles with zero launches
- Use for: Finding unused labs, utilization reporting

## Use Cases

- **Audit Trail** — Complete record of all lab launches
- **Usage Analytics** — Track which labs are most used
- **Utilization Report** — Identify unused or underutilized labs
- **Status Check** — Quick overview of recent launches
- **Compliance** — Document lab usage for audit purposes
- **Troubleshooting** — Analyze launch failures and patterns
- **Migration Planning** — Assess profile activity before changes
- **Performance Baselines** — Track launch frequency over time

## Notes

- Instances are sorted by StartTime in descending order (newest first)
- Profile metadata is cached during Lab Series discovery
- Lab Series must be enabled to retrieve profiles
- Disabled Lab Profiles still report instances (historical data)
- Instance count uses TotalCount from API when available
- "No launches" profiles are only exported with `-LaunchType None`
- CSV schema is determined by first row written (headers)

## Limitations

- Cannot combine multiple launch types in single run (use separate invocations)
- Does not filter instances by date range (export all by default)
- Instance details depend on Skillable Studio data availability
- Lab Series/Profile IDs must be numeric (format validation not enforced)

## Error Recovery

If the script encounters errors:

- **Connection issues** — Retry connection or check credentials
- **Missing profiles** — Verify Lab Series/Profile IDs exist and are enabled
- **No instances found** — Check if profiles have been launched
- **CSV write errors** — Verify output directory exists and is writable

## Related Utilities

- **Find-Text** — Search instance-related content
- **Get-ActivityDetails** — Extract Activity metadata
- **Get-Evaluations** — Retrieve evaluation assignments
- **Cloud Harbor** — Analyze deployed resources

## Troubleshooting

### "No Lab Profile IDs were discovered"
- Verify Lab Series IDs are correct
- Check that series contains profiles
- Ensure profiles are not all disabled

### "No Lab Instances found"
- Lab profile may be new with no launches
- Check lab profile is enabled
- Verify users have permission to launch

### CSV file not created
- Check output directory permissions
- Verify disk space available
- Ensure output path is valid

### Profile metadata shows null values
- Profile not found in cache (query failed)
- Try without `-IncludeProfileMetadata`
- Verify Lab Profile IDs are valid

## License

Licensed under the GNU General Public License v3.0 (GPLv3)

## Development Notes

- Created with SAPIEN PowerShell Studio 2025
- Uses strict mode for robust error handling
- Includes AI-assisted development validated by human review
- Optimized for processing large instance datasets

## Related Project

Get-InstanceList is part of the PLD (Program Lab Development) script library and is designed to support lab usage analysis, reporting, and maintenance within the Skillable platform.
