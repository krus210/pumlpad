Download `Pumlpad.zip`, unzip it and move Pumlpad to Applications. It carries PlantUML and a Java runtime, so there is nothing else to install; Graphviz is optional. Needs macOS 14 or later on Apple Silicon.

The app is not notarized. When macOS blocks it, open System Settings › Privacy & Security and click Open Anyway, or run once:

    xattr -dr com.apple.quarantine /Applications/Pumlpad.app

GitHub Actions built this zip from the release's tag. To check that your download is that file:

    gh attestation verify Pumlpad.zip -R krus210/pumlpad
