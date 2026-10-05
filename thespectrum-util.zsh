#!/bin/zsh
setopt NULL_GLOB
setopt NO_CASE_GLOB

tosec_demos_archive="Demos.zip"
tosec_demos_src="Demos"
top_demos_list="top200-demos.txt"

tosec_games_archive="Games.zip"
tosec_games_src="Games"

require_7z() {
    if command -v 7z >/dev/null 2>&1; then
        echo 7z
    elif command -v 7zz >/dev/null 2>&1; then
        echo 7zz
    else
        echo "Error: 7z/7zz not found. Install p7zip to extract archives:" >&2
        echo "  macOS:         brew install p7zip" >&2
        echo "  Debian/Ubuntu: sudo apt install p7zip-full" >&2
        exit 1
    fi
}

require_unzip() {
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Error: unzip not found. Install it to extract archives:" >&2
        echo "  macOS:         brew install unzip (usually preinstalled)" >&2
        echo "  Debian/Ubuntu: sudo apt install unzip" >&2
        exit 1
    fi
}

# Extracts only the paths needed for $src_dir out of $archive into $dest_dir,
# if $src_dir doesn't already exist locally and $archive is present. Falls
# back to a full extraction (with a warning) if the scoped extraction didn't
# produce $src_dir. $scoped_paths are archive-internal paths, relative to the
# archive root (not to $dest_dir).
require_extracted() {
    local src_dir="$1"
    local archive="$2"
    local dest_dir="$3"
    shift 3
    local scoped_paths=("$@")

    [[ -d "$src_dir" ]] && return 0
    [[ -f "$archive" ]] || return 0

    echo "Extracting $archive..."
    require_unzip
    if ! unzip -q -o "$archive" "${scoped_paths[@]}" -d "$dest_dir"; then
        if command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; then
            echo "Warning: unzip reported errors extracting $archive (e.g. a non-UTF-8 filename in the archive); retrying the same paths with 7z." >&2
            local sevenzip
            sevenzip=$(require_7z)
            "$sevenzip" x "$archive" "${scoped_paths[@]}" -o"$dest_dir" -y >/dev/null
        fi
    fi
    if [[ ! -d "$src_dir" ]]; then
        echo "Warning: scoped extraction of $archive did not produce $src_dir; extracting entire archive instead." >&2
        unzip -q -o "$archive" -d "$dest_dir"
    fi

    if [[ ! -d "$src_dir" ]]; then
        echo "Error: extraction of $archive did not produce expected folder $src_dir" >&2
        exit 1
    fi
}

# Makes $1 safe to copy onto the FAT32-formatted USB stick used by The Spectrum:
# drops apostrophes/backticks, replaces anything outside a conservative ASCII
# set with "_", trims leading spaces and trailing spaces/dots, and truncates to
# $2 characters. When $3 is 1 the extension is kept intact and excluded from
# the sanitisation.
sanitize_name() {
    local name="$1" max="$2" keep_ext="$3" base="$1" ext=""
    if [[ "$keep_ext" -eq 1 && "$name" == ?*.* ]]; then
        base="${name%.*}"
        ext=".${name##*.}"
    fi
    base=$(printf '%s' "$base" | LC_ALL=C sed -e "s/[\`']//g" -e 's/[^]A-Za-z0-9 ()[,._&+!#-]/_/g')
    base="${base#"${base%%[! ]*}"}"
    base="${base:0:$((max - ${#ext}))}"
    base="${base%"${base##*[! .]}"}"
    [[ -z "$base" ]] && base="_"
    printf '%s%s' "$base" "$ext"
}

# Succeeds if $1 already contains an entry named $2, ignoring case (FAT32 is
# case-insensitive, even when the local filesystem isn't).
name_taken() {
    local dir="$1" lc
    lc=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
    ls -A "$dir" | tr '[:upper:]' '[:lower:]' | grep -Fxq -- "$lc"
}

# Moves the supported files from the title folder $1 into $2 (created if
# needed), sanitising names and avoiding collisions. $2 is removed again if
# nothing was moved into it.
move_title_files() {
    local src_title="$1" dest="$2" f name target n
    mkdir -p "$dest"
    for f in "$src_title"/*.{tap,tzx,pzx,rom,szx,z80,sna,m3u}; do
        [[ -f "$f" ]] || continue
        name=$(sanitize_name "$(basename "$f")" 128 1)
        target="$name"
        n=2
        while name_taken "$dest" "$target"; do
            target="${name%.*} ($n).${name##*.}"
            n=$((n + 1))
        done
        [[ "$target" != "$(basename "$f")" ]] && echo "  Renamed: $(basename "$f") -> $target"
        mv "$f" "$dest/$target"
    done
    if [[ -z "$(ls -A "$dest")" ]]; then
        rmdir "$dest"
    fi
}

process_source() {
    local src="$1"
    local namespace="$2"
    local folder="" folder_ext="" count=0 file letter dest i

    if [[ ! -d "$src" ]]; then
        echo "Error: source directory not found: $src/. Place $src.zip or the unzipped $src/ folder from the TOSEC archive here first." >&2
        exit 1
    fi

    for i in "$src"/*/; do
        if [[ "${$(basename "$i"):0:1}" != "!" ]]; then
            file=$(basename "$i")
            letter=$(echo "${file:0:1}" | tr '[:digit:]' '#' | tr '[:lower:]' '[:upper:]')
            if [[ "$folder" != "$letter" ]]; then
                count=0
                folder=$letter
            fi
            folder_ext=$((count++ / 256))
            dest="THESPECTRUM/$namespace/$folder$folder_ext/$(sanitize_name "$file" 64 0)"
            echo "Processing: $file"
            move_title_files "$i" "$dest"
        fi
    done
}

# Moves only the title folders named in $list (one per line, in rank order)
# from $src into THESPECTRUM/$namespace/ as a flat list, each folder prefixed
# with its zero-padded position in $list ("001. Title"). Titles missing from
# $src are skipped with a warning, but still consume their position.
process_demo_list() {
    local src="$1"
    local list="$2"
    local namespace="$3"
    local seq=0 title dest

    if [[ ! -d "$src" ]]; then
        echo "Error: source directory not found: $src/. Place $src.zip or the unzipped $src/ folder from the TOSEC archive here first." >&2
        exit 1
    fi
    if [[ ! -f "$list" ]]; then
        echo "Error: demo list not found: $list" >&2
        exit 1
    fi

    while IFS= read -r title || [[ -n "$title" ]]; do
        title="${title#"${title%%[![:space:]]*}"}"
        title="${title%"${title##*[![:space:]]}"}"
        [[ -z "$title" ]] && continue
        seq=$((seq + 1))
        if [[ ! -d "$src/$title" ]]; then
            echo "Warning: $title (#$seq in $list) not found in $src/; skipping." >&2
            continue
        fi
        dest="THESPECTRUM/$namespace/$(sanitize_name "$(printf '%03d. %s' "$seq" "$title")" 64 0)"
        echo "Processing: $title"
        move_title_files "$src/$title" "$dest"
    done < "$list"
}

require_extracted "$tosec_demos_src" "$tosec_demos_archive" "." "Demos/*"
process_demo_list "$tosec_demos_src" "$top_demos_list" "TOSEC-Demos"

require_extracted "$tosec_games_src" "$tosec_games_archive" "." "Games/*"
process_source "$tosec_games_src" "TOSEC-Games"

mkdir -p THESPECTRUM/roms
# To pin to a specific FBZX release, replace "refs/heads/master" with a commit SHA.
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/128-0.rom
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/128-1.rom
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/48.rom
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-0.rom
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-1.rom
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-2.rom
curl -fO --output-dir THESPECTRUM/roms https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-3.rom
