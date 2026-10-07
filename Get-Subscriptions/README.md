# Get-Subscriptions

`Get-Subscriptions.ps1` lists the Organization ID and Cloud Subscription Pool ID for every Lab Profile in a fixed set of Lab Series in Skillable Studio, and writes the results to a timestamped CSV file.

The Lab Series to scan are hard-coded in the script. It takes no parameters.

## Contents

| File | Purpose |
|---|---|
| `Get-Subscriptions.ps1` | Connects to Skillable Studio, lists the Lab Profiles in each hard-coded Lab Series, and appends each profile's Series ID, Lab Profile ID, Organization ID, and Cloud Subscription Pool ID to `Subscriptions<timestamp>.csv`. |

## Prerequisites

- Windows PowerShell 5.1.
- The Skillable **LOD.Core** PowerShell module, installed so it auto-loads. The script uses `Connect-LabOnDemand`, `Search-LODLabProfile`, and `Get-LODLabProfile`.
- A Skillable Studio account with access to the Lab Series listed in the script. The script opens the interactive `Connect-LabOnDemand` sign-in when it starts.

## Usage

1. Open `Get-Subscriptions.ps1` and edit the `$lstSeries` string on the first line. It is a comma-separated list of Lab Series IDs with no spaces. As committed, it contains 74 series IDs.
2. Change to the folder where you want the report written. The report goes to the current working directory.
3. Run the script:

   ```powershell
   .\Get-Subscriptions.ps1
   ```

The console shows progress as `Series n / total` and, under each series, `Profile n / total`.

## Output

The script writes `Subscriptions<yyyyMMdd_HHmmss>.csv` to the current working directory, with one row per Lab Profile found:

| Column | Content |
|---|---|
| `Series` | The profile's Lab Series ID. |
| `LP ID` | The Lab Profile ID. |
| `Org Id` | The Organization ID that owns the Lab Profile. |
| `Sub ID` | The profile's **Cloud Subscription Pool ID**, not an Azure or AWS subscription ID. Blank for a profile without a pool. |

Every profile in each series is included, whether or not it uses a Cloud Subscription Pool. Values are written exactly as returned, without CSV quoting.

## Related scripts

`Get-SubPoolLabs` reports the same Cloud Subscription Pool information and also includes the pool name. It accepts Lab Series or Lab Profile IDs as parameters, skips disabled series, and retries failed calls. It does not report the Organization ID. Use `Get-Subscriptions` when you need the Organization ID.

## Known issues

These were found by reading the source in this folder and have not been fixed.

- **The header and the first data row share a line.** `New-Item -Value` writes the header without a trailing line break, and `Add-Content` does not add one before the next value. The first profile's values are appended directly to the end of the header line, which corrupts the header and drops that profile from any CSV import. Write the header with `Set-Content` instead, which ends the line.
- **The series list is hard-coded.** Changing the scope means editing the script. There is no parameter or input file.
- **No error handling.** There is no `try`/`catch` or retry. A failed sign-in does not stop the run (`-ErrorAction Continue`), and a failed series or profile lookup writes an error and either produces a row with blank values or skips the series.
- **Disabled series are not skipped.** Every series in the list is scanned regardless of its status.
- **Misleading column name.** `Sub ID` holds the Cloud Subscription Pool ID.
- **Extra console output.** `New-Item` writes the created file's details to the console at the start of the run.
- **No comment-based help.** `Get-Help .\Get-Subscriptions.ps1` returns no description.
