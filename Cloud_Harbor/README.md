# Cloud Harbor

This folder contains the Cloud Harbor Resource Scraper utility, a comprehensive suite of PowerShell tools for gathering, processing, and reporting on Azure cloud resources deployed during lab sessions.

## Overview

Cloud Harbor provides an automated workflow for:
- Querying Azure subscriptions to collect resource information
- Processing and analyzing resource deployment data
- Generating HTML reports and JSON configuration files
- Creating deployment tracking and audit reports

## Components

### PowerShell Scripts

- **control-AzureScrape.ps1** — Master orchestration script that coordinates the resource scraping workflow
- **get-ResourceScrape.ps1** — Queries Azure subscription and gathers resource data into JSON format
- **process-ResourceScrape.ps1** — Processes collected resource data and generates reports

### Configuration Files

- **ResourceScrape.ini** — Configuration settings for the resource scraper utility
- **rules.xml** — Processing rules for resource classification and analysis
- **rules-alt.xml** — Alternative processing rules for specialized scenarios
- **styles.css** — Stylesheet definitions for HTML report formatting

### UI & Deployment

- **Cloud Harbor.psf** — PowerShell Studio form file for the Cloud Harbor UI
- **Cloud Harbor.msi** — Installer package for deploying Cloud Harbor
- **resourceScraper.ico** — Application icon

### Assets & Resources

- **images/** — Directory containing logo and UI assets
  - Cloud_Harbor_White.png, Cloud_Harbor_White_64.ico, Cloud_Harbor_White_64.png
  - Cloud_Harbor_transparent.png, Cloud_Harbor_transparent_64.ico, Cloud_Harbor_transparent_64.png
  - compress.png, compress folder.png
- **background_ResourceScraper.png** — Background image for the scraper UI
- **background_ResourceScraper-Clouds.png** — Alternative cloud-themed background
- **banner_ResourceScraper.png** — Banner image for reports
- **Skillable Cloud Harbor Cert Request.txt** — Certificate request documentation
- **chversions.ver** — Version tracking file

### Documentation

- **LICENSE** — GNU General Public License v3 (GPLv3)

## Workflow

The Cloud Harbor workflow follows this process:

1. **control-AzureScrape.ps1** starts the orchestration
2. **get-ResourceScrape.ps1** connects to Azure and collects resource metadata
3. Collected resources are temporarily stored in JSON format
4. **process-ResourceScrape.ps1** processes the JSON data
5. Processing generates:
   - HTML report of resource deployment
   - Initial ACP (Azure Configuration Plan) JSON file
   - Detailed statistics and logging
6. All outputs are compressed into a ZIP file for delivery/archival

## Usage

### Parameters (control-AzureScrape.ps1)

```powershell
-SubscriptionId <GUID>     # Azure Subscription ID (required)
-Username <email>           # Azure account email (required)  
-Password <string>          # Azure account password
-OutPath <string>           # Output directory path
-Details                    # Display verbose console messages
-Stamp                      # Append timestamp to output folder/files
```

### Example

```powershell
.\control-AzureScrape.ps1 `
  -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -Username "user@domain.com" `
  -Password "SecurePassword123" `
  -OutPath "C:\Reports" `
  -Stamp -Details
```

## Features

- **Azure Integration** — Connects directly to Azure subscriptions using PowerShell Az module
- **Resource Enumeration** — Gathers comprehensive metadata on all deployed resources
- **Tag Processing** — Captures and analyzes custom resource tags
- **Property Collection** — Extracts detailed resource configuration data via Azure REST API
- **Duplicate Detection** — Identifies and filters duplicate resource records
- **HTML Reporting** — Generates human-readable deployment reports
- **JSON Export** — Produces structured data for further processing or integration
- **Status Tracking** — Creates status files (success.log, failed.log, etc.) for automation integration
- **Logging** — Comprehensive logging of all operations with timestamped entries

## Output Files

- **resourcescrape_[timestamp].json** — Raw resource data collection
- **resourcescrape_[timestamp].html** — Formatted HTML report
- **initialACP_[timestamp].json** — Initial Azure Configuration Plan
- **resources.zip** — Compressed archive containing all outputs
- **resourceControl.log** — Control script execution log
- **resourceScrape.log** — Resource gathering log
- **resourceProcessor.log** — Resource processing log
- **CountFile.cnt** — Statistics file with processing metrics

## Requirements

- **Azure Subscription** — Valid Azure subscription with appropriate permissions
- **PowerShell** — PowerShell 5.0 or later
- **Azure Az Module** — Microsoft.PowerShell.Az module installed
- **Credentials** — Valid Azure account credentials (username/password or TAP token)

## Configuration

Edit `ResourceScrape.ini` to customize:
- Resource filtering rules
- Report generation options
- Processing parameters
- Output formatting

Modify `rules.xml` or `rules-alt.xml` to define:
- Resource classification logic
- Property extraction rules
- Tag-based categorization

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3) — see the LICENSE file for full details.

## Related Project

Cloud Harbor is part of the PLD (Program Lab Development) script library and is designed to support automated resource inventory, compliance reporting, and lab environment analysis within the Skillable platform.

## Notes

- The utility requires the Azure Az PowerShell module to be installed
- Web-based login is used by default for authentication
- Temporary Access Passes (TAP) tokens are supported as an alternative authentication method
- The scraper monitors for a FlagFile.chk marker — removing this file stops the scraping process
- Resource data is continuously polled while FlagFile.chk exists
- All operations are logged for audit and troubleshooting purposes
