#!/usr/bin/env bash
# Records docs/demo.gif: Pumlpad plays its scripted session (DemoPlayer) and only the rectangle
# of its window is captured. Needs Screen Recording permission for the terminal, and ffmpeg.
# Keep hands off the keyboard and mouse for about a minute and a half. Should another window
# come in front of Pumlpad, the demo stops and the recording is thrown away.
#
# DRY_RUN=1 plays the session in the background without recording and checks it got through.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${APP:-$root/build/Pumlpad.app}"
dry_run="${DRY_RUN:-0}"
# screencapture writes the movie only when its time is up, so it records a fixed length that
# the demo fits in; the end is cut off afterwards.
length=62
work="$(mktemp -d)"
control="$work/control"
capture=""
cleanup() {
  if [[ -n "$capture" ]]; then kill -KILL "$capture" 2>/dev/null || true; fi
  quit_pumlpad
  rm -rf "$work"
}
# A demo stuck in a modal loop does not get to quit; it is killed then.
quit_pumlpad() {
  pkill -x Pumlpad 2>/dev/null || return 0
  for _ in $(seq 1 10); do
    pgrep -x Pumlpad >/dev/null || return 0
    sleep 0.5
  done
  pkill -KILL -x Pumlpad 2>/dev/null || true
}
trap cleanup EXIT

mkdir "$work/Diagrams"
cp "$root/docs/demo/checkout.puml" "$root/Samples/c4-container.puml" "$root/Samples/multiple-diagrams.puml" "$work/Diagrams/"

quit_pumlpad
sleep 1
crash_reports_before="$(ls ~/Library/Logs/DiagnosticReports | grep -c '^Pumlpad' || true)"
if [[ "$dry_run" == 1 ]]; then
  # In the background: the session does not take the front.
  open -g -a "$app" --env PUMLPAD_DEMO="$control" --env PUMLPAD_DEMO_DRY_RUN=1 "$work/Diagrams/checkout.puml" \
    --args -ApplePersistenceIgnoreState YES
else
  # Through LaunchServices, so that macOS brings the app to the front.
  open -a "$app" --env PUMLPAD_DEMO="$control" "$work/Diagrams/checkout.puml" --args -ApplePersistenceIgnoreState YES
fi
for _ in $(seq 1 60); do
  [[ -s "$control" ]] && break
  sleep 0.5
done
rectangle="$(cat "$control" 2>/dev/null || true)"
if [[ "$dry_run" != 1 && ! "$rectangle" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
  echo "Pumlpad did not come to the front (${rectangle:-no answer}); nothing was recorded." >&2
  exit 1
fi

if [[ "$dry_run" != 1 ]]; then
  screencapture -x -v -V "$length" -R"$rectangle" "$work/demo.mov" &
  capture=$!
  sleep 1
fi
started=$(date +%s)
touch "$control.recording"
while [[ ! -s "$control.done" ]] && (( $(date +%s) - started < length )); do
  if ! pgrep -x Pumlpad >/dev/null; then
    echo "aborted: Pumlpad quit" > "$control.done"
    break
  fi
  sleep 0.5
done
result="$(cat "$control.done" 2>/dev/null || echo "no answer in $length s")"
crash_reports_after="$(ls ~/Library/Logs/DiagnosticReports | grep -c '^Pumlpad' || true)"
if (( crash_reports_after > crash_reports_before )); then
  result="$result; new crash report: $(ls -t ~/Library/Logs/DiagnosticReports | grep '^Pumlpad' | head -1)"
fi
if [[ "$result" != done ]]; then
  echo "The demo stopped ($result); nothing was kept." >&2
  exit 1
fi
if [[ "$dry_run" == 1 ]]; then
  echo "Dry run passed in $(( $(date +%s) - started )) s."
  exit 0
fi
played=$(( $(date +%s) - started + 1 ))
wait "$capture"
capture=""

# The first second is the window waiting for the demo to start.
ffmpeg -loglevel error -y -ss 1 -t "$played" -i "$work/demo.mov" -vf \
  "fps=12,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  "$work/demo.gif"

# The edges of every frame must be the white backdrop: anything darker is another app.
dark=0
for strip in iw:6:0:0 6:ih:0:0 6:ih:iw-6:0 iw:6:0:ih-6; do
  count=$(ffmpeg -loglevel error -i "$work/demo.gif" \
    -vf "crop=$strip,signalstats,metadata=print:key=lavfi.signalstats.YMIN:file=-" -f null - 2>/dev/null \
    | awk -F= '/YMIN/ && $2 + 0 < 200 { n++ } END { print n + 0 }')
  dark=$((dark + count))
done
if (( dark > 0 )); then
  echo "Something besides the white backdrop shows at the edges of $dark frames; docs/demo.gif was not replaced." >&2
  exit 1
fi
mv "$work/demo.gif" "$root/docs/demo.gif"
ls -lh "$root/docs/demo.gif"
