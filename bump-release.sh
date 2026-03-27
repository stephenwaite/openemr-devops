#!/bin/bash
# usage: bump-release.sh [--dry-run] OLD_VERSION NEW_VERSION [OLD_SHORT NEW_SHORT]
# example: bump-release.sh --dry-run 8.0.1 8.1.0 801 810

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    shift
fi

OLD=${1:?Usage: $0 [--dry-run] OLD_VERSION NEW_VERSION [OLD_SHORT NEW_SHORT]}
NEW=${2:?Usage: $0 [--dry-run] OLD_VERSION NEW_VERSION [OLD_SHORT NEW_SHORT]}
OLD_SHORT="${3:-}"
NEW_SHORT="${4:-}"

DRY="[DRY RUN] "
if $DRY_RUN; then
    echo "*** DRY RUN MODE - no changes will be made ***"
    echo ""
fi

show_matches() {
    local file="$1"
    local search="$2"
    local replace="$3"
    grep -n "$search" "$file" | while read line; do
        lineno="${line%%:*}"
        content="${line#*:}"
        new_content="${content//$search/$replace}"
        echo "    line $lineno:"
        echo "      was: $content"
        echo "      now: $new_content"
    done
}

# --- Pass 1: Move (rename) version-named directories ---
echo "Searching for directories named with version $OLD ..."
dirs=$(find . -type d -name "*${OLD}*" -not -path "*/obsolete/*")

if [ -n "$dirs" ]; then
    echo "Found:"
    echo "$dirs"
    echo ""

    if ! $DRY_RUN; then
        echo "Will MOVE directories and update contents $OLD -> $NEW. Hit any key to continue, ctrl-c to abort."
        read ans
    fi

    for old_dir in $dirs; do
        new_dir="${old_dir//$OLD/$NEW}"
        echo "${DRY_RUN:+$DRY}Move directory: $old_dir -> $new_dir"

        find "$old_dir" -depth -name "*${OLD}*" | while read f; do
            new_f="${f//$OLD/$NEW}"
            echo "  ${DRY_RUN:+$DRY}Rename file: $f -> $new_f"
        done

        find "$old_dir" -type f | while read f; do
            if file "$f" | grep -q text; then
                if grep -q "$OLD" "$f"; then
                    new_f="${f//$OLD/$NEW}"
                    echo "  ${DRY_RUN:+$DRY}Update contents: $f -> $new_f"
                    show_matches "$f" "$OLD" "$NEW"
                fi
            fi
        done

        if ! $DRY_RUN; then
            mv "$old_dir" "$new_dir"

            find "$new_dir" -depth -name "*${OLD}*" | while read f; do
                new_f="${f//$OLD/$NEW}"
                mv "$f" "$new_f"
            done

            find "$new_dir" -type f | while read f; do
                if file "$f" | grep -q text; then
                    if grep -q "$OLD" "$f"; then
                        sed -i "s/${OLD}/${NEW}/g" "$f"
                    fi
                fi
            done
        fi
    done
else
    echo "No directories found matching $OLD"
fi

# --- Pass 1b: Rename individual files matching OLD_SHORT outside versioned dirs ---
if [ -n "$OLD_SHORT" ]; then
    echo ""
    echo "Searching for files named with short version $OLD_SHORT ..."
    short_files=$(find . -type f -name "*${OLD_SHORT}*" \
        -not -path "*/obsolete/*" \
        -not -path "*/.git/*" \
        -not -name "$(basename $0)")

    if [ -n "$short_files" ]; then
        echo "$short_files" | while read f; do
            new_f="${f//$OLD_SHORT/$NEW_SHORT}"
            echo "  ${DRY_RUN:+$DRY}Rename file: $f -> $new_f"
            if ! $DRY_RUN; then
                mv "$f" "$new_f"
            fi
        done
    else
        echo "No files found matching $OLD_SHORT"
    fi
fi

# --- Pass 2: Find all remaining references across the whole repo ---
echo ""
echo "Scanning all files in repo for remaining references to $OLD ..."
matches=$(grep -rl "$OLD" . \
    --exclude-dir=".git" \
    --exclude-dir="obsolete" \
    --exclude="$(basename $0)" \
    --exclude="demo_5_0_0_5.sql")

if [ -z "$matches" ]; then
    echo "No remaining references found."
else
    echo ""
    echo "$matches" | while read f; do
        if file "$f" | grep -q text; then
            echo "  ${DRY_RUN:+$DRY}Update contents: $f"
            show_matches "$f" "$OLD" "$NEW"
        fi
    done
    echo ""

    if ! $DRY_RUN; then
        echo "Will update all references $OLD -> $NEW in the files above. Hit any key to continue, ctrl-c to abort."
        read ans

        echo "$matches" | while read f; do
            if file "$f" | grep -q text; then
                echo "  Updating: $f"
                sed -i "s/${OLD}/${NEW}/g" "$f"
            fi
        done
    fi
fi

# --- Pass 2b: Find remaining references to OLD_SHORT if provided ---
if [ -n "$OLD_SHORT" ]; then
    echo ""
    echo "Scanning all files in repo for remaining references to $OLD_SHORT ..."
    short_matches=$(grep -rl "$OLD_SHORT" . \
        --exclude-dir=".git" \
        --exclude-dir="obsolete" \
        --exclude="$(basename $0)" \
        --exclude="demo_5_0_0_5.sql")

    if [ -z "$short_matches" ]; then
        echo "No remaining references to $OLD_SHORT found."
    else
        echo ""
        echo "$short_matches" | while read f; do
            if file "$f" | grep -q text; then
                echo "  ${DRY_RUN:+$DRY}Update contents: $f"
                show_matches "$f" "$OLD_SHORT" "$NEW_SHORT"
            fi
        done
        echo ""

        if ! $DRY_RUN; then
            echo "Will update all references $OLD_SHORT -> $NEW_SHORT in the files above. Hit any key to continue, ctrl-c to abort."
            read ans

            echo "$short_matches" | while read f; do
                if file "$f" | grep -q text; then
                    echo "  Updating: $f"
                    sed -i "s/${OLD_SHORT}/${NEW_SHORT}/g" "$f"
                fi
            done
        fi
    fi
fi

echo ""
if $DRY_RUN; then
    echo "*** Dry run complete - no changes were made ***"
    echo "Re-run without --dry-run to apply."
else
    echo "Done. Review with: git diff"
fi

# --- Final notes ---
echo ""
if [ -z "$OLD_SHORT" ]; then
    echo "NOTE: Files with dotless version names (e.g. build-801.yml) were NOT renamed."
    echo "      Re-run with short version args to handle these:"
    echo "      $0 [--dry-run] $OLD $NEW 801 810"
fi
