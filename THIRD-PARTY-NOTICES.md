# Third-party notices

Pumlpad's own code is under the MIT License, see [LICENSE](LICENSE). The repository contains no third-party code.

The standalone app (`make app-standalone` and the release downloads) also carries the components below, unmodified. Their licence texts are in [Licenses/](Licenses) and, inside the app, in `Contents/Resources/Licenses`.

| Component | Version | Licence | In the app | Source code |
|---|---|---|---|---|
| [PlantUML](https://plantuml.com), MIT build | 1.2026.8 | MIT, © Arnaud Roques | `Contents/Resources/plantuml.jar` | [plantuml-mit-1.2026.8-sources.jar](https://repo1.maven.org/maven2/net/sourceforge/plantuml/plantuml-mit/1.2026.8/plantuml-mit-1.2026.8-sources.jar) |
| Smetana, the Java port of Graphviz `dot` | part of PlantUML | EPL-1.0, © AT&T | inside `plantuml.jar` | the same sources jar |
| ditaa | part of PlantUML | LGPL-3.0-or-later, © Efstathios Sideris | inside `plantuml.jar` | the same sources jar |
| PlantUML standard library (C4-PlantUML and others) | part of PlantUML | per library, listed in `PlantUML-license.txt` | inside `plantuml.jar` | [plantuml-stdlib](https://github.com/plantuml/plantuml-stdlib) |
| Eclipse Temurin (OpenJDK) runtime, trimmed with `jlink`, with the FreeType, HarfBuzz and other libraries it carries | 21.0.12.1 | GPL-2.0 with Classpath Exception; those libraries under their own licences | `Contents/Resources/jre` | [adoptium.net](https://adoptium.net), [openjdk.org](https://openjdk.org); notices in `Contents/Resources/jre/legal` |

- `PlantUML-license.txt` inside the app is PlantUML's own notice, printed by `java -jar plantuml.jar -license` at build time.
- `plantuml.jar` stays a separate file: you can replace it with another PlantUML build.
- PlantUML's licence does not cover the diagrams you make with it.
