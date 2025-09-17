#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: ./find_ingredient.sh -i "<ingredient>" -d /path/to/folder
       ./find_ingredient.sh -h

Checks whether any product in products.csv (TSV) under the given folder
contains the specified ingredient (case-insensitive).
USAGE
}

ingredient=""
folder=""

while getopts ":i:d:h" opt; do
    case "$opt" in
        i)
            ingredient="$OPTARG"
            ;;
        d)
            folder="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            printf 'Error: Option -%s requires an argument.\n' "$OPTARG" >&2
            usage >&2
            exit 1
            ;;
        ?)
            printf 'Error: Unknown option -%s.\n' "$OPTARG" >&2
            usage >&2
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

if (($# > 0)); then
    printf 'Error: Unexpected argument: %s\n' "$1" >&2
    usage >&2
    exit 1
fi

if [[ -z "$ingredient" ]]; then
    printf 'Error: Missing required -i "<ingredient>" option.\n' >&2
    usage >&2
    exit 1
fi

if [[ -z "$folder" ]]; then
    printf 'Error: Missing required -d /path/to/folder option.\n' >&2
    usage >&2
    exit 1
fi

csv_file="$folder/products.csv"

for tool in csvcut csvgrep csvformat; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Error: Required command "%s" is not available on PATH.\n' "$tool" >&2
        printf 'Found 0 product(s) containing: "%s"\n' "$ingredient"
        exit 1
    fi
done

if [[ ! -f "$csv_file" ]]; then
    printf 'Warning: File not found: %s\n' "$csv_file" >&2
    printf 'Found 0 product(s) containing: "%s"\n' "$ingredient"
    exit 0
fi

if [[ ! -s "$csv_file" ]]; then
    printf 'Warning: File is empty: %s\n' "$csv_file" >&2
    printf 'Found 0 product(s) containing: "%s"\n' "$ingredient"
    exit 0
fi

if ! headers=$(csvcut -t -n "$csv_file" 2>/dev/null); then
    printf 'Warning: Unable to read headers from %s\n' "$csv_file" >&2
    printf 'Found 0 product(s) containing: "%s"\n' "$ingredient"
    exit 0
fi

missing_cols=()
for col in ingredients_text product_name code; do
    if ! grep -Fqw "$col" <<<"$headers"; then
        missing_cols+=("$col")
    fi
done

if ((${#missing_cols[@]} > 0)); then
    printf 'Warning: Missing required column(s): %s\n' "${missing_cols[*]}" >&2
    printf 'Found 0 product(s) containing: "%s"\n' "$ingredient"
    exit 0
fi

escape_regex() {
    local raw="$1"
    local result=""
    local i ch
    for ((i = 0; i < ${#raw}; i++)); do
        ch="${raw:i:1}"
        case "$ch" in
            '.'|'['|']'|'{'|'}'|'('|')'|'*'|'+'|'?'|'^'|'$'|'|'|'\\')
                result+="\\$ch"
                ;;
            *)
                result+="$ch"
                ;;
        esac
    done
    printf '%s' "$result"
}

pattern="(?i)$(escape_regex "$ingredient")"

matches=0
placeholder_name="(no name)"
placeholder_code="(no code)"

while IFS=$'\t' read -r name code; do
    if [[ -z "${name//[[:space:]]/}" ]]; then
        name="$placeholder_name"
    fi

    if [[ -z "${code//[[:space:]]/}" ]]; then
        code="$placeholder_code"
    fi

    printf '%s\t%s\n' "$name" "$code"
    matches=$((matches + 1))
done < <(
    csvcut -t -c ingredients_text,product_name,code "$csv_file" \
    | csvgrep -t -c ingredients_text -r "$pattern" \
    | csvcut -c product_name,code \
    | csvformat -T \
    | tail -n +2
)

printf 'Found %d product(s) containing: "%s"\n' "$matches" "$ingredient"
