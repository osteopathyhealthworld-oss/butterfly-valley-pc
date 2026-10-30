#!/usr/bin/env bash
# Fetch only the pinned CC0 modular pieces used by Bruno's workshop.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_revision="21104b4045261c28fc312360841ed1a7b0ac8782"
source_root="https://raw.githubusercontent.com/J-Ponzo/gltf-medieval-village-megakit/${source_revision}/glTF"
destination="${project_dir}/assets/buildings/village"
mkdir -p "$destination"
while read -r file size; do
  [[ -z "$file" || "$file" == \#* ]] && continue
  [[ "$file" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Unsafe filename: $file" >&2; exit 2; }
  output="${destination}/${file}"
  if [[ -f "$output" ]] && [[ "$(wc -c < "$output")" -eq "$size" ]]; then
    continue
  fi
  curl -fL --retry 3 --connect-timeout 15 --max-time 120 "$source_root/$file" -o "${output}.download"
  actual="$(wc -c < "${output}.download")"
  [[ "$actual" -eq "$size" ]] || { echo "Size mismatch: $file" >&2; exit 3; }
  mv -f "${output}.download" "$output"
done < "${project_dir}/building-assets-manifest.txt"
echo "Quaternius Medieval Village CC0 pieces are ready for Godot import."

