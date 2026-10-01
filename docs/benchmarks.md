# Benchmarks

How fast Pumlpad shows a diagram, and why. Measured on 2026-10-01.

## Machine

- Apple M2 Pro, macOS 27.0
- Pumlpad standalone build: PlantUML 1.2026.8 (MIT build) on the bundled OpenJDK 25.0.2 runtime
- Graphviz `dot` from Homebrew

## Rendering while you type

Pumlpad keeps one PlantUML process running (`java -jar plantuml.jar -pipe`) and sends it each version of the diagram. Only the first render pays for starting Java.

First render, including Java start: **576 ms**.

| Diagram | Median | 95th percentile |
|---|---:|---:|
| Sequence, 5 participants | 3.1 ms | 4.0 ms |
| Class, 3 classes (Graphviz) | 22.0 ms | 24.5 ms |
| Mind map, 12 nodes | 2.1 ms | 2.5 ms |
| C4 containers (standard library) | 84.7 ms | 86.5 ms |

30 renders of each diagram after 5 warm-up renders. The preview waits for a 300 ms pause in typing, so a diagram is on screen about a third of a second after the last keystroke.

The PlantUML process holds **300 MB** (resident) after these renders. Pumlpad stops idle processes: PNG ones after a minute, SVG ones after ten minutes, and a folder's processes when its last window closes.

### For comparison: a new Java process per render

What the `plantuml` command does, and what previewers that run it for every change do: `java -jar plantuml.jar -tsvg -pipe < diagram`, 5 runs each.

| Diagram | Median | Pumlpad is faster by |
|---|---:|---:|
| Sequence, 5 participants | 885 ms | ×285 |
| Class, 3 classes (Graphviz) | 1043 ms | ×47 |
| Mind map, 12 nodes | 873 ms | ×416 |
| C4 containers (standard library) | 1218 ms | ×14 |

## Opening a file

From launching the app with a file (`open -a Pumlpad file.puml`) to the rendered diagram on screen, as the app logs it. The clock starts when the kernel creates the process, so it includes AppKit's own start-up and Java's.

| File | Runs | Time to first diagram |
|---|---:|---:|
| `Samples/sequence.puml` | 5 | 0.92–1.03 s |
| `Samples/c4-container.puml` | 3 | 0.92–1.22 s |

The first launch after a build or a reboot is slower (about 1.4 s), while macOS loads Java's files from disk.

## Size

| Build | Size |
|---|---:|
| `make app-standalone` (PlantUML and Java inside) | 63 MB: Java runtime 46 MB, PlantUML 17 MB, Pumlpad 1.3 MB |
| `make app` (uses Homebrew's PlantUML and Java) | 1.3 MB |

The Java runtime is trimmed with `jlink` to the seven modules PlantUML needs.

## Reproduce

```sh
make app-standalone   # the app the numbers above come from
make bench            # rendering tables (Sources/PumlBench)
make bench-launch     # time to first diagram, 5 launches (scripts/bench-launch.sh)
scripts/bench-launch.sh Samples/c4-container.puml
```

`make bench` prints the machine section and both rendering tables in Markdown. `make bench-launch` opens the app in the background, reads `First preview N ms after launch` from the unified log and quits the app after each run.
