#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: package_macos_dmg.sh [options] APP_PATH

Creates a compressed, Developer ID-signed disk image containing the app and
an Applications directory shortcut.

Options:
  --output PATH       Output DMG. Defaults to
                      dist/release/APP-VERSION.dmg.
  --volume-name NAME  Mounted volume name. Defaults to nativ.
  --identity ID       Developer ID Application identity name or SHA-1 hash.
  --team-id ID        Resolve the Developer ID identity from a Team ID.
  -h, --help          Show this help.
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
repository_root="$(cd "$script_directory/.." && pwd -P)"
output_path=""
volume_name="Nativ"
identity=""
team_id=""

while (($# > 0)); do
    case "$1" in
        --output)
            (($# >= 2)) || fail "--output requires a value"
            output_path="$2"
            shift 2
            ;;
        --volume-name)
            (($# >= 2)) || fail "--volume-name requires a value"
            volume_name="$2"
            shift 2
            ;;
        --identity)
            (($# >= 2)) || fail "--identity requires a value"
            identity="$2"
            shift 2
            ;;
        --team-id)
            (($# >= 2)) || fail "--team-id requires a value"
            team_id="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            fail "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

(($# == 1)) || {
    usage >&2
    exit 2
}

app_path="$1"
[[ -d "$app_path" && -f "$app_path/Contents/Info.plist" ]] || fail "not a macOS app bundle: $app_path"
[[ -z "$identity" || -z "$team_id" ]] || fail "use either --identity or --team-id, not both"
[[ -n "$volume_name" ]] || fail "volume name cannot be empty"

app_directory="$(cd "$(dirname "$app_path")" && pwd -P)"
app_path="$app_directory/$(basename "$app_path")"
info_plist="$app_path/Contents/Info.plist"
app_name="$(basename "$app_path" .app)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
[[ -n "$version" ]] || fail "CFBundleShortVersionString is missing from $info_plist"

if [[ -z "$output_path" ]]; then
    output_path="dist/release/${app_name}-${version}.dmg"
fi
case "$output_path" in /*) ;; *) output_path="$repository_root/$output_path" ;; esac
[[ "$output_path" == *.dmg ]] || fail "--output must end in .dmg"
[[ ! -e "$output_path" ]] || fail "output already exists: $output_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
app_signature="$(codesign -dvvv "$app_path" 2>&1)"
[[ "$app_signature" == *"Authority=Developer ID Application:"* ]] || \
    fail "the app must be signed with a Developer ID Application certificate"
[[ "$app_signature" == *"Timestamp="* ]] || \
    fail "the app signature does not contain a secure timestamp"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mlx-vlm-dmg.XXXXXX")"
mount_path="$temporary_directory/mount"
is_mounted=false
cleanup() {
    if [[ "$is_mounted" == true ]]; then
        hdiutil detach "$mount_path" -quiet || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

staging_directory="$temporary_directory/contents"
mkdir -p "$staging_directory" "$mount_path" "$(dirname "$output_path")"
ditto "$app_path" "$staging_directory/$(basename "$app_path")"
ln -s /Applications "$staging_directory/Applications"

temporary_dmg="$temporary_directory/$(basename "$output_path")"
echo "Creating compressed disk image..."
hdiutil create \
    -quiet \
    -fs HFS+ \
    -format UDZO \
    -volname "$volume_name" \
    -srcfolder "$staging_directory" \
    "$temporary_dmg"

signing_arguments=()
if [[ -n "$identity" ]]; then
    signing_arguments+=(--identity "$identity")
elif [[ -n "$team_id" ]]; then
    signing_arguments+=(--team-id "$team_id")
fi
if ((${#signing_arguments[@]} > 0)); then
    "$script_directory/sign_macos_release.sh" "${signing_arguments[@]}" "$temporary_dmg"
else
    "$script_directory/sign_macos_release.sh" "$temporary_dmg"
fi

echo "Verifying disk image contents..."
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_path" "$temporary_dmg"
is_mounted=true
mounted_app="$mount_path/$(basename "$app_path")"
[[ -d "$mounted_app" ]] || fail "disk image does not contain $(basename "$app_path")"
[[ -L "$mount_path/Applications" && "$(readlink "$mount_path/Applications")" == "/Applications" ]] || \
    fail "disk image does not contain a valid Applications shortcut"
codesign --verify --deep --strict --verbose=2 "$mounted_app"
hdiutil detach "$mount_path" -quiet
is_mounted=false

mv "$temporary_dmg" "$output_path"
echo "Signed disk image: $output_path"
