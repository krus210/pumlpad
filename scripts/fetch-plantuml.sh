#!/usr/bin/env bash
# Downloads the MIT build of PlantUML that `make app-standalone` puts inside the app, checks it
# against the pinned SHA-256 and prints its path. The version is pinned: newer PlantUML releases
# change rendering defaults.
set -euo pipefail

version="1.2026.8"
sha256="8a171e8941d1f68f4ec28f5c180a4bf8d54a2cd679348370d4ba59fc9fb910e3"

root="$(cd "$(dirname "$0")/.." && pwd)"
jar="$root/vendor/plantuml-mit-$version.jar"
url="https://repo1.maven.org/maven2/net/sourceforge/plantuml/plantuml-mit/$version/plantuml-mit-$version.jar"

verified() {
  [[ -f "$1" ]] && [[ "$(shasum -a 256 "$1" | cut -d " " -f 1)" == "$sha256" ]]
}

if ! verified "$jar"; then
  mkdir -p "$root/vendor"
  curl --fail --location --silent --show-error --output "$jar.part" "$url"
  if ! verified "$jar.part"; then
    rm -f "$jar.part"
    echo "SHA-256 of $url does not match the pinned value" >&2
    exit 1
  fi
  mv "$jar.part" "$jar"
fi
echo "$jar"
