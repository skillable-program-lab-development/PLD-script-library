# Indent-Markdown

Indent-Markdown indents everything that sits between numbered steps in a Markdown file. Notes, images, code blocks, and paragraphs then render as part of the step above them instead of breaking the numbered list. The original file is left unchanged, and the result is saved beside it with an `_indented` suffix.

| | |
|---|---|
| **Author** | Wayne Klapwyk (WKUtils) |
| **Version** | 1.0 |
| **Built with** | SAPIEN PowerShell Studio 2025 v5.9.261 |
| **Runtime** | Windows PowerShell 5.1 |

## Contents

| File | Purpose |
|---|---|
| `Indent-Markdown.ps1` | Reads the Markdown file, applies the indentation rules, and writes `<name>_indented<ext>` to the same folder. |
| `Indent-Markdown.cmd` | Drag-and-drop launcher. Runs `Indent-Markdown.ps1` from its own folder with `-NoProfile -ExecutionPolicy Bypass` and passes it the first file dropped on it. |

## Prerequisites

- Windows PowerShell 5.1. No modules or Skillable Studio connection are needed.
- `Indent-Markdown.cmd` and `Indent-Markdown.ps1` must be in the same folder.

## Usage

### Drag and drop

Drag one Markdown file onto `Indent-Markdown.cmd`. The indented copy is created next to the original.

The console window closes as soon as the script finishes, so the summary and any errors are not visible. Check the source file's folder for the `_indented` file, or run from a console if you need to see the output.

### Command line

```powershell
.\Indent-Markdown.ps1 -MarkdownPath 'C:\Labs\Lab01\instructions.md'

# The path can also be passed positionally
.\Indent-Markdown.ps1 'C:\Labs\Lab01\instructions.md'
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `MarkdownPath` | string | Yes | Path to an existing file. The script validates that it exists and is a file, not a folder. |

When it finishes, the script prints the path of the new file and a `Lines Processed` count.

## Indentation rules

The script reads the file one line at a time and applies the first rule that matches:

| Line | Action |
|---|---|
| Blank or whitespace-only | Written unchanged. |
| Starts with `#`, after any leading whitespace | Written unchanged. **Stops** indenting. |
| Starts with digits followed by a period, such as `1.` or `12.`, after any leading whitespace | Written unchanged. **Starts** indenting. |
| Any other line while indenting | Leading whitespace removed, then four spaces added. |
| Any other line while not indenting | Written unchanged. |

In practice, everything from the first numbered step down to the next heading is indented by exactly four spaces. Content before the first step, and content after a heading but before the next step, is not changed.

### Example

Input:

```markdown
# Exercise 1

1. Sign in to the portal.
Use the credentials below.
>[!NOTE] This can take a minute.
1. Open **Resource groups**.
```

Output:

```markdown
# Exercise 1

1. Sign in to the portal.
    Use the credentials below.
    >[!NOTE] This can take a minute.
1. Open **Resource groups**.
```

## Output

The script writes `<original name>_indented<original extension>` to the same folder as the source file, as UTF-8 without a BOM so it works cleanly with Git and Markdown renderers. An existing file with the same name is overwritten without a prompt. Lines are written with Windows (CRLF) line endings, whatever the source used.

## Known issues

These were found by reading the source in this folder and have not been fixed.

- **Code blocks inside a step can be damaged.** Every line in a code block is trimmed and given exactly four spaces, so any indentation inside the block is lost. This breaks YAML, Python, and nested JSON. A code line that starts with `#`, such as a PowerShell, Bash, or Python comment, also stops indenting, so the rest of the block and its closing fence are left at the margin.
- **Nested content is flattened.** Bullets, sub-steps, and other content that was already indented by more than four spaces are reduced to four spaces, so nesting levels are lost.
- **Any line starting with a number and a period starts a step.** Body text such as `2.5 GB is required` or `2026. Next year...` is treated as a new step and is not indented.
- **Indenting continues until the next heading.** A paragraph after the last step of a list, with no heading between them, is indented as if it belonged to that step.
- **`Lines Processed` is not a total.** It counts only the lines that are not blank, headings, or numbered steps, whether or not they were indented.
- **One file per run.** The launcher passes only the first dropped file. If you pass several paths directly to the script, they are joined into one string, which fails validation.
- **Results vanish on drag and drop.** The launcher has no `pause`, so the console window closes before you can read the summary or any error.
