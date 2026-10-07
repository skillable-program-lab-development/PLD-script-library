# Add-Images

This folder contains a utility for adding a batch of image files to a Skillable Studio Lab Profile Instructions set.

## Contents

- Add-Images.ps1 — PowerShell script that validates a folder of images and uploads them to a specified lab profile and instructions set.
- Add-Images.psf — PowerShell Studio form/project file for the utility.
- WKUtils Add-Images.msi — packaged installer for the Add-Images tool.

## Purpose

The script is designed to:

- Validate that the selected image folder exists
- Find supported image files in the folder
- Connect to Skillable Studio
- Upload each image to the specified Lab Profile and Instructions Set

Supported file types include:
- .png
- .jpg
- .jpeg
- .bmp
- .gif

## Parameters

The script expects the following parameters:

- LabProfile — the Skillable Studio Lab Profile ID
- InstSetId — the Instructions Set ID
- ImageFolder — the directory containing the images to upload

## Example usage

```powershell
.\Add-Images.ps1 -LabProfile 12345 -InstSetId 6789 -ImageFolder "C:\Images\LabAssets"
```

## Notes

- If no supported image files are found in the selected folder, the script exits with a warning.
- After upload, the image paths in the Lab Instructions may need to be updated to reference the correct Instructions Set.
- The script uses the Skillable Studio PowerShell cmdlet Add-LODLabProfileInstructionsFile to upload the files.

## Related project

This utility is part of the PLD script library and is intended to streamline the process of importing image assets into lab instruction content.
