Download `Pumlpad-apple-silicon.zip` or, for a Mac with an Intel processor, `Pumlpad-intel.zip`, unzip it and move Pumlpad to Applications. It carries PlantUML and a Java runtime, so there is nothing else to install; Graphviz is optional. Needs macOS 14 or later.

The app is not notarized. When macOS blocks it, open System Settings › Privacy & Security and click Open Anyway, or run once:

    xattr -dr com.apple.quarantine /Applications/Pumlpad.app

GitHub Actions built these zips from the release's tag. To check that your download is one of them:

    gh attestation verify Pumlpad-apple-silicon.zip -R krus210/pumlpad
