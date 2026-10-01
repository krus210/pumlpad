APP := build/Pumlpad.app
# Command Line Tools ship the Swift Testing macros, but SwiftPM does not pass their plugin path.
TESTING_PLUGINS := $(shell xcrun --find swift | sed 's|/bin/swift$$|/lib/swift/host/plugins/testing|')
# Tests and benchmarks use the pinned PlantUML from `make plantuml` when it is there.
PLANTUML_MIT := $(abspath $(firstword $(wildcard vendor/plantuml-mit-*.jar)))

.PHONY: app app-standalone plantuml run test bench bench-launch install keywords icon clean

app:
	scripts/build-app.sh

# Carries PlantUML and a Java runtime: runs without Homebrew.
app-standalone:
	STANDALONE=1 scripts/build-app.sh

# The pinned MIT build of PlantUML, in vendor/.
plantuml:
	scripts/fetch-plantuml.sh

run: app
	open $(APP)

# One suite at a time: process tests count open file descriptors.
test:
	PUMLPAD_PLANTUML_JAR=$(PLANTUML_MIT) swift test --no-parallel -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)

# Engine timings with the standalone app's PlantUML and Java (run `make app-standalone` first).
bench:
	PUMLPAD_PLANTUML_JAR=$(abspath $(APP)/Contents/Resources/plantuml.jar) \
	PUMLPAD_JAVA=$(abspath $(APP)/Contents/Resources/jre/bin/java) \
	swift run -c release PumlBench Samples

# Launch to first preview, read from the app's log.
bench-launch:
	scripts/bench-launch.sh

# Copies the app to ~/Applications so Finder offers it for .puml files.
install: app
	rm -rf ~/Applications/Pumlpad.app
	mkdir -p ~/Applications
	cp -R $(APP) ~/Applications/
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/Pumlpad.app

keywords:
	scripts/gen-keywords.sh > Sources/Pumlpad/Keywords.swift

icon:
	scripts/make-icon.sh

clean:
	rm -rf .build build
