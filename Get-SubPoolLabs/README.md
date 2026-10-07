# Get-SubPoolLabs

`Get-SubPoolLabs.ps1` reports which Cloud Subscription Pool, if any, each Lab Profile in a set of Lab Series or Lab Profiles uses in Skillable Studio. You give it a comma-separated list of Lab Series IDs or Lab Profile IDs. It looks up each Lab Profile and writes the series, the profile, and the profile's Cloud Subscription Pool ID and name to a timestamped CSV file.

| | |
|---|---|
| **Author** | Wayne Klapwyk (WKUtils) |
| **Built with** | SAPIEN PowerShell Studio 2024 v5.8.243 |
| **Runtime** | Windows PowerShell 5.1 |

## Contents

| File | Purpose |
|---|---|
| `Get-SubPoolLabs.ps1` | Connects to Skillable Studio, resolves the requested Lab Series or Lab Profiles, and exports each profile's Cloud Subscription Pool ID and name to `Sub_Report_<timestamp>.csv`. |

## Prerequisites

- Windows PowerShell 5.1. The script defines a PowerShell class, so it needs version 5.0 or later.
- The Skillable **LOD.Core** PowerShell module, installed so it auto-loads. The script uses `Connect-LabOnDemand`, `Get-LODLabSeries`, `Search-LODLabProfile`, and `Get-LODLabProfile`.
- A Skillable Studio account with access to the Lab Series and Lab Profiles you want to report on. The script opens the interactive `Connect-LabOnDemand` sign-in when it starts.

## Usage

The script has two modes. Use exactly one of the two parameters per run.

```powershell
# By Lab Series: every Lab Profile in each enabled series
.\Get-SubPoolLabs.ps1 -LabSeriesList "12345,23456"

# By Lab Profile: only the profiles listed
.\Get-SubPoolLabs.ps1 -LabProfileList "171948,171949,171950"
```

| Parameter | Type | Mode | Description |
|---|---|---|---|
| `LabSeriesList` | string | Series | Comma-separated Lab Series IDs. Each entry is reduced to its first run of digits, so entries such as `12345 - Azure Fundamentals` also work. |
| `LabProfileList` | string | Profiles | Comma-separated Lab Profile IDs. Entries must be plain numbers. |

Running the script with neither parameter fails, because both parameters are mandatory within their own parameter set and no default set is defined, so PowerShell cannot choose a mode.

## How it works

In **Series** mode, the script retrieves each Lab Series and skips any series that is disabled. For each enabled series, it lists the series' Lab Profiles with `Search-LODLabProfile` and then retrieves each profile individually.

In **Profiles** mode, it retrieves each listed Lab Profile directly.

Every Studio call is retried once after a one-second pause before the error is logged. Errors are written to the console, and processing moves on to the next series or profile, so one bad ID does not stop the run.

## Output

The script writes `Sub_Report_yyyyMMdd_HHmmss.csv` to the **current working directory**, not the script's folder. The file is UTF-8 with a BOM and contains one row per Lab Profile that was retrieved, whether or not the profile uses a Cloud Subscription Pool:

| Column | Content |
|---|---|
| `LabSeries` | Series mode: `(<entry as typed>) <Series Name>`. Profiles mode: the profile's numeric Series ID only. |
| `LabProfile` | `(<Profile ID>): <Profile Name>` |
| `PoolId` | The profile's Cloud Subscription Pool ID. A profile without a pool shows `0`. |
| `PoolName` | The profile's Cloud Subscription Pool name. Blank for a profile without a pool. |

To list only profiles that use a pool, filter the CSV on `PoolId` not equal to `0`.

Progress and errors are written to the console with a timestamp prefix. They are not saved to a log file.

## Known issues

These were found by reading the source in this folder and have not been fixed.

- **A failed series lookup can duplicate the previous series.** `$LabList` is not cleared between series. If `Search-LODLabProfile` fails for one series, the loop reprocesses the profiles from the previous series and labels them with the failed series' name.
- **The empty-result report errors instead of being written.** When no profiles are found, `Out-File -FilePath $rptName -Append "NO DATA FOUND"` passes the text as a positional argument that `Out-File` has no parameter for. PowerShell rejects the call, and no report file is created.
- **Sign-in failure does not stop the run.** `Connect-LabOnDemand` runs with `-ErrorAction Continue`, so a failed sign-in does not reach the `catch` block. The script continues, and every lookup fails.
- **Inconsistent `LabSeries` values between modes.** Series mode shows the series name. Profiles mode shows only the numeric Series ID.
- **Misnamed constructor.** The `PoolResult` class declares a method named `conResult` that appears to be intended as a constructor. Constructors must use the class name, so it is never called. The script uses the default constructor and sets properties directly.
- **Leftover code.** A commented-out header line still refers to `Eval ID`, and the variable `$x` is assigned but never used.
