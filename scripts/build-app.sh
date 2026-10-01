#!/usr/bin/env bash
# Builds build/Pumlpad.app with SwiftPM and the Command Line Tools; no Xcode project is involved.
#
# STANDALONE=1 also puts PlantUML and a trimmed Java runtime inside the app, so it runs on a Mac
# without Java or PlantUML: the MIT build of PlantUML (scripts/fetch-plantuml.sh, or PLANTUML_JAR)
# and a runtime linked from the JDK at JDK_HOME (default: the newest Java 21 or later that
# /usr/libexec/java_home knows). That JDK must carry its own native libraries, as Eclipse Temurin
# does: Homebrew's openjdk links Homebrew's freetype and harfbuzz, and a runtime made from it
# cannot draw text on a Mac without Homebrew. The build checks for that.
#
# ARCH=x86_64 builds for Intel Macs on Apple Silicon (and ARCH=arm64 the other way). A standalone
# build then needs a JDK of that architecture at JDK_HOME, and Rosetta to run its jlink and java.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
arch="${ARCH:-$(uname -m)}"
app="$root/build/Pumlpad.app"

swift build --package-path "$root" -c "$configuration" --arch "$arch" --product Pumlpad
bin="$(swift build --package-path "$root" -c "$configuration" --arch "$arch" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Pumlpad" "$app/Contents/MacOS/Pumlpad"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$root/Resources/Credits.html" "$app/Contents/Resources/"

if [[ "${STANDALONE:-0}" == 1 ]]; then
  jar="${PLANTUML_JAR:-$("$root/scripts/fetch-plantuml.sh")}"
  jdk="${JDK_HOME:-$(/usr/libexec/java_home -v 21+)}"
  if ! lipo -archs "$jdk/bin/java" | grep -qw "$arch"; then
    echo "The JDK at $jdk is not built for $arch: JDK_HOME=<a JDK for $arch> $0" >&2
    exit 1
  fi
  runtime="$app/Contents/Resources/jre"
  cp "$jar" "$app/Contents/Resources/plantuml.jar"
  # The modules PlantUML needs for SVG, PNG and the standard library (docs/research.md, 2e).
  "$jdk/bin/jlink" \
    --add-modules java.base,java.compiler,java.desktop,java.logging,java.prefs,java.scripting,jdk.unsupported \
    --strip-debug --no-header-files --no-man-pages --compress=zip-6 \
    --output "$runtime"

  # Every library the runtime loads must come with macOS or with the runtime itself.
  foreign="$(find "$runtime" -type f | while read -r file; do
    file -b "$file" | grep -q "Mach-O" || continue
    otool -L "$file" | tail -n +2 | awk '{ print $1 }' \
      | grep -vE '^(/usr/lib/|/System/|@rpath/|@loader_path/|@executable_path/)' | sed "s|^|${file#"$runtime"/}: |"
  done)"
  if [[ -n "$foreign" ]]; then
    echo "The runtime from $jdk needs libraries that Macs do not have:" >&2
    echo "$foreign" >&2
    echo "Use a JDK that carries its own, such as Eclipse Temurin: JDK_HOME=<its Contents/Home> $0" >&2
    exit 1
  fi

  # Licences of everything inside (THIRD-PARTY-NOTICES.md); the runtime keeps its own in jre/legal.
  licenses="$app/Contents/Resources/Licenses"
  mkdir -p "$licenses"
  cp "$root/Licenses/"*.txt "$root/THIRD-PARTY-NOTICES.md" "$licenses/"
  cp "$root/LICENSE" "$licenses/Pumlpad-LICENSE.txt"
  # PlantUML prints the notice only when stdout and stderr go to the same place.
  "$jdk/bin/java" -Djava.awt.headless=true -jar "$jar" -license > "$licenses/PlantUML-license.txt" 2>&1 < /dev/null
  grep -q "MIT License" "$licenses/PlantUML-license.txt"

  # Contents/Helpers would require a signature on every file, data included, so the runtime
  # lives in Resources; its Mach-O files are signed one by one before the bundle.
  find "$runtime" -type f | while read -r file; do
    if file -b "$file" | grep -q "Mach-O"; then codesign --force --sign - "$file"; fi
  done
fi

# Ad-hoc signature: enough to run on this Mac. Downloads need "Open Anyway" once (README).
codesign --force --sign - "$app"
echo "$app"
