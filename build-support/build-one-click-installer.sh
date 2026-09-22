#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
source_dir="${script_dir:h}"
release_dir="${source_dir}/release"
template_path="${script_dir}/one-click-installer.cmd.in"
installer_name="1 - DOUBLE-CLICK TO INSTALL WEATHER TICKER.cmd"
archive_name="Weather-Ticker-One-Click-Installer.zip"
task_temp="$(mktemp -d)"

cleanup() {
    rm -rf -- "$task_temp"
}
trap cleanup EXIT

payload_dir="$task_temp/payload"
mkdir -p "$payload_dir" "$release_dir"

payload_files=(
    "WeatherTicker.ps1"
    "Weather Ticker.cmd"
    "Configure Weather Ticker.cmd"
    "Open Location Roster.cmd"
    "locations-template.csv"
    "README.txt"
    "START HERE.txt"
    "LICENSE"
)

for payload_file in "${payload_files[@]}"; do
    cp "$source_dir/$payload_file" "$payload_dir/$payload_file"
done

payload_zip="$task_temp/weather-ticker-payload.zip"
(
    cd "$payload_dir"
    /usr/bin/zip -X -q "$payload_zip" "${payload_files[@]}"
)

payload_hash="$(/usr/bin/shasum -a 256 "$payload_zip" | /usr/bin/awk '{print $1}')"
installer_lf="$task_temp/installer-lf.cmd"
installer_crlf="$task_temp/$installer_name"

/usr/bin/sed "s/__PAYLOAD_SHA256__/$payload_hash/" "$template_path" > "$installer_lf"
/usr/bin/base64 < "$payload_zip" | /usr/bin/fold -w 76 >> "$installer_lf"
/usr/bin/perl -pe 's/\r?\n/\r\n/g' "$installer_lf" > "$installer_crlf"

outer_zip="$task_temp/$archive_name"
(
    cd "$task_temp"
    /usr/bin/zip -X -q "$outer_zip" "$installer_name"
)

mv -f "$installer_crlf" "$release_dir/$installer_name"
mv -f "$outer_zip" "$release_dir/$archive_name"

echo "Built: $release_dir/$archive_name"
echo "Installer: $release_dir/$installer_name"
echo "Embedded payload SHA-256: $payload_hash"
