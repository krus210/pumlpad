# Лёгкий PlantUML-редактор для macOS: исследование

- **Дата:** 2026-09-30.
- **Источники:** первичные — сайты продуктов, App Store и iTunes Lookup/Search API, plantuml.com, исходники `plantuml/plantuml` @ `e41d08e` (master, 2026-09-29), документация Apple, Swift.org, Tauri, Wails, GNU.
- **«Не подтверждено»** — первоисточника нет.
- **«Локальная проверка»** — команда выполнена на этой машине: macOS 27.0, PlantUML 1.2026.2 из Homebrew, Command Line Tools без Xcode.
- **Вне рамок:** замеры скорости рендера и сборка SwiftPM.

## Итог: рекомендации

1. **Ниша свободна.** Нативного офлайн-редактора с полным PlantUML, лёгкого и open-source, на рынке нет.
   - Приложения 2026 года рендерят через удалённый сервер (Pladitor, PlantUML Renderer, Sonance, PlantUML QuickLook) или реализуют подмножество своим движком (VUML: 8 типов, CoreGraphics).
   - EasyPlantUML весит 117.8 MB и не обновлялся с 2023-08: внутри PlantUML 1.2023.10 (раздел 1).
2. **Движок MVP.**
   - Неизменённый `plantuml-mit-1.2026.8.jar`, ≈17.7 MB. Не `-light`: в нём нет stdlib и C4.
   - Урезанная Java через jlink: `java.base,java.compiler,java.desktop,java.logging,java.prefs,java.scripting,jdk.unsupported`, ≈45–50 MB.
   - Итого ≈63–68 MB, Java и Graphviz пользователю ставить не нужно (2e, 3a).
3. **Протокол — один долгоживущий `-pipe` на папку документа:**
   `java -Djava.awt.headless=true -jar plantuml-mit.jar --pipe --svg -pipenostderr -pipedelimitor <UUID> -stdrpt:2 -filedir <папка>`. Эта команда проверена локально на 1.2026.2: в stdout по очереди идут SVG + разделитель и `string:3:error:…` + разделитель, stderr пуст.
   - Результат приходит после каждого `@end…`, EOF не нужен. Ошибка приходит строкой `string:<N>:error:<msg>`, N считается от `@startuml`.
   - Разделитель пишется сразу после `</svg>` и ищется как подстрока. Флаги писать точно и в нижнем регистре (2a).
   - picoweb по умолчанию небезопасен: 0.0.0.0, `ACAO: *`, профиль `LEGACY` (2b). Если он понадобится, то только на `127.0.0.1` и с `ALLOWLIST`.
4. **Graphviz не требовать.** С PlantUML 1.2026.7 и новее без `dot` автоматически включается Smetana (порт dot на Java, уже в jar). Если Homebrew-`dot` установлен, PlantUML подхватывает его сам. Встраивать `dot` (EPL-2.0 + dylib) — только после сравнения качества (2d, 3e).
5. **Превью в SVG** (например, в WKWebView), без `-Sdpi`.
   - PNG — только для экспорта и буфера обмена: `-Sdpi=192` плюс поднятый `PLANTUML_LIMIT_SIZE`. Иначе при 192 dpi обрезается всё, что шире ≈2048 px.
   - Ошибку показывать своим UI по номеру строки и держать последнюю удачную картинку: в картинке ошибки PlantUML есть баннеры, которые меняются по минутам (2c, 2f).
6. **Лицензия приложения — MIT.** В `Licenses/` и окно About положить:
   - MIT для PlantUML;
   - EPL-1.0 для Smetana, она внутри MIT-jar;
   - LGPL-3.0 и GPL-3.0 для ditaa;
   - GPLv2+CE для OpenJDK, сохранив каталог `legal/`;
   - лицензии stdlib (C4 — MIT) и ссылку на `plantuml-mit-<ver>-sources.jar` или его зеркало.

   В не-GPL сборках нет `<latex>`, PDF, встроенного ELK, Jcckit и Sudoku; для UML-редактора это не критично (3).
7. **Сборка без Xcode реальна:** SwiftPM executable плюс скрипт, который собирает `.app` (Info.plist, `.icns` через `iconutil`, `codesign --sign -`).
   - Недоступны `.xcassets`, xib/storyboard, `#Preview`, `@Entry`. `@Observable` работает на macOS 14+.
   - Ресурсы — в `Contents/Resources` через `Bundle.main`. Mach-O-файлы JRE — в `Contents/Frameworks` или `Contents/Helpers` (4a, 4b).
8. **Распространение v0.x.** GitHub Releases, ad-hoc подпись, в README — инструкция «System Settings → Privacy & Security → Open Anyway»: начиная с macOS 15 Control-click больше не обходит Gatekeeper.
   - Официальный Homebrew cask и запуск без предупреждений — только после нотаризации.
   - Нотаризации нужен Developer ID за $99/год, но Xcode не нужен: `notarytool` и `stapler` есть в CLT (4c).
9. **Редактор — NSTextView (TextKit 2)** с подсветкой регулярками и системным find/replace.
   - Словари — из `plantuml --list-keywords` (или `-language`): 918 строк, генерировать при сборке под версию jar.
   - Готовые пакеты не подходят: STTextView под GPL-3.0; CodeEditSourceEditor «not ready for production» и без PlantUML; tree-sitter-грамматики PlantUML незрелые.
   - Паттерны можно взять из TextMate-грамматики vscode-plantuml (MIT), сниппеты оттуда — Apache-2.0 (5).
10. **Запасной путь без JVM** — `@plantuml/core` (MIT, ≈8 MB, TeaVM) в WKWebView.
    - Только SVG, без локальных `!include`, stdlib подключается отдельно. Годится для «лёгкого режима» или Quick Look-расширения.
    - Официальную сборку native-image (macOS arm64, GPL, zip 55 MB) сначала проверить локально на PNG и SVG (2e).

**К замерам**
- **Локальная 1.2026.2 отстаёт от 1.2026.8:**
  - нет автоматического перехода на Smetana, поэтому для замера Smetana нужен явный `-Playout=smetana`;
  - sequence-диаграммы с 1.2026.7 по умолчанию рисует Teoz, а не Puma;
  - регистр флагов не важен только с 1.2026.7 (2a, 2d).
- **Флаги в 1.2026.2 (локальная проверка, 2a, 2f):**
  - работает только `-pipenostderr` в нижнем регистре;
  - `-pipeNoStdErr` молча игнорируется, и в stdout идёт картинка ошибки;
  - флага `-dpi<N>` нет, нужен `-Sdpi=<N>`.
- **Поведение `-pipe`:** `-filedir` один на процесс; `@start` и `@end` должны стоять с 0-й колонки; без `@end` процесс ждёт (2a).
- **picoweb:** `POST /render` принимает опции на каждый запрос, но при ошибке отвечает 200. Ошибку видно только по заголовку `X-PlantUML-Diagram-Error-Line` (2b).

## 1. Конкуренты

Данные App Store сняты 2026-09-30: страницы apps.apple.com и iTunes Lookup/Search API (`https://itunes.apple.com/lookup?id=<id>`, `https://itunes.apple.com/search?term=plantuml&entity=macSoftware`). Это первичный источник Apple для цены, версии, дат, размера и минимальной macOS.

### 1a. EasyPlantUML (TickPlant, Jiwei Xu)

**Паспорт**
- Цена $3.99 (в CN ¥28), только Mac, Developer Tools, bundle id `com.tickplant.EasyPlantUML`. Размер 117.8 MB (`fileSizeBytes` 117835213), нужна macOS 10.15+ ([App Store](https://apps.apple.com/us/app/easyplantuml/id1589635432?mt=12), [iTunes Lookup](https://itunes.apple.com/lookup?id=1589635432&country=us)).
- Последняя версия 1.4.0 от 2023-08-26, первый релиз 2021-10-12. История версий: 1.2.0 (2021-11-29) — «Add native Apple Silicon support»; 1.2.1 (2022-04-05) — bug fixes; 1.3.0 (2023-08-24) — «Updated PlantUML to v1.2023.10»; 1.4.0 — «Copy Preview Image to pasteboard», Cmd+Shift+C ([App Store, Version History](https://apps.apple.com/us/app/easyplantuml/id1589635432?mt=12)). С августа 2023 обновлений нет, внутри PlantUML 1.2023.10.
- Рейтинг в US: 3.3/5 по 4 оценкам ([Ratings & Reviews](https://apps.apple.com/us/app/1589635432?see-all=reviews&platform=mac)).

**Функции.** Заявлены на [tickplant.com/easyplantuml](https://tickplant.com/easyplantuml/) и в App Store, это полный список:
- Редактор: «Syntax Highlighting for PlantUML grammar», «Auto Completion in editor helps typing keywords quickly», «Instant Parsing Error indicator for locating syntax error».
- Превью: «Auto Generated Preview when typing», «Zoom and Pan», зум колесом мыши.
- Файлы: сохранение как `.plantuml`, `.puml`, `.pu`.
- Экспорт: PNG, SVG, TXT, EPS, LaTeX, VDX «with one click». С версии 1.4.0 есть копирование картинки превью в буфер.
- Не заявлены (не подтверждено): сниппеты и шаблоны, поиск и замена, номер строки в индикаторе ошибки, темы редактора, фон превью, `!include`, вкладки и несколько окон, окно настроек. Отзыв ниже говорит, что размер шрифта не меняется.

**Рендер.** Механизм официально не раскрыт.
- Сайт: «without the hassle of running java commands in the terminal or deploying an additional PlantUML parsing server, just download an app». Значит, ставить Java и поднимать сервер пользователю не нужно ([tickplant.com](https://tickplant.com/easyplantuml/)).
- Косвенные признаки: запись «Updated PlantUML to v1.2023.10» и размер 117.8 MB говорят, что движок PlantUML лежит внутри приложения, вероятно вместе со встроенным JRE. **Не подтверждено.** Про Graphviz (встроен, Smetana или системный) данных нет, **не подтверждено**.
- Архитектура Intel + Apple Silicon, сборка 1.4.0 (67) — по данным MacUpdater, это вторичный источник ([macupdater.net](https://macupdater.net/app_updates/appinfo/com.tickplant.EasyPlantUML/)).

**Жалобы из отзывов**
- US, JodyHagins, 2022-04-21: «font size of the editor is fixed at 12», «a number of those simple [State] diagrams didn't even render correctly», нет пробной версии ([reviews](https://apps.apple.com/us/app/1589635432?see-all=reviews&platform=mac)).
- CN, hetung, 2022-05-21: нет справки, слабый UI, просьба вернуть деньги ([App Store CN](https://apps.apple.com/cn/app/easyplantuml/id1589635432?mt=12)).

### 1b. VUML (Lloyd Moore)

- $19.99 в US App Store; на сайте £19.99 за App Store Edition и столько же за Independent Edition (прямая покупка через Stripe). Версия 1.0 от 2026-03-30, 1.4 MB, macOS 13.0+, **только Apple Silicon (M1 и новее)**, bundle id `com.vuml.app`, отзывов нет ([App Store](https://apps.apple.com/us/app/vuml/id6759516323?mt=12), [iTunes Lookup](https://itunes.apple.com/lookup?id=6759516323&country=us), [vuml.app](https://vuml.app/)).
- **Рендер офлайн — собственный, не plantuml.jar.** В App Store: «Eight diagram types rendered with CoreGraphics. No Java, no server, fully offline»; в описании: «reads PlantUML text and renders diagrams instantly, with no external dependencies, no Java runtime». На сайте: «Built entirely with Swift and SwiftUI. No Electron, no web views, no third-party dependencies».
- Поддерживаются 8 типов: Sequence, Class, Component, State, Activity, Use Case, ArchiMate, WBS ([vuml.app](https://vuml.app/)). Остальной PlantUML (mindmap, gantt, json/yaml, salt, stdlib/C4, `!theme`) не заявлен, **совместимость не подтверждена**.
- Отличия в UX:
  - «Model-First Persistence»: элементы определяются один раз в модели на SQLite и переиспользуются в нескольких views, формат `.vuml`.
  - «Vim Mode» — полноценный модальный редактор.
  - Разделённый экран: редактор с подсветкой и live preview.
  - Sidebar модели для ArchiMate и deployment views.
  - Экспорт PNG и SVG. «No telemetry».

### 1c. Прочие (одной строкой: стек и рендер)

| Проект | Стек | Рендер | Статус |
|---|---|---|---|
| [PUML2Picture](https://github.com/codeisconquer/PUML2Picture) | Go + Fyne v2.6.2 ([go.mod](https://github.com/codeisconquer/PUML2Picture/blob/ea51d0c514b204438e4a77a8255bd236f4c3dbfe/go.mod)) | `plantuml.jar` вшит через `go:embed` ([logic.go#L12-L13](https://github.com/codeisconquer/PUML2Picture/blob/ea51d0c514b204438e4a77a8255bd236f4c3dbfe/logic.go#L12-L13)). На каждый рендер новый процесс `java -jar plantuml.jar -t<fmt> file` ([#L40-L41](https://github.com/codeisconquer/PUML2Picture/blob/ea51d0c514b204438e4a77a8255bd236f4c3dbfe/logic.go#L40-L41)). Проверяет наличие `java` и `dot` ([#L66-L79](https://github.com/codeisconquer/PUML2Picture/blob/ea51d0c514b204438e4a77a8255bd236f4c3dbfe/logic.go#L66-L79)), то есть **нужны системные Java и Graphviz** | 3 коммита, 0 звёзд, последний 2025-08-07 |
| [PlantUMLPreviewer](https://github.com/Artem-Shapovalov/PlantUMLPreviewer) | Python + PySide6, упаковка PyInstaller | Системная команда `plantuml` из PATH или `PLANTUML_CMD`. Новый процесс на каждый рендер: `plantuml -tpng -DPLANTUML_LIMIT_SIZE=16384 -dpi<N> file`, debounce 350 мс ([app.py#L240-L243](https://github.com/Artem-Shapovalov/PlantUMLPreviewer/blob/d0f7a91b28420da8ca6a9bc8702cef4ce5dc3592/app.py#L240-L243), [#L327-L332](https://github.com/Artem-Shapovalov/PlantUMLPreviewer/blob/d0f7a91b28420da8ca6a9bc8702cef4ce5dc3592/app.py#L327-L332)). PNG «192 DPI» (но флаг `-dpi<N>` в 1.2026.2 молча игнорируется, см. 2f), зум колесом, drag, completion по Ctrl+Space, копирование картинки по Ctrl+Shift+C | 2 коммита, последний 2026-04-06 |
| [plantuml-live-editor](https://github.com/oakraw/plantuml-live-editor) | Веб: Vite + Monaco, не нативное приложение | В браузере: CheerpJ + [plantuml-core](https://github.com/plantuml/plantuml-core), CheerpJ-loader грузится с CDN Leaning Technologies. Debounce ~400 мс, SVG-превью, экспорт PNG 16–8192 px, «First render may take several seconds» | 1 коммит, 2026-06-16 |
| [Pladitor](https://plantumleditor.com/) (Florian Müller) | Monaco в webview; в release notes упомянут WebView2 на Windows, фреймворк не подтверждён | **По умолчанию удалённый «Pladitor PlantUML server»**, можно указать свой. Для офлайна есть отдельный пакет [PlantUML Local Server](https://plantumleditor.com/localserver) со своим JVM runtime на `http://127.0.0.1:5080/` | $9.99, v1.17.1 от 2026-07-28, 23.3 MB, macOS 12+ ([Lookup](https://itunes.apple.com/lookup?id=6443944095&country=us)). У него самый широкий набор функций, см. таблицу. Брат-близнец Dacitor ($19.99) добавляет Mermaid и D2 |
| [PlantUML Renderer](https://www.gregboratyn.com/apps/PlantUMLRenderer/) (Greg Boratyn) | SwiftUI + AppKit | Публичный сервер plantuml.com, нужен интернет. Показывает ошибку сервера с номером строки | $1.99, v1.0 от 2026-06-04, 0.4 MB, `minimumOsVersion` 26.5 ([Lookup](https://itunes.apple.com/lookup?id=6772376593&country=us)). Палитра сниппетов по типам диаграмм (вставка кликом или перетаскиванием), find, PNG/SVG |
| DiagramLab – Mermaid/PlantUML ([App Store](https://apps.apple.com/us/app/diagramlab-mermaid-plantuml/id6757279031?mt=12)) | н/д | Способ рендера PlantUML не указан | $34.99, v1.0.9 от 2026-05-20, 0.8 MB, macOS 14+. Ошибки «line-focused», экспорт PNG/JPG/SVG/PDF/HTML |
| Sonance Diagram Studio ([App Store](https://apps.apple.com/us/app/sonance-diagram-studio/id6809284333?mt=12)) | н/д | PlantUML «renders through a server you choose (plantuml.com by default)». Mermaid, D2, Graphviz и Nomnoml работают офлайн | бесплатно, v1.1.0 от 2026-09-19 |
| PlantUML QuickLook ([App Store](https://apps.apple.com/us/app/plantuml-quicklook/id6778470690?mt=12)) | Quick Look extension | Через PlantUML-сервер (публичный по умолчанию или свой) | $0.99, v1.0 от 2026-06-21, macOS 14+. Это не редактор, но показывает спрос на Quick Look |

Итог по рынку (вывод по данным выше):
- Ниша **«нативный + офлайн + полный PlantUML + лёгкий + open-source»** свободна.
- Приложения 2026 года рендерят через сервер (Pladitor, PlantUML Renderer, Sonance, QuickLook) или реализуют подмножество своим движком (VUML).
- Из приложений Mac App Store офлайн на настоящем движке PlantUML, судя по описаниям, работает только EasyPlantUML: 117.8 MB, обновлений нет с 2023 года. DiagramLab способ рендера не раскрывает. Open-source-поделки (PUML2Picture, PlantUMLPreviewer) требуют системную Java.

### Итог раздела 1: функции

«✓» — заявлено производителем, «—» — не заявлено (наличие не подтверждено), «✗» — подтверждённое отсутствие. Pladitor добавлен справочно: у него самый широкий набор функций.

| Функция | EasyPlantUML | VUML | Pladitor (справочно) |
|---|---|---|---|
| Подсветка синтаксиса | ✓ | ✓ | ✓ + подсветка строки |
| Автодополнение | ✓ (ключевые слова) | — | ✓ |
| Сниппеты / шаблоны | — | — | ✓ 120+ шаблонов + свои |
| Поиск / замена | — | — | ✓ |
| Ошибка синтаксиса | ✓ «Instant Parsing Error indicator» (номер строки не заявлен) | — | ✓ «real-time syntax-error feedback» |
| Размер шрифта редактора | ✗ (отзыв: фиксирован 12 pt) | — | ✓ |
| Темы / тёмный режим | — | — | ✓ light/dark, «15 light and dark themes» |
| Vim mode | — | ✓ | — |
| Live preview | ✓ | ✓ | ✓ |
| Зум / пан | ✓ (колесо мыши) | — | ✓ + fit-to-screen |
| Переход картинка → код | — | — | ✓ (двойной клик) |
| Экспорт | PNG, SVG, TXT, EPS, LaTeX, VDX | PNG, SVG | PNG, SVG, PDF, EPS, ASCII, Base64, MAP, URL |
| Копирование в буфер | ✓ картинка (с 1.4.0) | — | ✓ все форматы |
| Файлы | `.plantuml`, `.puml`, `.pu` | `.vuml` (SQLite-модель) | + импорт исходника из PNG/SVG |
| Вкладки / несколько диаграмм | — | — | ✓ multi-tab, autosave |
| Рендер | PlantUML 1.2023.10 внутри app, механизм не раскрыт | свой, на CoreGraphics (8 типов) | удалённый сервер, отдельно — Local Server |
| Офлайн | ✓ (вывод из текста сайта) | ✓ | только с Local Server |
| Нужны Java / Graphviz пользователю | Java не нужна (заявлено), Graphviz — н/д | нет | нет |
| Размер / min macOS | 117.8 MB / 10.15 | 1.4 MB / 13.0, только Apple Silicon | 23.3 MB / 12.0 |
| Цена / последняя версия | $3.99 / 1.4.0 от 2023-08-26 | $19.99 / 1.0 от 2026-03-30 | $9.99 / 1.17.1 от 2026-07-28 |

### Итог раздела 1: MVP и что позже

Предложение основано на функциях конкурентов, жалобах из отзывов и ограничениях из разделов 2–5.

**MVP**
- **Документы.**
  - Открыть и сохранить `.puml/.plantuml/.pu/.iuml/.wsd`, ассоциация файлов (4b), несколько окон.
  - `!include` относительно файла (`-filedir`, 2a).
  - `!theme` и stdlib (C4) офлайн (2g).
- **Редактор.**
  - NSTextView, моноширинный шрифт с **настраиваемым размером**: к EasyPlantUML была жалоба на фиксированные 12 pt.
  - Подсветка по словарям из `--list-keywords` (5), номера строк, undo.
  - Системный find/replace, у EasyPlantUML его нет.
- **Live preview.**
  - Debounce 300–400 мс (у PlantUMLPreviewer 350 мс, у plantuml-live-editor ~400 мс), устаревшие рендеры отменяются.
  - При ошибке остаётся последняя удачная картинка, строка ошибки подсвечивается, внизу — сообщение (2a, 2c).
- **Превью.** Зум (pinch, ⌘+/⌘−, колесо), fit-to-window, 100 %, пан. SVG на Retina (2f).
- **Экспорт.**
  - PNG @2x и SVG.
  - Копирование картинки в буфер по ⌘⇧C, как у EasyPlantUML 1.4.0 и PlantUMLPreviewer.
- **Рендер.** Офлайн, Java и Graphviz у пользователя не нужны (2d, 2e). При `newpage` показывается первая страница.

**Позже**
- **Автодополнение** ключевых слов, skinparam и цветов (есть у EasyPlantUML, Pladitor, PlantUMLPreviewer).
- **Сниппеты и шаблоны:** палитра как у PlantUML Renderer, галерея как у Pladitor. Сниппеты vscode-plantuml под Apache-2.0 (5).
- **Превью.** Переключатель страниц `newpage`, выбор фона.
- **Переход картинка → код** (двойной клик, как в Pladitor). Как привязать элементы SVG к строкам, нужно исследовать.
- **Экспорт** в другие форматы PlantUML (TXT/UTXT, EPS, LaTeX, VDX — есть у EasyPlantUML). PDF в MIT-jar нет (3b).
- **Импорт исходника из PNG/SVG** через `--extract-source`, как у Pladitor.
- **Quick Look extension:** есть платный конкурент, значит, спрос есть.
- **Вне фокуса:** Vim mode (VUML), своя модель данных (VUML), MCP/AI (Pladitor), удалённый сервер как основной режим.

## 2. Быстрый рендер PlantUML

- Ссылки на код ведут на master @ [`e41d08e`](https://github.com/plantuml/plantuml/commit/e41d08e1e28d739d02dd3a1a57d6926ef12248f1) (2026-09-29). Последний релиз — v1.2026.8 от 2026-09-05, локально установлен 1.2026.2.
- Местами документация plantuml.com отстаёт от кода, расхождения отмечены.
- **В 1.2026.x у CLI новые имена флагов** в стиле GNU: `--pipe`, `--http-server`, `--check-syntax` и т.д. Старые остаются алиасами. [command-line](https://plantuml.com/command-line): «legacy options will still be supported for a transition period, but they will no longer be documented».

Префикс `…/blob/e41d08e…/src/main/java/net/sourceforge/plantuml/` ниже сокращён до `PU/`.

### 2a. `-pipe`: один долгоживущий процесс

**Где код**
- Класс `net.sourceforge.plantuml.Pipe` ([Pipe.java](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java)). `Run` вызывает его при `--pipe`, `-pipemap` или `-syntax` ([Run.java#L182-L186](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Run.java#L182-L186)).

**Флаги в 1.2026.x** ([CliFlag.java#L99-L108](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliFlag.java#L99-L108)):
- `--pipe`, алиасы `-p` и legacy `-pipe`;
- `-pipemap`, `-pipedelimitor <str>`, `-pipenostderr`;
- `--pipe-image-index <n>` (legacy `-pipeimageindex`), по умолчанию 0.

**Регистр и опечатки во флагах**
- Регистр не важен ([CliFlag.java#L412-L419](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliFlag.java#L412-L419)), но **это вернули только в V1.2026.7** ([CHANGES.md#L82](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/CHANGES.md?plain=1#L82)).
- Неизвестный флаг молча игнорируется: `plantuml -syntax -foobarbaz` → exit 0 (локальная проверка).
- **Локальная проверка на 1.2026.2:** работает только `-pipenostderr` в нижнем регистре. С `-pipeNoStdErr` и `-pipeNoStderr` в stdout идёт картинка ошибки (8363 байта SVG), а отчёт — в stderr. То есть флаг просто не распознан.

**Много диаграмм подряд без EOF — да.**
- Цикл `for (source = readFirstDiagram(); source != null; source = readSubsequentDiagram())` на каждую диаграмму создаёт новый `SourceStringReader`, рендерит её и делает `ps.flush()` ([Pipe.java#L93-L112](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L93-L112)).
- `readSingleDiagram` читает только до строки, которая начинается с ожидаемого `@end…` ([Pipe.java#L202-L247](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L202-L247)).

**Подводные камни разбиения потока** (из того же кода, L208–L243):
- `@start…` и `@end…` проверяются через `startsWith`, поэтому должны стоять с 0-й колонки.
- Всё, что стоит до `@start`, отбрасывается.
- Текст без `@start` принимается только как первая диаграмма и только при EOF.
- Если `@end` нет, процесс ждёт дальше.
- Итог: приложение всегда шлёт полный блок `@startuml…@enduml` и ставит таймаут с перезапуском процесса.
- **Проверено на 1.2026.8 (байткод `Pipe.readSingleDiagram` и живые запуски):**
  - Оба тега чувствительны к регистру и отступу. `  @startuml`, `@StartUML` и `@startuml … @EndUML` не отвечают никогда.
  - Если строка начала целиком совпадает с `@start([A-Za-z]*)`, конец ждётся ровно `@end` плюс то же слово: после `@startmindmap` строка `@enduml` процесс не закроет, после `@startUML` нужен `@endUML`. Если после слова есть что-то ещё (`@startuml name`, `@startuml(id=x)`), подходит любая строка с `@end`.
  - В файловом режиме PlantUML принимает теги с отступом, но `@StartUML` не считает началом диаграммы («no image»). Поэтому Pumlpad находит теги как файловый режим, а отправляет блок в форме для `-pipe`: начало без отступа, в конце — строка, которую ждёт `-pipe`.
  - `@@@format png` внутри диаграммы переключает процесс на PNG и для всех следующих диаграмм. Pumlpad сдвигает такую строку на пробел.
- **Include-файлы в `-pipe` всегда читаются как UTF-8.** `Pipe.managePipe` создаёт `SourceStringReader` с `StandardCharsets.UTF_8`; `-charset` влияет только на stdin. В файловом режиме `-charset windows-1251` include читает правильно. `-Dfile.encoding` не помогает (проверено).

**Скрытая директива `@@@format png|svg|atxt|utxt`.** Такая строка во входном потоке переключает формат для следующих диаграмм ([Pipe.java#L210-L211, #L249-L259](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L249-L259)). На plantuml.com не описана.

**Формат вывода**
- Байты картинки идут прямо в stdout, префикса длины нет.
- `-pipedelimitor X` печатает `X\n` после каждой диаграммы ([Pipe.java#L145-L146](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L145-L146)).
- SVG начинается с `<?plantuml 1.2026.2?><svg …` и содержит `<?plantuml-src …?>` с закодированным исходником.
- **Локальная проверка:** разделитель пишется сразу после `</svg>`, без перевода строки (`…</g></svg>---END---`). Искать его нужно как подстроку, не как отдельную строку.

**Ошибка синтаксиса** ([Pipe.java#L115-L148](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L115-L148)):
- по умолчанию: в stdout — **картинка ошибки**, в stderr — текстовый отчёт;
- с **`-pipenostderr`**: картинка выбрасывается, отчёт идёт **в stdout** перед разделителем. На каждую диаграмму в stdout приходит либо картинка, либо отчёт, затем разделитель;
- с одним `--no-error-image`: картинка выбрасывается, отчёт остаётся в stderr.

Локальная проверка: `printf '@startuml\nA -> B\nfoo bar baz\n@enduml\n' | plantuml -pipe -tsvg -pipenostderr -stdrpt:2 -pipedelimitor ---END---` → stdout ровно `string:3:error:Syntax Error? (Assumed diagram type: sequence)\n---END---\n` (72 байта).

**Форматы отчёта.** Выбираются в [CliOptions.java#L123-L137](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliOptions.java#L123-L137):
- по умолчанию в pipe — `StdrptPipe0`: `ERROR\n<строка, 0-based>\n<сообщение>` ([StdrptPipe0.java#L50-L60](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/StdrptPipe0.java#L50-L60));
- `-stdrpt:1`: `protocolVersion=1 / status=ERROR / lineNumber=<1-based> / label=<msg>` ([StdrptV1.java#L65-L77](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/StdrptV1.java#L65-L77));
- **`-stdrpt:2`**: `string:<1-based>:error:<msg>` ([StdrptV2.java#L69-L85](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/StdrptV2.java#L69-L85)).
- **Для пустой диаграммы** (welcome screen) `-stdrpt:2` печатает пустую строку ([StdrptV2.java#L60-L66](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/StdrptV2.java#L60-L66)). Локальная проверка: `@startuml\n@enduml` в потоке дал пустую строку перед SVG.

**Отсчёт номера строки.**
- Строка 1 — это `@startuml` данной диаграммы. Строки до неё не считаются, `-S` и `-P` номер не сдвигают.
- Локальная проверка: `printf "x\ny\n@startuml\nA -> B\nfoo bar baz\n@enduml\n" | plantuml -syntax -stdrpt:2` → `string:3:error:…`.
- Смещение `@startuml` в файле приложение прибавляет само.

**Ошибка рендера и exit-коды**
- Если парсинг прошёл, а рендер упал (например, упал dot), выдаётся crash-картинка со статусом 503. У синтаксической ошибки статус 400. В обоих случаях итоговый exit-код — «ошибка» ([Pipe.java#L124-L132](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L124-L132), [FileImageData.java#L43-L44](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/FileImageData.java#L43-L44), [UgDiagram.java#L152-L162](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/UgDiagram.java#L152-L162)).
- Exit-коды: 0 / 50 / 100 / 200 ([ExitStatus.java#L40-L43](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/ExitStatus.java#L40-L43); см. также `plantuml -help`).

**Прочее**
- `--pipe-image-index N` — N-я страница при `newpage` ([CliOptions.java#L333-L339](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliOptions.java#L333-L339)).
- `-pipemap` — карта ссылок PNG (cmapx) или пустая строка ([Pipe.java#L150-L163](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L150-L163); [command-line, «Standard Input & Output»](https://plantuml.com/command-line)).
- **Относительные `!include`** считаются от `-filedir <dir>` ([Pipe.java#L95-L97](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L95-L97), [CliFlag.java#L213](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliFlag.java#L213)), без него — от текущей папки процесса. Значение **одно на процесс**, поэтому нужен один pipe-процесс на папку документа.

### 2b. `--http-server` / `-picoweb`

**Классы и синтаксис**
- `picoweb.PicoWebServer` ([PicoWebServer.java](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java)) и `picoweb.RenderRequest`.
- Флаг `--http-server[:<port>]`, legacy-алиас `-picoweb`, «default port : 8080» ([CliFlag.java#L91-L92](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliFlag.java#L91-L92)).
- Синтаксис `--http-server:PORT[:BINDADDR][:stop]` ([CliOptions.java#L146-L167](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliOptions.java#L146-L167)).
- Сокет: `new ServerSocket(port, 50, bind)`. **Без адреса слушает все интерфейсы.** В stderr печатаются `webPort=<порт>` и `webAddress=0.0.0.0` ([PicoWebServer.java#L96-L104](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L96-L104)).
  - [plantuml.com/picoweb](https://plantuml.com/picoweb): «By default, the server listens on all interfaces on port 8080», пример `-picoweb:8000:127.0.0.1`.
  - Порт `0` по коду допустим, реальный порт тогда виден в `webPort=`. Запуском не проверено.
  - На [command-line](https://plantuml.com/command-line) в блоке «future beta» у `--http-server` указан порт 4242, в коде — 8080.

**Маршруты** ([PicoWebServer.java#L128-L163](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L128-L163)):
- `GET /png|svg|txt|utxt/<encoded>`, те же с префиксом `/plantuml/`;
- `GET /serverinfo` (JSON), `GET /language`;
- `/stopserver` — только при `:stop`;
- **`POST /render`** с JSON `{"source": "...", "options": ["--svg", "-filedir", "..."]}` ([RenderRequest.java#L29-L44](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/RenderRequest.java#L29-L44)). Опции разбираются как CLI **на каждый запрос**, значит, `-filedir` можно менять. Текст без `@start` оборачивается в `@startuml…@enduml` ([#L272-L308](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L272-L308));
- на всё остальное — `302` на демо-картинку.

На странице picoweb описан только `GET /plantuml/png|svg`, **POST не документирован**.

**GET игнорирует настройки старта.** Он создаёт `new SourceStringReader(source)` без них, поэтому `-S` и `--theme`, заданные при старте, по коду не применяются. Рендерится только первый блок и страница 0 ([#L235-L255](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L235-L255)).

**Ответ** ([#L310-L344](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L310-L344)):
- заголовки `X-PlantUML-Diagram-Width/-Height/-Description`, `X-PlantUML-Diagram-Title`, `Access-Control-Allow-Origin: *`;
- при ошибке — `X-PlantUML-Diagram-Error: <msg>` и `X-PlantUML-Diagram-Error-Line: <1-based>`;
- статус GET: `200 OK`, `400 ERROR` (синтаксис) или `503 ERROR` (падение рендера) ([#L365-L370](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L365-L370));
- **`POST /render` всегда отвечает `200`**, ошибку видно только по заголовку;
- битый JSON → `400` text/plain, исключение → `500` со stack trace ([#L346-L363](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L346-L363)).

**Потоки.** Новый `Thread` на каждое соединение, пула нет. Соединение закрывается после ответа, keep-alive нет ([#L106-L118](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L106-L118), [#L171-L178](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/picoweb/PicoWebServer.java#L171-L178)).

**Безопасность**
- `PLANTUML_SECURITY_PROFILE` задаётся через env или `-D`; system property важнее ([SecurityUtils.java#L202-L213](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/security/SecurityUtils.java#L202-L213)).
- **По умолчанию — `LEGACY`** ([SecurityProfile.java#L114-L135](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/security/SecurityProfile.java#L114-L135)). По [plantuml.com/security](https://plantuml.com/security) это «full access to local files and full access to URL».
- Другие профили:
  - `INTERNET` — без локальных файлов, URL на портах 80/443;
  - `ALLOWLIST` — только пути и URL из `plantuml.allowlist.path`, `plantuml.include.path`, `plantuml.allowlist.url`;
  - `SANDBOX` — всё закрыто.
- picoweb свой профиль не выставляет.
- **Вывод из кода:** bind 0.0.0.0 + `ACAO: *` + `LEGACY` означают, что любая веб-страница в браузере пользователя может через `127.0.0.1:<port>` читать локальные файлы с помощью `!include`.
- Если использовать picoweb, то только `--http-server:0:127.0.0.1` и `ALLOWLIST`.

### 2c. Номер строки ошибки программно

- **`-syntax`** (stdin, без рендера) работает в том же потоковом цикле Pipe ([Pipe.java#L171-L183](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Pipe.java#L171-L183)).
  - Без ошибки — `<ТИП>\n<описание>` (например, `SEQUENCE` и `(2 participants)`), с ошибкой — отчёт в формате stdrpt из 2a.
  - Локальная проверка с `-stdrpt:1` → `SEQUENCE / (2 participants) / protocolVersion=1 / status=ERROR / lineNumber=3 / label=Syntax Error? …`, exit 200.
- **`--check-syntax`** (legacy `-checkonly`) работает по файлам и **номер строки не выводит**. Печатается только «Some diagram description contains errors», exit 200 ([Run.java#L347-L348](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/Run.java#L347-L348); локальная проверка).
- **`--stop-on-error` (`-failfast`) и `--check-before-run` (`-failfast2`)** управляют только пакетной обработкой файлов ([CliFlag.java#L138-L148](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliFlag.java#L138-L148)). Для превью не нужны.
- **picoweb:** заголовок `X-PlantUML-Diagram-Error-Line`, 1-based (2b).
- **Ошибка во включённом файле** (`-stdrpt:2`, проверено на 1.2026.8): источник — путь из самого внутреннего `!include` как он написан (`b.iuml` для `!include b.iuml` внутри `sub/a.iuml`), строка — в этом файле. Если у файла свой `@startuml`, источник называется `desc2`, а строка считается от начала файла. Pumlpad находит нужный `!include` диаграммы, проходя по include-файлам.
- **Java API** (если держать свою JVM-обёртку): `SourceStringReader.getBlocks().get(0).getDiagram()` → `PSystemError` → `getLineLocation().getPosition()` (0-based) и `getErrorsUml()` ([PSystemError.java#L102-L108](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/error/PSystemError.java#L102-L108)).
- **Картинка ошибки.**
  - Показывает исходник до ошибки, ошибочную строку с красным волнистым подчёркиванием и сообщение ([PSystemError.java#L126-L146](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/error/PSystemError.java#L126-L146)).
  - Кроме того, на неё **добавляются баннеры, которые меняются по минутам** (Patreon / Liberapay / QR «dedication»), а к коротким исходникам — приветственный блок ([#L213-L235](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/error/PSystemError.java#L213-L235)). Из CLI их не отключить, только через Java API `disableTimeBasedErrorDecorations()`.
  - Вывод: ошибку показывать своим UI по номеру строки.

### 2d. Smetana, ELK, Graphviz

**Smetana**
- Включается `!pragma layout smetana` или `-Playout=smetana` ([smetana02](https://plantuml.com/smetana02); [CommandPragma.java#L116-L121](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/command/CommandPragma.java#L116-L121)). `-P` превращается в строку `!pragma` ([CliOptions.java#L115-L116](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliOptions.java#L115-L116)).
- **Без dot PlantUML сам переключается на Smetana:** `else if (isUseSmetana() || dotIsAvailable() == false) → CucaDiagramFileMakerSmetana` ([CucaDiagram.java#L478-L504](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/atmp/CucaDiagram.java#L478-L504)).
  - Это есть **с V1.2026.7** («fall back to Smetana when Graphviz/dot is unavailable», [CHANGES.md#L64](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/CHANGES.md?plain=1#L64)). **В локальной 1.2026.2 этого нет.**
- **Graphviz нужен только** для use case, class, object, component, deployment, state и legacy activity. Остальным типам «GraphViz is not needed nor used» ([graphviz-dot](https://plantuml.com/graphviz-dot)). Та же страница называет Smetana «experimentally».
- **Качество:**
  - [layout-engines](https://plantuml.com/layout-engines): «tends to make slightly straighter arrows»;
  - в V1.2026.7 много исправлений Smetana — вложенные узлы, группы, стрелки, параллельные состояния ([CHANGES.md#L51-L71](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/CHANGES.md?plain=1#L51-L71));
  - официального списка ограничений нет.

**Поиск dot на macOS** ([GraphvizLinux.java#L50-L57](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/dot/GraphvizLinux.java#L50-L57); класс используется на всех ОС, кроме Windows, [GraphvizRuntimeEnvironment.java#L125-L128](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/dot/GraphvizRuntimeEnvironment.java#L125-L128)):
- порядок: `/usr/local/bin/dot` → `/opt/homebrew/bin/dot` → `/opt/homebrew/opt/graphviz/bin/dot` → `/usr/bin/dot` → `/opt/local/bin/dot`;
- приоритет: `--dot-path` > `-DGRAPHVIZ_DOT` > env `GRAPHVIZ_DOT` ([#L99-L113](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/dot/GraphvizRuntimeEnvironment.java#L99-L113));
- страница graphviz-dot перечисляет только два старых пути.

**ELK**
- Включается `!pragma layout elk` или `-Playout=elk`. С V1.2024.6 входит в `plantuml.jar`, статус alpha ([elk](https://plantuml.com/elk)).
- layout-engines: «supports only orthogonal layout, and doesn't cover all features».
- Локальная проверка: `unzip -l plantuml.jar | grep -c org/eclipse/elk` → 805. В MIT-jar ELK не встроен (3b).

**VizJs.** Java-вариант VizJs требует J2V8, а он для macOS есть только под x86_64 ([vizjs](https://plantuml.com/vizjs)).

**Версию движка стоит зафиксировать.**
- С V1.2026.7 sequence-диаграммы по умолчанию рисует Teoz, а не Puma ([CHANGES.md#L47](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/CHANGES.md?plain=1#L47); [PragmaKey.java#L64](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/skin/PragmaKey.java#L64) `TEOZ("true")`).
- layout-engines всё ещё называет движком по умолчанию Puma.

### 2e. Как обойтись без Java у пользователя

**1. Урезанная Java (jlink) + jar — самый совместимый путь.**
- Модули по `jdeps --print-module-deps --ignore-missing-deps --multi-release base plantuml.jar`: `java.base,java.compiler,java.desktop,java.logging,java.prefs,java.scripting,jdk.unsupported`.
- `jlink --add-modules <эти> --strip-debug --no-header-files --no-man-pages --compress=zip-9` дал **45M** на JDK 25.0.2 (Homebrew) и **49M** на JDK 21.0.12 (Temurin) по `du -sh`. Готовые образы для замеров лежат рядом с этим файлом: `jlink/jre25` и `jlink/jre21`. С этой Java проверены SVG sequence, PNG class через dot и SVG через Smetana (локальный замер).
- `plantuml.jar` 1.2026.2 требует Java 11+: у class-файлов версия 55 (локальная проверка). Для Java 8 в релизе есть `plantuml-java8-*.jar`.
- Размеры jar в [v1.2026.8](https://github.com/plantuml/plantuml/releases/tag/v1.2026.8): GPL `plantuml.jar` 29.9 MB, `plantuml-mit` 17.7 MB, `plantuml-mit-light` 7.9 MB (в MiB см. 3a).
- **Итого около 63–68 MB с MIT-jar.** Это примерно вдвое меньше EasyPlantUML (117.8 MB).
- Homebrew-обёртка `/opt/homebrew/bin/plantuml` запускает jar с `-Djava.awt.headless=true` и `GRAPHVIZ_DOT=/opt/homebrew/opt/graphviz/bin/dot` (локальная проверка).

**2. Официальная нативная сборка (GraalVM native-image), с V1.2026.5** («add native image builds (macOS)», [CHANGES.md#L108-L117](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/CHANGES.md?plain=1#L108-L117)).
- Подпроект `plantuml-natif` собирается из **того же GPL-кода**, что и основной jar, с `-Djava.awt.headless=true`, `-march=compatibility`, `--enable-url-protocols=https`. Точка входа — `Run`, поэтому доступен весь CLI, включая `-pipe` ([build.gradle.kts#L1-L17, #L46-L74](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/plantuml-natif/build.gradle.kts#L46-L74)).
- CI собирает на Liberica NIK / Java 21, для macOS **только arm64**. В CI проверяется лишь `-pipe -ttxt` ([native-image-release.yml#L154-L194](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/.github/workflows/native-image-release.yml#L154-L194); [BUILDING.md#L110-L148](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/docs/BUILDING.md?plain=1#L110-L148)).
- Архив `native-plantuml-macos-arm64-1.2026.8.zip` весит 55.0 MB.
- JNI/reflection-конфигурацию снимали **на Windows** ([native-agent.yml#L3-L14](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/.github/workflows/native-agent.yml#L3-L14)). В `jni-config.json` есть `sun.awt.Win32GraphicsEnvironment`, классов macOS нет.
- В GraalVM AWT на macOS не поддержан: [oracle/graal#13272](https://github.com/oracle/graal/issues/13272) открыт с 2026-04-02, по комментарию от 2026-07-16 исправление есть только в nightly CE. BellSoft утверждает, что NIK Full собирает AWT-приложения «on Linux, Windows, and macOS» ([bell-sw.com](https://bell-sw.com/blog/how-to-turn-awt-applications-into-native-images/)).
- PlantUML измеряет текст шрифтами AWT даже при выводе в SVG.
- **Итог: работают ли PNG и SVG в официальной macOS-сборке, не подтверждено.**

**3. Официальный JS-движок (TeaVM): npm [`@plantuml/core`](https://www.npmjs.com/package/@plantuml/core).**
- Собран из MIT-варианта: MIT с 1.2026.6, раньше был под GPL. Исключена только Sudoku ([PUBLISHING_NPM.md#L1-L27](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/PUBLISHING_NPM.md?plain=1#L1-L27); [README.md.tmpl#L77-L84](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/license-variants/plantuml-mit/npm/README.md.tmpl#L77-L84)).
- Версия 1.2026.8 (2026-09-06), 7.76 MB в распакованном виде.
- API: `render(lines, id, {dark})` и `renderToString(lines, ok, err)`, **только SVG** ([PlantUMLBrowser.java#L283-L335](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/teavm/browser/PlantUMLBrowser.java#L283-L335)).
- Graphviz — через `viz-global.js` (Viz.js). Без него с 1.2026.8 используется Smetana ([CucaDiagram.java#L467-L475](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/atmp/CucaDiagram.java#L467-L475)).
- `!theme` требует `themes.js`. **Stdlib (включая C4) в пакет не входит**, её подключают через `PLANTUML_STDLIB_BASE` или `PLANTUML_STDLIB_LOADER` ([README.md.tmpl#L28-L75](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/license-variants/plantuml-mit/npm/README.md.tmpl#L28-L75)).
- Максимальный размер SVG по умолчанию 8192 px (`maxSvgSize`, [#L466-L470](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/teavm/browser/PlantUMLBrowser.java#L466-L470)).
- Синтаксическая ошибка приходит как SVG-картинка ошибки; `onError` срабатывает только на исключения ([#L528-L535](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/teavm/browser/PlantUMLBrowser.java#L528-L535)).
- Текст измеряется через canvas `measureText`, то есть шрифтами WebView ([StringBounderTeaVM.java#L119-L123](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/teavm/StringBounderTeaVM.java#L119-L123)).
- В JS-сборке текущая папка — `null`, поэтому **локальные `!include` не работают**. Это вывод из кода, запуском не проверен ([PathSystem.java#L68-L74](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/nio/PathSystem.java#L68-L74)).
- Headless-вариант (Node, `@plantuml/mcp-js`) даёт `checkSyntax` в JSON с `errorLineNumber` (1-based) и «font-metrics-free» SVG ([PlantUMLHeadless.java#L68-L100](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/teavm/headless/PlantUMLHeadless.java#L68-L100); [README-NPM.md#L105-L182](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/plantuml-mcp-js/README-NPM.md?plain=1#L105-L182)).
- Живые примеры:
  - [dlutcat/plantuml-quicklook](https://github.com/dlutcat/plantuml-quicklook/blob/main/scripts/build.py) рендерит plantuml.js (TeaVM) в WKWebView офлайн (build.py L47–L55);
  - [plantuml-live-editor](https://github.com/oakraw/plantuml-live-editor) использует CheerpJ + [plantuml-core](https://github.com/plantuml/plantuml-core) (1c).

**Что реалистично для лёгкого приложения**
1. **jlink + MIT-jar + долгоживущий `-pipe`.** Полная совместимость: PNG и SVG, stdlib и темы офлайн, локальные `!include`. Около 63–68 MB, Java у пользователя не нужна.
2. **`@plantuml/core` в WKWebView.** Около 8 MB, MIT, без Java. Цена: только SVG, нет локальных `!include`, stdlib надо везти отдельно, пакету несколько месяцев. Годится как лёгкий режим или вариант для Quick Look.
3. **Нативная сборка.** Быстрый старт, но GPL, только arm64 и не подтверждена на macOS для PNG/SVG. Сначала проверить локально.

### 2f. Чёткий PNG на Retina

- **Масштаб считается как `scale × dpi / 96`, dpi по умолчанию 96** ([TextBlockExporter.java#L204-L208](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/core/TextBlockExporter.java#L204-L208); [SkinParam.java#L647-L654](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/skin/SkinParam.java#L647-L654)).
  - Для 2× нужно `skinparam dpi 192` или `-Sdpi=192`. `-S` добавляется как `skinparamlocked` и перекрывает skinparam самой диаграммы ([CliOptions.java#L118-L119](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliOptions.java#L118-L119)).
  - Директива `scale` умножается туда же.
  - Флага `-dpi` в CLI нет ([CliFlag.java](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliFlag.java)). Локальная проверка на 1.2026.2: `-dpi192` молча игнорируется (PNG 65×104, как без флага), а `-Sdpi=192` даёт 131×209.
- **PNG всегда помечен как 96 dpi.** Растёт только число пикселей ([#L344-L345](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/core/TextBlockExporter.java#L344-L345), [#L178](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/core/TextBlockExporter.java#L178)). Размер в точках (пиксели / 2) приложение выставляет само.
- **dpi масштабирует и SVG** ([#L280-L285](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/core/TextBlockExporter.java#L280-L285)), поэтому для SVG-превью `-Sdpi` не передавать.
- **`PLANTUML_LIMIT_SIZE` по умолчанию 4096 px** ([GraphvizUtils.java#L63-L73](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/dot/GraphvizUtils.java#L63-L73); [faq](https://plantuml.com/faq)).
  - PNG больше лимита обрезается ([EmptyImageBuilder.java#L68-L76](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/EmptyImageBuilder.java#L68-L76)).
  - Лимит проверяется **после** умножения на dpi, поэтому при 192 dpi обрезается всё шире ≈2048 px исходной ширины.
  - Поднять: env, `-DPLANTUML_LIMIT_SIZE=8192` в JVM или `-D` в CLI PlantUML ([CliOptions.java#L102-L104](https://github.com/plantuml/plantuml/blob/e41d08e1e28d739d02dd3a1a57d6926ef12248f1/src/main/java/net/sourceforge/plantuml/cli/CliOptions.java#L102-L104)). Для огромных картинок FAQ советует увеличить `-Xmx`.
  - PlantUMLPreviewer, например, передаёт `-DPLANTUML_LIMIT_SIZE=16384` (1c).
- **Не все типы понимают `skinparam dpi`** (проверено на 1.2026.8, ширина PNG): uml, mindmap, wbs, gantt, salt, nwdiag, regex, ebnf, chen и chart удваиваются; json, yaml и math остаются 1× — им нужен `scale 2`. `-Sdpi=192` ломает json и yaml (картинка ошибки). ditaa масштабируется только опцией начала `@startditaa(scale=2)` (проверено на GPL-jar 1.2026.2). Pumlpad выбирает способ по типу диаграммы.
- **Вывод:** превью показывать в SVG, оно не зависит от разрешения. PNG нужен только для экспорта и буфера обмена.

### 2g. Темы и stdlib офлайн

- **`!theme`:** темы «included into the library… working out of the box» ([theme](https://plantuml.com/theme)). В jar лежат 44 файла `themes/puml-theme-*` (локальная проверка). `!theme foo from https://…` требует сеть.
- **Stdlib** «included in all official releases», есть `-stdlib` и `-extractstdlib` ([stdlib](https://plantuml.com/stdlib)).
  - В jar 1.2026.2: `stdlib/<lib>/*.spm`, 100 файлов, ≈8.9 MB. C4 лежит в `stdlib/c4/puml.spm`, так что `!include <C4/C4_Container>` работает офлайн (локальная проверка).
  - Те же stdlib и темы есть в MIT-jar, но **не в MIT-light** (3b). В JS-сборке stdlib подключается отдельно (2e).

## 3. Лицензия

### 3a. Варианты дистрибутива

Последняя версия — 1.2026.8, ассеты выложены 2026-09-05. Источники: [plantuml.com/download](https://plantuml.com/download), [ассеты релиза v1.2026.8](https://github.com/plantuml/plantuml/releases/expanded_assets/v1.2026.8), [Maven Central](https://repo1.maven.org/maven2/net/sourceforge/plantuml/).

| Вариант | jar (GitHub Releases) | Размер, MB (MiB) | Maven `net.sourceforge.plantuml:` | Лицензия |
|---|---|---|---|---|
| GPLv3 | `plantuml-1.2026.8.jar` (= `plantuml.jar`) | 29.9 (28.5) | `plantuml` | GPL-3.0 |
| GPLv2 | `plantuml-gplv2-1.2026.8.jar` | 18.0 (17.1) | `plantuml-gplv2` | GPL-2.0 |
| LGPL | `plantuml-lgpl-1.2026.8.jar` | 17.7 (16.9) | `plantuml-lgpl` | LGPL-3.0-or-later |
| ASL | `plantuml-asl-1.2026.8.jar` | 17.7 (16.9) | `plantuml-asl` | Apache-2.0 |
| BSD | `plantuml-bsd-1.2026.8.jar` | 17.7 (16.9) | `plantuml-bsd` | BSD (download ссылается на BSD-3-Clause) |
| EPL | `plantuml-epl-1.2026.8.jar` | 29.5 (28.1), fat jar | `plantuml-epl` | на download — EPL-2.0, в POM и заголовке файлов — EPL-1.0 (расхождение) |
| **MIT** | `plantuml-mit-1.2026.8.jar` | **17.7 (16.9)** | `plantuml-mit` | MIT |
| MIT light | `plantuml-mit-light-1.2026.8.jar` | 7.9 (7.6) | `plantuml-mit-light` | MIT (**без stdlib/C4**, см. 3b) |

- К каждому jar приложены `-sources.jar`, `-javadoc.jar` и подписи `.asc`.
- В том же релизе лежат `plantuml-java8-1.2026.8.jar`, **`native-plantuml-macos-arm64-1.2026.8.zip` (55.0 MB)** (есть также linux и windows) и **`js-plantuml-1.2026.8.zip` (31.7 MB)**. Размеры взяты из байтов GitHub API; GitHub в интерфейсе показывает MiB с подписью «MB».
- Maven Central: все 8 артефактов опубликованы в 1.2026.8 (lastUpdated 20260905). У GPL-артефакта `plantuml` в `maven-metadata.xml` `<latest>/<release>` = `8059` (старая нумерация), поэтому версию нужно фиксировать явно.
- Все варианты собираются в CI из одного дерева исходников. SJPP подставляет define `__<ID>__` и заголовок `<id>-license.txt`:
  - [license-variants/README.md](https://github.com/plantuml/plantuml/blob/master/license-variants/README.md);
  - [settings.gradle.kts#L34-L50](https://github.com/plantuml/plantuml/blob/master/settings.gradle.kts#L34-L50);
  - [plantuml.license-variant.gradle.kts#L118-L146](https://github.com/plantuml/plantuml/blob/master/license-variants/build-logic/src/main/kotlin/plantuml.license-variant.gradle.kts#L118-L146).

### 3b. Что вырезано из не-GPL сборок

**Официальная позиция**
- Таблица на [download](https://plantuml.com/download): Ditaa есть только в GPLv3, GPLv2 и LGPL; Jcckit и Sudoku — только в GPLv3 и GPLv2; ELK — только в EPL.
- [FAQ, «I don't like GPL!»](https://plantuml.com/faq): «Those versions miss few features (DITAA for example), but are 100% able to generate UML diagrams».

**Что на самом деле входит в сборки (скрипты сборки, master)**
- GPL-jar — fat jar: в нём jlatexmath, ELK (core/layered/mrtree), xtext-xbase-lib и OpenPDF ([build.gradle.kts#L48-L53, #L116-L123](https://github.com/plantuml/plantuml/blob/master/build.gradle.kts#L48-L53)).
- В лицензионных вариантах jlatexmath и OpenPDF подключены только как compileOnly/testImplementation, в jar они не попадают. Ресурсы (stdlib, темы, skin) берутся из общего `src/main/resources` ([plantuml.license-variant.gradle.kts#L50-L57, #L72-L81](https://github.com/plantuml/plantuml/blob/master/license-variants/build-logic/src/main/kotlin/plantuml.license-variant.gradle.kts#L50-L57)).
- EPL — fat jar с jlatexmath, ELK и OpenPDF ([plantuml-epl/build.gradle.kts#L15-L24](https://github.com/plantuml/plantuml/blob/master/license-variants/plantuml-epl/build.gradle.kts#L15-L24)).
- **MIT-light** = MIT без `**/*.spm` (весь stdlib, включая C4), без `emoji/data/**` и без `teavm/**` ([plantuml-mit-light/build.gradle.kts#L35-L36, #L53-L56](https://github.com/plantuml/plantuml/blob/master/license-variants/plantuml-mit-light/build.gradle.kts#L35-L36)). Если C4 нужен офлайн, MIT-light не подходит.
- Официальный native-бинарь собирается из корневого GPL-проекта без SJPP, значит, он под **GPL** ([plantuml-natif/build.gradle.kts#L5-L9](https://github.com/plantuml/plantuml/blob/master/plantuml-natif/build.gradle.kts#L5-L9)).

**Локальная проверка.** `unzip -l` двух jar версии 1.2026.2: GPL из Homebrew и `plantuml-mit-1.2026.2.jar` (19.4 MB) из плагина plantuml4idea.

| Содержимое | GPL | MIT |
|---|---|---|
| `jcckit/` | 82 записи | 0 |
| `net/sourceforge/plantuml/sudoku/` | 9 | 0 |
| `org/scilab` (jlatexmath) | 332 | 0 |
| `org/eclipse` (ELK+EMF) | 1751 | 0: есть только прокси `net/sourceforge/plantuml/elk`, ELK подключается через `elk-full.jar` из Class-Path в MANIFEST |
| `org/stathissideris` (ditaa) | 40 | 40, размеры классов совпадают |
| `gen/lib`, `smetana/core` (Smetana) | есть | есть |
| stdlib (34 библиотеки, в т.ч. C4) | есть | есть |
| `themes/` (44 `.puml`) | есть | есть |
| `windowsdot/graphviz.dat` | есть | есть |

- **Таблица на download в двух местах устарела.** Ditaa есть и в MIT: это видно по списку пакетов `org.stathissideris.ascii2image.*` в [javadoc plantuml-mit 1.2026.6](https://javadoc.io/static/net.sourceforge.plantuml/plantuml-mit/1.2026.6/element-list). ELK встроен и в GPL-jar.
- Вероятно, в MIT-сборке не работают `<latex>` (нет jlatexmath), экспорт в PDF (нет OpenPDF) и ELK без `elk-full.jar`. Рендером **не проверено**.
- **ditaa в MIT 1.2026.8 не рендерится**, хотя классы `org/stathissideris` в jar есть: `@startditaa` даёт картинку «Diagram not supported by this release of PlantUML» (проверено рендером). То же для `@startchronology`. В GPL-jar ditaa работает.

### 3c. Сторонний код внутри «MIT»-jar

- **Smetana** — порт Graphviz. В заголовке файлов: «This translation is distributed under the same License as the original C program … Eclipse Public License v1.0», копирайт AT&T 2011 ([position__c.java#L12-L24](https://github.com/plantuml/plantuml/blob/master/src/main/java/gen/lib/dotgen/position__c.java#L12-L24), [Macro.java#L12-L27](https://github.com/plantuml/plantuml/blob/master/src/main/java/smetana/core/Macro.java#L12-L27)). Какой заголовок у этих файлов в текущем `plantuml-mit-*-sources.jar`, **не проверено**.
- **ditaa** — LGPL-3.0-or-later, © Efstathios Sideris ([ConversionOptions.java#L1-L18](https://github.com/plantuml/plantuml/blob/master/src/main/java/org/stathissideris/ascii2image/core/ConversionOptions.java#L1-L18)).
- **`graphviz.dat`** — минимальный `dot.exe` для Windows, который распаковывается во временную папку ([plantuml.com/graphviz-dot](https://plantuml.com/graphviz-dot)). Это Graphviz, то есть EPL. На macOS не используется.
- **`java -jar plantuml-mit-1.2026.2.jar -license`** (локальная проверка):
  - перечислены OpenIconic, спрайты Archi, AWS-PlantUML, tupadr3, ASCIIMathML, CafeUndZopfli, Brotli, puml-themes и Twemoji;
  - Smetana (EPL) и ditaa (LGPL) не упомянуты;
  - есть строка «This distribution bundles a minimal set of GraphViz files». При этом [mit-license.txt#L58-L60](https://github.com/plantuml/plantuml/blob/master/license-variants/plantuml-mit/mit-license.txt#L58-L60) называет сборку «IGY distribution (Install GraphViz by Yourself)» — одно противоречит другому.
- Лицензия PlantUML на сгенерированные картинки не распространяется ([faq](https://plantuml.com/faq), [mit-license.txt#L45-L56](https://github.com/plantuml/plantuml/blob/master/license-variants/plantuml-mit/mit-license.txt#L45-L56)).

### 3d. Встраивание в open-source приложение под MIT или Apache

**Вариант A (рекомендуемый).** Положить неизменённый `plantuml-mit` (для Apache-приложения можно `plantuml-asl`) в `Contents/Resources` и выполнить следующее:
1. **MIT.** Копирайт Arnaud Roques и текст `mit-license.txt` — в `Licenses/` и в окно About/Acknowledgements.
2. **EPL-1.0 (Smetana, graphviz.dat).** По §3 EPL-1.0 при распространении в объектном виде нужно: отказаться от гарантий, сообщить, что «source code for the Program is available», и объяснить, как его получить, плюс приложить текст EPL ([epl-v10](https://www.eclipse.org/legal/epl-v10.html)). На практике: текст EPL-1.0 и ссылка на `plantuml-mit-<ver>-sources.jar`.
3. **LGPL-3.0 (ditaa).** Jar остаётся отдельным заменяемым файлом. Нужно приложить LGPL-3.0 и GPL-3.0 и дать исходники: «if you yourself convey the executable LGPLed library along with your application… you must also convey the library's sources» ([GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html#LGPLStaticVsDynamic)).
4. **stdlib.** У каждой библиотеки своя лицензия, общего LICENSE в [plantuml-stdlib](https://github.com/plantuml/plantuml-stdlib) нет. `plantuml -stdlib` показывает источник каждой библиотеки (строка «Delivered by …»; локально C4 = 2.13.0).
   - C4-PlantUML — MIT ([LICENSE](https://github.com/plantuml-stdlib/C4-PlantUML/blob/master/LICENSE));
   - AWS icons — иконки под CC-BY-ND 2.0, код под MIT ([license summary](https://github.com/awslabs/aws-icons-for-plantuml#license-summary));
   - Twemoji — графика под CC-BY 4.0, код под MIT ([jdecked/twemoji](https://github.com/jdecked/twemoji)).
5. **Доступность исходников.** Их можно держать на другом сайте, но «make sure that the source remains available for as long as you distribute» ([GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html#SourceAndBinaryOnDifferentSites)). Надёжнее выложить копию `sources.jar` в собственный GitHub Release.

**Вариант B — GPL-компонент как отдельный процесс** (`plantuml.jar` или официальный native-бинарь через `-pipe` или HTTP).
- «pipes, sockets and command-line arguments are communication mechanisms normally used between two separate programs» — это агрегат ([GPL FAQ, MereAggregation](https://www.gnu.org/licenses/gpl-faq.html#MereAggregation)). Код приложения остаётся под MIT.
- На сам компонент ложатся обязанности GPL: текст лицензии и Corresponding Source.
- Для LGPL-jar FAQ PlantUML разрешает встраивать неизменённый файл даже в закрытое ПО, если указать, что используется PlantUML под LGPL ([faq](https://plantuml.com/faq)).

**Вариант C — JS-движок.** npm `@plantuml/core` 1.2026.8 под MIT, распакованный размер 7.76 MB ([registry](https://registry.npmjs.org/@plantuml%2Fcore/latest)).
- Собирается из MIT-варианта ([plantuml-mit/build.gradle.kts#L37-L41, #L98-L102](https://github.com/plantuml/plantuml/blob/master/license-variants/plantuml-mit/build.gradle.kts#L37-L41)).
- Внутри `viz-global.js` — это Viz.js, «WebAssembly build of Graphviz», обёртка под MIT ([mdaines/viz-js](https://github.com/mdaines/viz-js)). Для самого Graphviz внутри действует EPL — это вывод, не проверено.

**JRE в .app.** OpenJDK распространяется под GPLv2 + Classpath Exception ([openjdk.org](https://openjdk.org/legal/gplv2+ce.html)). В `$(/usr/libexec/java_home -v 17)/legal` лежат 70 каталогов модулей, в `java.base` есть LICENSE, ASSEMBLY_EXCEPTION и ADDITIONAL_LICENSE_INFO (локальная проверка). Каталог `legal/` нужно сохранить в образе. jlink переносит его сам: в образах `jlink/jre25` и `jlink/jre21` есть `legal/` для 9 модулей (7 заданных и транзитивные `java.datatransfer`, `java.xml`), в `java.base` лежат LICENSE, ASSEMBLY_EXCEPTION и ADDITIONAL_LICENSE_INFO (локальная проверка).

### 3e. Graphviz

- **Лицензия.** «The current versions of the Graphviz software are now licensed … only under the Eclipse Public License». Сейчас на странице текст EPL-2.0; сайт правили 2026-03-07 с сообщением «Change from Common Public License Version 1.0 to Eclipse Public License version 2.0» ([graphviz.org/license](https://graphviz.org/license/)).
  - EPL-2.0 требует при любой форме распространения сделать исходники доступными и сказать, как их получить (§3.1), и не удалять notices (§3.3).
- **Как PlantUML вызывает dot.** Запускает `dot -T<type>` ([AbstractGraphviz.java#L165-L183](https://github.com/plantuml/plantuml/blob/master/src/main/java/net/sourceforge/plantuml/dot/AbstractGraphviz.java#L165-L183)), тип всегда `svg` ([DotStringFactory.java#L305](https://github.com/plantuml/plantuml/blob/master/src/main/java/net/sourceforge/plantuml/svek/DotStringFactory.java#L305)).
- **Локальная проверка.**
  - `echo 'digraph{a->b}' | dot -Tsvg -v` показывает, что работают только плагины `libgvplugin_core` (render svg:core) и `libgvplugin_dot_layout`.
  - `otool -L` на `dot` 14.1.5 из Homebrew: libgvc, libxdot, libpathplan, libcgraph, libcdt, плюс libltdl из libtool, плюс системные libexpat и libz.
- **Минимальный набор для встраивания** (оценка, не проверено): `dot`, 5 dylib Graphviz, libltdl, 2 плагина и config (`dot -c`). Затем переписать install_name и подписать.
- Для MVP встраивать `dot` не обязательно: в jar уже есть Smetana.

## 4. Сборка .app без Xcode

Среда (локальная проверка):
- `sw_vers` → macOS 27.0;
- `xcode-select -p` → `/Library/Developer/CommandLineTools`;
- `swift --version` → Apple Swift 6.4, target arm64-apple-macosx27.0;
- Xcode.app в /Applications нет.

### 4a. SwiftPM + SwiftUI/AppKit на CLT: что недоступно

| Что | На CLT | Источник |
|---|---|---|
| `swift build/run/test/package`, `swift-format`, `sourcekit-lsp`, `lldb`, `lipo` | есть | локальная проверка: `ls /Library/Developer/CommandLineTools/usr/bin` |
| `xcodebuild` | **нет**. `/usr/bin/xcodebuild` — шим, на `-version` отвечает «tool 'xcodebuild' requires Xcode, but active developer directory … is a command line tools instance» | локальная проверка |
| `actool` (`.xcassets`, AppIcon, `CFBundleIconName`) | **нет** (`xcrun --find actool` → unable to find utility) | локальная проверка |
| `ibtool` (xib/storyboard/nib) | **нет** | локальная проверка |
| Instruments / `xctrace` | **нет** | локальная проверка |
| `@Observable` | **работает**: в CLT есть `usr/lib/swift/host/plugins/libObservationMacros.dylib`, `swiftc -typecheck` проходит. Требует macOS 14+: `@available(macOS 14.0 …)` в SDK `Observation.swiftmodule/arm64e-apple-macos.swiftinterface` L24–L25 | локальная проверка |
| `#Preview` | **не компилируется**: «external macro implementation type 'PreviewsMacros.SwiftUIView' could not be found … plugin for module 'PreviewsMacros' not found». Объявлен в SDK `SwiftUI.swiftinterface` L25108–L25112 | локальная проверка |
| `@Entry` (SwiftUI) | **не компилируется**: «plugin for module 'SwiftUIMacros' not found» | локальная проверка |
| Foundation `#Predicate` / `#Expression` / `#bundle` | `libFoundationMacros.dylib` в CLT не найден, компиляцией не проверено | не подтверждено |
| XCTest | `XCTest.framework` в CLT **нет**. Есть Swift Testing: `Library/Developer/Frameworks/Testing.framework` и `host/plugins/testing/libTestingMacros.dylib` | локальная проверка |

**Ресурсы, которым нужен Xcode.** SwiftPM сам помечает `nib/xib/storyboard`, `xcassets`, `xcstrings`, `xcdatamodel(d)` и `metal` как «requires the Xcode build system» ([TargetSourcesBuilder.swift#L793-L898](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageLoading/TargetSourcesBuilder.swift#L793-L898)). Бэкенд `swiftbuild` эти типы распознаёт. Скомпилирует ли он их без actool и ibtool — не подтверждено.

**SwiftPM не собирает .app.** `ProductType` бывает только library, executable, snippet, plugin, test или macro ([Product.swift#L89-L127](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageModel/Product.swift#L89-L127)). Значит, бандл собирается скриптом вокруг `swift build`.

**Ловушка с `Bundle.module`.**
- Сгенерированный accessor ищет `<Pkg>_<Target>.bundle` в `Bundle.main.bundleURL`, то есть в корне `X.app/`, вне `Contents/`.
- Если там нет, пробует абсолютный путь в `.build`, а затем падает с `fatalError("could not load resource bundle…")` ([SwiftModuleBuildDescription.swift#L406-L445](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L406-L445)).
- Apple при этом требует класть ресурсы в `Contents/Resources/`: «If you put content in the wrong location, you may encounter hard-to-debug code signing and distribution problems» ([Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)).
- Вывод: копировать ресурсы в `Contents/Resources` и читать через `Bundle.main`.

**Официальной позиции нет.** swift.org пишет только: «To develop with Swift for Apple platforms, download the latest version of Xcode» ([swift.org/install/macos](https://www.swift.org/install/macos/)). Руководства по сборке SwiftUI-приложения на одних CLT не найдено.

**Рабочий пример на одних CLT:** [dlutcat/plantuml-quicklook](https://github.com/dlutcat/plantuml-quicklook/blob/main/scripts/build.py).
- Собирает .app и Quick Look appex «using macOS Command Line Tools only» (L2, L24–L29, L57–L94).
- Цепочка: `xcrun swiftc` без SwiftPM → Info.plist через plistlib → `codesign --sign` с идентичностью `-` по умолчанию → `codesign --verify --deep --strict`.
- Там же PlantUML рендерится **офлайн через plantuml.js (TeaVM) внутри WKWebView** (build.py L47–L55), см. раздел 2e.

### 4b. Структура .app, Info.plist, ассоциация файлов, иконка

**Структура бандла.** `X.app/Contents/{Info.plist, MacOS/, Resources/}`, каталог `MacOS/` обязателен. Mach-O-код кладётся только в места для кода:
- dylib и framework — `Contents/Frameworks/`;
- plug-in и appex — `Contents/PlugIns/`;
- helper tool — `Contents/MacOS/` или `Contents/Helpers/`;
- XPC — `Contents/XPCServices/`.

Ресурсы, включая скрипты, — в `Contents/Resources/` ([Bundle Programming Guide, Listing 2-3, Table 2-5](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html); [Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)).

Следствие для встроенного JRE и Graphviz: их бинарники и dylib кладутся в `Frameworks/` или `Helpers/`, не в `Resources/`. Это вывод, нотаризацией не проверен.

**PkgInfo не нужен.** Его нет ни в базовой структуре Apple, ни в таблице размещения. Это legacy-файл с type/creator-кодами (вторичный источник: [Eclectic Light](https://eclecticlight.co/2025/04/25/what-is-a-bundle-and-how-are-frameworks-different/)).

**Ключи Info.plist**
- Apple «Expected keys»: `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`, `CFBundleVersion`, `CFBundlePackageType` (`APPL`), `CFBundleSignature` (legacy), `CFBundleExecutable`.
- «Recommended»: `CFBundleDocumentTypes`, `CFBundleShortVersionString`, `LSMinimumSystemVersion`, `NSHumanReadableCopyright`, `NSPrincipalClass` ([BundleTypes, Tables 2-6/2-7](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html)).
- `CFBundleExecutable`: «You must include a valid CFBundleExecutable key» ([Core Foundation Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)).
- `CFBundleIconFile`: имя `.icns` в Resources. `CFBundleIconName` работает только с asset catalog, поэтому без actool остаётся `CFBundleIconFile` (там же).
- `NSPrincipalClass`: «Xcode sets the default value of this key to NSApplication for macOS apps» ([docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsprincipalclass)). Без Xcode ключ ставится вручную.
- `NSHighResolutionCapable` ([docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nshighresolutioncapable)): значение по умолчанию без ключа не подтверждено, поэтому ставить `true` явно.
- `LSMinimumSystemVersion` ([docs](https://developer.apple.com/documentation/bundleresources/information-property-list/lsminimumsystemversion)): с `@Observable` фактически нужно 14.0.

**Ассоциация .puml/.plantuml/.pu/.iuml/.wsd**
- **`CFBundleDocumentTypes`** ([docs](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes), archive Core Foundation Keys):
  - `CFBundleTypeRole`: `Editor|Viewer|Shell|QLGenerator|None`, в archive — «This key is required»;
  - `LSHandlerRank`: `Owner|Default|Alternate|None`, `Default` применяется, если ранг не задан;
  - `LSItemContentTypes` (UTI) главнее устаревших `CFBundleTypeExtensions`.
- **Exported или Imported** ([Defining file and data types for your app](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app)):
  - exported — если приложение «canonical source» формата;
  - imported — если тип объявлен другим приложением «or if it's a proprietary file format the system doesn't declare»;
  - префиксы `public`, `dyn`, `com.apple` использовать нельзя;
  - документный тип должен наследовать `public.data` и `public.content`;
  - для PlantUML подходит **`UTImportedTypeDeclarations`**.
- **Общепринятого UTI для PlantUML нет.**
  - Локальная проверка: `mdls` для `t.puml` → `dyn.ah62d4rv4ge81a7prru`, для остальных расширений тоже `dyn.*`; `lsregister -dump | grep -i puml` ничего не находит.
  - В проектах используются разные ID:
    - `com.plantuml.puml` — наследует `public.source-code` и `public.plain-text`, расширения puml/plantuml/iuml/pu, MIME `text/x-plantuml` ([hansemannn/quicklook-plantuml, project.yml#L33-L47](https://github.com/hansemannn/quicklook-plantuml/blob/main/project.yml#L33-L47));
    - `org.plantuml.source` — наследует `public.plain-text`, все 5 расширений, Role Viewer, Rank Alternate ([dlutcat build.py L57–L65](https://github.com/dlutcat/plantuml-quicklook/blob/main/scripts/build.py)).
  - UTI у EasyPlantUML не подтверждён.

**Иконка**
- `iconutil` — часть macOS, не CLT: `/usr/bin/iconutil` — настоящий бинарник, не xcrun-шим, `pkgutil` не относит его ни к какому пакету (локальная проверка).
- `.iconset` — это 10 PNG, от `icon_16x16.png` до `icon_512x512@2x.png`. Команда: `iconutil -c icns -o AppIcon.icns AppIcon.iconset` ([Apple, Optimizing for High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html)).
- Размеры можно нарезать системным `sips`.
- Liquid Glass `.icon` из Icon Composer собирает только Xcode ([docs](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)), без него остаётся `.icns`.

Минимальный Info.plist с ассоциацией типов:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PlantUMLEditor</string>
  <key>CFBundleIdentifier</key><string>io.github.OWNER.PlantUMLEditor</string>
  <key>CFBundleName</key><string>PlantUML Editor</string>
  <key>CFBundleDisplayName</key><string>PlantUML Editor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>   <!-- Contents/Resources/AppIcon.icns -->
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>PlantUML Source</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Default</string>
    <key>LSItemContentTypes</key>
    <array><string>com.plantuml.puml</string></array>
  </dict></array>
  <key>UTImportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>com.plantuml.puml</string>
    <key>UTTypeDescription</key><string>PlantUML Source</string>
    <key>UTTypeConformsTo</key>
    <array><string>public.plain-text</string><string>public.source-code</string></array>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key>
      <array><string>puml</string><string>plantuml</string><string>pu</string><string>iuml</string><string>wsd</string></array>
      <key>public.mime-type</key><array><string>text/x-plantuml</string></array>
    </dict>
  </dict></array>
</dict></plist>
```

Сборка (fish):

```fish
swift build -c release
set APP dist/PlantUMLEditor.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/PlantUMLEditor $APP/Contents/MacOS/
cp Support/Info.plist $APP/Contents/
iconutil -c icns -o $APP/Contents/Resources/AppIcon.icns Support/AppIcon.iconset
codesign --force --sign - $APP
codesign --verify --deep --strict $APP
```

### 4c. Подпись, Gatekeeper, нотаризация

**Ad-hoc подпись**
- `man codesign` (локально): «ad-hoc signing does not use an identity at all… Significant restrictions apply».
- Apple Silicon ([Big Sur 11.0.1 Universal Apps release notes, Code Signing](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)):
  - «any executable must be signed before it's allowed to run… a simple ad-hoc signature is sufficient»;
  - подпись, которую ставит линкер, «doesn't cover any resource other than the executable»;
  - «binaries signed this way cannot pass through Gatekeeper».
- Поэтому после сборки нужен `codesign --force --sign - X.app`: он запечатывает Info.plist и Resources.

**Gatekeeper для скачанного приложения (с quarantine), без нотаризации**
- Пользователь видит алерт «Apple cannot check … for malicious software» с кнопками Move to Trash и Done.
- Обход: System Settings → Privacy & Security → **Open Anyway** → Open, после этого приложение запоминается как исключение ([support.apple.com/102445](https://support.apple.com/en-us/102445)).
- **macOS Sequoia 15:** «users will no longer be able to Control-click to override Gatekeeper… They'll need to visit System Settings > Privacy & Security» ([Apple Developer News, 2024-08-06](https://developer.apple.com/news/?id=saqachfa)).

**Нотаризация**
- Нужны подпись **Developer ID** (не ad-hoc) и Hardened Runtime ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
- Сертификат Developer ID выпускает только Account Holder в Apple Developer Program ([developer-id](https://developer.apple.com/developer-id/)), членство стоит **$99 в год** ([programs](https://developer.apple.com/programs/)).
- С бесплатным аккаунтом нотаризация недоступна (вторичный источник: [Tauri docs](https://v2.tauri.app/distribute/sign/macos/)).
- Apple пишет, что `notarytool` и `stapler` «included with Xcode» ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)). **Локально оба есть и в CLT** (`/Library/Developer/CommandLineTools/usr/bin/notarytool`, `stapler`). Xcode для нотаризации не нужен, нужен только платный аккаунт.
- Застейплить можно .app или .dmg, ZIP — нельзя.

**Homebrew Cask**
- Официальный cask должен проходить Gatekeeper «and must not require … Gatekeeper to be disabled or bypassed» ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks); [Security and Supply Chain](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain#casks-have-a-different-trust-model)).
- Homebrew 5.0.0 (2025-11-12): «Casks without codesigning are deprecated… disable … casks that fail Gatekeeper checks in September 2026», флаг `--no-quarantine` объявлен устаревшим ([brew.sh](https://brew.sh/2025/11/12/homebrew-5.0.0)).
- Homebrew 6.0.0 (2026-06-11) подтверждает этот срок и вводит tap trust для сторонних tap ([brew.sh](https://brew.sh/2026/06/11/homebrew-6.0.0)).
- Итог: без нотаризации официального cask не будет. Останутся GitHub Releases или собственный tap, и Gatekeeper-диалог никуда не денется.

### 4d. Tauri v2 и Wails v2

- **Tauri v2:** «If you're only planning to develop desktop apps and not targeting iOS then you can install Xcode Command Line Tools instead». Полный Xcode нужен только для iOS, плюс требуется Rust ([prerequisites](https://v2.tauri.app/start/prerequisites/#macos)).
  - Размер: «a minimal Tauri app can be less than 600KB» за счёт системного webview ([v2.tauri.app/start](https://v2.tauri.app/start/#smaller-app-size)). Это заявление документации, а не замер .app.
  - Ad-hoc подпись: `"signingIdentity": "-"` ([docs](https://v2.tauri.app/distribute/sign/macos/#ad-hoc-signing)).
- **Wails v2:** «requires that the xcode command line tools are installed». Нужны Go 1.21+ (на macOS 15+ — 1.23.3+) и NPM/Node 15+ ([installation](https://wails.io/docs/gettingstarted/installation)).
  - «It does not embed a browser» ([introduction](https://wails.io/docs/introduction)).
  - Официального размера hello-world нет, **не подтверждено**.
- Итог: ни одному из двух не нужен полный Xcode для desktop. Перед SwiftPM на CLT у них нет выигрыша, а добавляются Rust или Go + Node, WebView и JS-стек.

## 5. Редактор кода и грамматики

| Вариант | Лицензия | macOS | Что умеет | Статус |
|---|---|---|---|---|
| NSTextView (TextKit 2) | системный | — | find bar (`usesFindBar`, `isIncrementalSearchingEnabled`), undo, ruler | стабильно |
| [STTextView](https://github.com/krzyzanowskim/STTextView) | **GPL-3.0** или [коммерческая](https://krzyzanowskim.gumroad.com/l/sttextview) | 14+ (`.macOS(.v14)`; README требует Xcode 26+) | номера строк, find/replace, completion, multi-cursor; подсветка через плагины TreeSitter/Neon | 2.4.1 от 2026-09-08, 1.6k★ |
| [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView) | MIT | 13+ | быстрый TextView; авторы: «suitable for replacing NSTextView in some, specific cases» | 184★ |
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) | MIT | 13+ | tree-sitter, completion, find/replace, minimap, inline-сообщения, парные скобки | «not ready for production use», 724★ |
| [Highlightr](https://github.com/raspu/Highlightr) | MIT (highlight.js — BSD-3) | 10.10+ | highlight.js через JavaScriptCore | «As of 2026… no longer actively maintained» |
| [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) | MIT | 11+ | highlight.js 11.11.1 | 111★ |
| [Neon](https://github.com/ChimeHQ/Neon) + [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter) | BSD-3-Clause | — | tree-sitter-подсветка для NSTextView/TextKit | main у Neon «not quite ready for release» |

**NSTextView с подсветкой регулярками**
- С macOS 12 NSTextView работает на TextKit 2. При явном обращении к `layoutManager` или на контенте вроде NSTextTable переходит в режим совместимости с NSLayoutManager ([NSTextView](https://developer.apple.com/documentation/appkit/nstextview)).
- `NSTextStorage` — «semi-concrete subclass of NSMutableAttributedString». Подсветку можно вешать на `NSTextStorageDelegate` или `processEditing()`. Обращаться к storage можно из любого потока, но одновременно только из одного ([NSTextStorage](https://developer.apple.com/documentation/appkit/nstextstorage)).
- В TextKit 2 у `NSTextLayoutManager` есть `addRenderingAttribute(_:value:for:)` и `renderingAttributesValidator`. Это атрибуты только для отрисовки: storage и undo они не трогают ([NSTextLayoutManager](https://developer.apple.com/documentation/appkit/nstextlayoutmanager)).
- Ограничение: «In a traditional NSTextStorage-backed system (TextKit 1 and 2), it can be challenging to achieve flicker-free on-keypress highlighting» ([Neon README](https://github.com/ChimeHQ/Neon#textkit-integration)).
- **Плюсы:** ноль зависимостей, собирается на CLT.
- **Минусы:** номера строк (`NSRulerView`), completion, парные скобки и маркер ошибки придётся писать самим.
- Оценка: для `.puml` в сотни строк полной перекраски с debounce хватит.

**Замечания по пакетам**
- **STTextView** под GPL-3.0: в MIT-приложении его можно использовать только с коммерческой лицензией.
- **CodeEditSourceEditor** берёт языки из CodeEditLanguages — это бинарный `CodeLanguagesContainer.xcframework` со всеми tree-sitter-грамматиками. Из 38 языков в таблице PlantUML нет ([CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages)).
- **highlight.js** PlantUML не поддерживает — его нет в [SUPPORTED_LANGUAGES.md](https://github.com/highlightjs/highlight.js/blob/main/SUPPORTED_LANGUAGES.md). Без собственной грамматики Highlightr и HighlighterSwift не помогут.

**Готовые грамматики PlantUML**
- **TextMate — [qjebbs/vscode-plantuml](https://github.com/qjebbs/vscode-plantuml)**, самая зрелая:
  - исходник `syntaxes/plantuml.yaml-tmLanguage`, в пакете — `syntaxes/plantuml.tmLanguage`, scopeName `source.wsd`;
  - лицензия **MIT** © 2016 jebbs (LICENSE.txt);
  - сниппеты `snippets/{general,activity,class,component,sequence,state,usecase,salt,eggs}.json` — **Apache-2.0** (`snippets/license.snippets.txt`);
  - расширения `.wsd .pu .puml .plantuml .iuml`, версия 2.18.1;
  - регулярки написаны под Oniguruma, для NSRegularExpression (ICU) их придётся переносить вручную (оценка).
- **tree-sitter** — все варианты незрелые:
  - [derivasoftware/tree-sitter-plantuml](https://github.com/derivasoftware/tree-sitter-plantuml): MIT, v0.10.0, коммиты с 2026-08-27 по 2026-09-29, 0★. Принцип «never ERROR»: неизвестные строки уходят в `raw_line`. На нём сделан SVG-рендерер [derivasoftware/plantuml-render](https://github.com/derivasoftware/plantuml-render) для подмножеств class, sequence и activity;
  - Decodetalkers/tree_sitter_plantuml: MIT, 12★, последний коммит 2023-09-01, есть пакет в [GNU Guix](https://packages.guix.gnu.org/packages/tree-sitter-plantuml/);
  - lyndsysimon/tree-sitter-plantuml: MIT, 7★, 2021, учебный;
  - Szeliga/tree-sitter-plantuml: только C4, лицензия не указана;
  - codeberg mhaase: черновик.
- **Vim:** [aklt/plantuml-syntax](https://github.com/aklt/plantuml-syntax), Vim license, 496★.
- **Sublime:** [PlantUmlDiagrams](https://packagecontrol.io/packages/PlantUmlDiagrams) — плагин рендера. Есть ли отдельный файл синтаксиса, не проверено.

**Словари из самого движка.** Флаги `plantuml -language` (legacy) и `--list-keywords` (новый CLI) дают одинаковый вывод. На [plantuml.com/command-line](https://plantuml.com/command-line): «legacy options will still be supported for a transition period, but they will no longer be documented».
- Локальная проверка на 1.2026.2: 918 строк. Секции: `;type` 53, `;keyword` 182, `;preprocessor` 35, `;skinparameter` 478, `;color` 154, `;EOF`.
- Из этого вывода удобно генерировать при сборке словари для подсветки и автодополнения под версию встроенного jar.
- `--list-keywords` в `-help` версии 1.2026.2 не упомянут, хотя работает.

## Открытые вопросы и неподтверждённое

**Рендер (раздел 2)**
- **Нативная сборка** `native-plantuml-macos-arm64-1.2026.8.zip`: не проверено, работают ли `-tsvg` и `-tpng`, есть ли внутри библиотеки AWT и сколько она весит после распаковки. Сборки под Intel нет.
- **picoweb:**
  - порт `:0` и `/stopserver` — выводы из кода, запуском не проверены;
  - безопасен ли параллельный рендер в одной JVM, документация не подтверждает.
- **Модули jlink.** Не проверено, хватает ли их для:
  - `!include https://…` (на старых JDK нужен `jdk.crypto.ec`);
  - локалей (`jdk.localedata`, например для Gantt);
  - `jdk.charsets`.
- **JS-сборка** (`@plantuml/core`). Не проверены:
  - паритет возможностей с Java-версией;
  - отличия вёрстки текста (шрифты WebView);
  - отсутствие локальных `!include` — пока это вывод из кода;
  - запуск в JavaScriptCore без WebView.
- **Картинка ошибки.** Убрать баннеры из CLI нельзя, это делается только через Java API `disableTimeBasedErrorDecorations()`.
- **Не исследовано:**
  - сколько памяти занимает JVM с `-pipe` и во что обходится схема «процесс на папку» — это покажут замеры;
  - показ SVG нативно через NSImage, без WKWebView;
  - привязка элементов SVG к строкам исходника (для перехода картинка → код).
- **Документация plantuml.com отстаёт от кода:**
  - picoweb: `POST /render` не описан;
  - graphviz-dot: старые пути к `dot`;
  - layout-engines: движком по умолчанию названа Puma;
  - command-line, блок «future beta»: порт 4242.

**Лицензии (раздел 3)**
- Какие лицензионные заголовки у Smetana и ditaa в текущем `plantuml-mit-*-sources.jar`. Проверен только снимок 2020 года.
- Работает ли ditaa в MIT-jar на деле. Классы в нём есть, рендер не проверен.
- **EPL-вариант:** под EPL-1.0 (POM и заголовки) или под EPL-2.0 (страница download). Версия BSD-лицензии в BSD-варианте не сверена.
- `js-plantuml-*.zip` в GitHub Releases: GPL- или MIT-сборка. У npm `@plantuml/core` лицензия MIT.
- **Лицензии прочих вложенных компонентов не проверены:** OpenIconic, Archi, tupadr3, ASCIIMathML, Brotli, CafeUndZopfli, puml-themes, остальные библиотеки stdlib, а также libltdl и прочие dylib Graphviz из Homebrew.
- **Противоречие внутри MIT-jar:** вывод `-license` пишет «This distribution bundles a minimal set of GraphViz files», а `mit-license.txt` называет сборку «IGY distribution (Install GraphViz by Yourself)».

**Сборка и распространение (раздел 4)**
- **Info.plist и иконка:**
  - значение `NSHighResolutionCapable`, если ключа нет;
  - как legacy `.icns` без `.icon` выглядит на macOS 26 и 27.
- **Сборка на одних CLT. Не проверено:**
  - universal binary через `swift build --arch arm64 --arch x86_64`; запасной путь — две сборки и `lipo`;
  - `.xcassets` с `--build-system swiftbuild`;
  - макросы Foundation (`#Predicate`, `#bundle`).
- **UTI:** что будет, если два приложения объявят для `.puml` разные UTI (`com.plantuml.puml` и `org.plantuml.source`).
- **Gatekeeper:** точный текст диалога для приложения с ad-hoc подписью, в сравнении с «is damaged».
- **Homebrew:** отключили ли на деле в сентябре 2026 casks без нотаризации. В заметках к Homebrew 7.0.0 об этом ничего нет.
- **Размер hello-world:** у Wails официальной цифры нет, «<600KB» у Tauri — заявление документации, а не замер.
- **Встроенный JRE:** куда класть — в Frameworks или Helpers, чтобы пройти нотаризацию.

**Конкуренты (раздел 1) и редактор (раздел 5)**
- **EasyPlantUML** — не подтверждены:
  - механизм рендера (встроенный JRE?);
  - Graphviz или Smetana;
  - UTI;
  - наличие сниппетов, поиска, тем, `!include`, вкладок.
- **VUML:** не подтверждено, какие конструкции PlantUML он понимает и совпадает ли его раскладка с plantuml.jar.
- **DiagramLab:** способ рендера PlantUML не указан.
- **Pladitor:** фреймворк оболочки не подтверждён.
- **`--list-keywords`:** флаг работает, но не упомянут в `-help` версии 1.2026.2. Проверить в 1.2026.8.
- **vscode-plantuml:** какая доля паттернов переносится из Oniguruma в ICU (`NSRegularExpression`).
- **Только CLT:** соберётся ли STTextView (требует «Xcode 26.0+») и можно ли добавить грамматику в CodeEditLanguages (xcframework).
