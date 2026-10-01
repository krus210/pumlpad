# Security

## Reporting a vulnerability

Please report security problems privately: on the repository's **Security** tab, click **Report a vulnerability** ([direct link](https://github.com/krus210/pumlpad/security/advisories/new)). Do not open a public issue for them.

Include the Pumlpad version (Pumlpad › About Pumlpad), your macOS version, and a diagram or the steps that show the problem. Pumlpad is a one-person project: expect a reply within a few days, and a fix in the next release.

## Supported versions

Only the latest release gets fixes.

## What counts as a vulnerability

Pumlpad opens diagrams that may come from anyone, so these are security problems:

- a diagram reads a file or reaches the network while its folder is not trusted;
- a diagram in a trusted folder reaches the network;
- something in a diagram runs code in the preview, or a diagram link opens anything but a web or mail address;
- a PlantUML process keeps running after its last window closes or the app quits.

These are known and documented ([README](README.md#security)):

- a diagram in a trusted folder can read files outside it through `../`, because PlantUML compares paths as written;
- the download is ad-hoc signed and not notarized.

A problem in PlantUML itself is worth reporting to the [PlantUML project](https://github.com/plantuml/plantuml) as well.
