# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A set of equivalent utility scripts (bash, zsh, PowerShell) that reorganise the [TOSEC ZX Spectrum collection](https://archive.org/details/zx_spectrum_tosec_set_september_2023) into a folder structure compatible with [The Spectrum](https://retrogames.biz/products/thespectrum/) retro console, then download the original Spectrum ROMs from FBZX.

## Running the Scripts

Scripts must be run from the directory containing the script and the TOSEC `Demos/` and `Games/` folders (or their `Demos.zip`/`Games.zip` archives, which are extracted automatically).

**Linux/macOS — bash:**
```bash
chmod +x thespectrum-util.bash
./thespectrum-util.bash
```

**Linux/macOS — zsh:**
```bash
chmod +x thespectrum-util.zsh
./thespectrum-util.zsh
```

**Windows — PowerShell:**
```powershell
powershell.exe -ExecutionPolicy Bypass
.\thespectrum-util.ps1
```

## How the Scripts Work

All three scripts implement the same logic for two TOSEC collections. Games use the `process_source`/`Invoke-ProcessSource` bucketing helper; Demos use `process_demo_list`/`Invoke-ProcessDemoList` (see **Demos list** below). Both share `move_title_files`/`Move-TitleFiles`:

| Collection | Archive | Source | Destination |
|---|---|---|---|
| TOSEC Demos | `Demos.zip` | `Demos/` | `THESPECTRUM/TOSEC-Demos/` (filtered, flat — see below) |
| TOSEC Games | `Games.zip` | `Games/` | `THESPECTRUM/TOSEC-Games/` |

1. **Automatic extraction**: `require_extracted`/`Assert-Extracted` checks whether the source folder exists; if not and the archive is present, it extracts it into `.` (both archives contain a wrapping `Demos/` or `Games/` folder at the root). Bash/zsh extract only the scoped paths (`Demos/*`, `Games/*`) with `unzip`, retry with `7z`/`7zz` if `unzip` errors (e.g. non-UTF-8 filenames), then fall back to a full extraction with a warning. PowerShell uses the built-in `Expand-Archive`.
2. **Input validation**: Exits with an error if a source folder is still not found (neither folder nor archive present).
3. **Input** (Games): Each subdirectory of the source folder is a title.
4. **Filtering** (Games): Skips entries whose name starts with `!` (TOSEC uses this prefix for non-game entries).
5. **Bucketing** (Games only; Demos are not bucketed): Groups titles alphabetically — digits map to `#`, letters to their uppercase initial. Within each letter bucket, titles are split into groups of 256 (e.g. `A0`, `A1`, `A2`…) because The Spectrum supports at most 256 files per folder. The bucket is taken from the *unsanitised* first character, so any other leading character becomes its own bucket (`#`-prefixed titles share `#0` with digits). Titles are bucketed in glob/`Get-ChildItem` sort order.
6. **Output**: Moves supported files (`tap`, `tzx`, `pzx`, `rom`, `szx`, `z80`, `sna`, `m3u`, matched case-insensitively) into `THESPECTRUM/TOSEC-Games/<bucket>/<title>/` (Games) or `THESPECTRUM/TOSEC-Demos/<nnn>. <title>/` (Demos). Title folders and filenames are sanitised on the way (see below). Empty destination directories are pruned after the move — note many TOSEC demos are TR-DOS (`scl`, `trd`) images, which are not supported and are left behind. Files are *moved*, not copied, so the source folders are consumed: a re-run finds empty title folders, and any collision with a previous run's output gets a ` (2)` suffix.
7. **ROMs**: Creates `THESPECTRUM/roms/` and downloads the seven Spectrum ROM files (48K, 128K, +3) from the FBZX GitHub repo. Bash/zsh (`curl -f`, no `set -e`) carry on past a failed download and still exit 0; PowerShell stops at the first failure with exit 1.

**Demos list**: Demos are not bucketed. `top200-demos.txt` (one TOSEC folder name per line, in rank order) is the filter, ranked by [Pouët](https://www.pouet.net/) popularity scores: only the listed folders are moved, flat, into `THESPECTRUM/TOSEC-Demos/<nnn>. <folder>/`, where `nnn` is the zero-padded line number (e.g. `001. Mescaline Synesthesia`). A listed folder missing from `Demos/` is skipped with a warning but still consumes its number; blank lines and trailing `\r` are ignored. Files are moved, not copied, as for Games. The script errors if the list file is missing.

**Filename sanitisation** (`sanitize_name`/`Get-SanitizedName`): destination names are made safe for the FAT32-formatted USB stick used by The Spectrum. Apostrophes and backticks are dropped (`BC's Quest` → `BCs Quest`); anything outside `A-Z a-z 0-9 space ( ) [ ] , . _ & + ! # -` becomes `_`; leading spaces and trailing spaces/dots are trimmed; title folders are truncated to 64 characters and filenames to 128 (extension preserved). If a sanitised filename already exists in the destination (compared case-insensitively, as FAT32 does), ` (2)`, ` (3)`… is appended. Every rename is logged as `Renamed: <old> -> <new>`. Non-ASCII characters become one `_` per byte in bash/zsh (`LC_ALL=C sed`) but one `_` per character in PowerShell — the TOSEC sets currently contain no non-ASCII names.

The `.gitignore` excludes `*.zip`, `Demos/`, `Games/` and `THESPECTRUM/` — these are large runtime artefacts, not source.

## Key Differences Between Script Variants

| | bash | zsh | PowerShell |
|---|---|---|---|
| Glob no-match handling | `shopt -s nullglob` | `setopt NULL_GLOB` | implicit |
| Case-insensitive extensions | `shopt -s nocaseglob` | `setopt NO_CASE_GLOB` | implicit |
| Archive extraction | `unzip` (scoped), `7z` retry | `unzip` (scoped), `7z` retry | `Expand-Archive` (whole archive, no fallback) |
| Filename sanitisation | `LC_ALL=C sed` | same as bash | `-replace` |
| Collision check | `name_taken` (case-insensitive `ls`/`grep`) | same as bash | `Test-Path -LiteralPath` (case-insensitive only because NTFS is) |
| `!` filter | assigns `file` then checks `${file:0:1}` | inline `${$(basename "$i"):0:1}` | `StartsWith('!')` |
| Digit→`#` mapping | `tr '[:digit:]' '#'` | `tr '[:digit:]' '#'` | regex match `'\d'` → `'#'` |
| Path separators | `/` | `/` | hard-coded `\` (Windows only, not `pwsh` on macOS/Linux) |
| ROM download | `curl -fO --output-dir`, continues on failure | same as bash | `Invoke-WebRequest` with try/catch, aborts on failure |

When making changes, keep all three scripts in sync with each other.