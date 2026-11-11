# HomeRoll – Appearance & Localization Instructions

Working notes for the appearance (Automatic / Light / Dark) feature and for adding localized strings.
Code comments in this project are in German; UI strings are German-keyed with English translations.

## Goal

The whole UI follows **Automatic** (the iPhone's Light or Dark setting) by default. The user can switch to
**Light** or **Dark** permanently in the app's **Settings** page, which is opened from the library menu
(the menu next to "Select" in the Library header).

## Where things live

| Piece | File |
|---|---|
| Theme enum (`auto` / `light` / `dark`), saved in `UserDefaults` (`app.theme`), default `.auto` | `App/Core/Theme.swift` |
| Applies the theme to every window (`overrideUserInterfaceStyle`) and to SwiftUI (`preferredColorScheme`) | `App/Core/Theme.swift` (`ThemeApplier`, `.appTheme(_:)`) |
| Adaptive colors (`appBackground`, `appFill`, `appFill2`, `appFill3`, `loginTop`) – use these instead of fixed `Color.black` / `Color(white:)` | `App/Core/Theme.swift` |
| Settings page (Automatic / Light / Dark, shows "Currently: Light/Dark" under Automatic) | `App/Core/SettingsView.swift` |
| Library menu entry "Einstellungen" (gear icon, between Filters and Refresh) sets `app.showSettings = true` | `App/Library/LibraryView.swift` (`libraryMenu`) |
| Settings sheet presented | `App/RootView.swift` (`.sheet(isPresented: $app.showSettings)`) |
| Theme set at the app root and written to the App Group on change | `App/FotosApp.swift` (`.appTheme(app.theme)`, `AppGroup.saveTheme`) |
| Theme shared with the Share extension | `Shared/AppGroup.swift` (`saveTheme` / `loadTheme`, file `erscheinungsbild.txt`) |

## Share extension

`Share/ShareViewController.swift` reads the saved theme in `viewDidLoad()` and sets
`overrideUserInterfaceStyle` (`"light"` → light, `"dark"` → dark, anything else → follow the system). So the
extension shows the same appearance as the app. Automatic follows the iPhone.

## Widget

Widgets always follow the system appearance. iOS does not let a widget take an in-app Light/Dark choice, so
there is nothing to wire up (noted in `AppGroup.swift`). The empty-state background in `Widget/FotosWidget.swift`
uses `Color(.secondarySystemBackground)` (was a fixed near-black `Color(white: 0.12)`, which made the
"open the app" text hard to read in light mode).

## Rules when writing UI code

- Do not force a color scheme in views, the Share extension or the widget. No `preferredColorScheme(.dark)` and no
  `overrideUserInterfaceStyle = .dark`, except the Share extension line that reads the saved theme.
- Use the adaptive colors from `Theme.swift` or system colors (`.primary`, `.secondary`, `Color(.systemBackground)`,
  …). Avoid fixed `Color.black`, `Color.white` and `Color(white:)` for backgrounds and text.
- White text on top of photos (gradient overlays, video durations, badges) is fine because it sits on image content.
- **New settings and future options go into the Settings page (`SettingsView.swift`), not into the library menu.**
  The library menu (next to "Select") stays for sorting, view options, filters, Settings, Refresh and Sign Out only.
  Add a new `Section` in `SettingsView` for each new setting or group of settings.

## Localization

- Format: **String Catalogs** (`.xcstrings`), one set per target:
  - App: `Resources/Localizable.xcstrings`, plus `AppShortcuts`, `InfoPlist`, `Theme`
  - Share extension: `Share/Localizable.xcstrings`, `Share/InfoPlist.xcstrings`
  - Widget: `Widget/Localizable.xcstrings`, `Widget/InfoPlist.xcstrings`
- Source language is German (`"sourceLanguage" : "de"`). **The German text is the key**, e.g. `"Abbrechen"`.
  There are no symbolic keys.
- Every new string gets an explicit English translation:

  ```json
  "Abbrechen" : {
    "localizations" : {
      "en" : {
        "stringUnit" : {
          "state" : "translated",
          "value" : "Cancel"
        }
      }
    }
  }
  ```

- In code use `String(localized: "…")`. For strings in the Theme table use `String(localized: "…", table: "Theme")`.
- Format specifiers stay as they are: `String(localized: "\(n) gesichert")` has the key `%lld gesichert`.
  Singular cases get their own key (e.g. `"1 Objekt auf deinen Server sichern"`).
- Use typographic quotes in English values (“2 Years Ago Today”) and German quotes in German keys („…“).
- Put each string in the catalog of the target that uses it. Catalogs are separate per target, so a string in the
  app catalog is not available in the Share extension or the widget.
- Strings that appear only at runtime (raw enum values) go through `L("…")` in `Shared/AppGroup.swift`.

Current Theme strings (all translated): Automatisch, Hell, Dunkel, Gerade: Dunkel, Gerade: Hell, Erscheinungsbild,
the "Automatisch folgt …" footer text, Einstellungen, Fertig.

## Changes made

1. `Share/ShareViewController.swift`: applies the saved app theme (see above).
2. `Widget/FotosWidget.swift`: empty-state background now adapts to light and dark.
3. `App/Core/SettingsView.swift`: "Currently: Light/Dark" reads the iPhone's real system setting (screen traits), not the
   sheet's own color scheme, which could be stale after picking Dark once.
4. `App/Core/Theme.swift`: `ThemeApplier` also resets the root view controller and open sheets, so an old Dark override
   does not stay stuck after switching back to Automatic.
5. `App/Collections/CollectionDetail.swift`: build fix (Swift 6 data-race error in `PersonMenu.link`): the fields are
   `[String: String]` and copied to a `let` before the `Task`.

Known gap: some collection screens (`AssetGridScreen`, `CardGridScreen`, `PeopleScreen` in `CollectionDetail.swift`)
still use fixed `Color.black` backgrounds and white text, and `FaceReviewSheet` forces `.preferredColorScheme(.dark)`.
They do not follow light mode yet.

The Settings page and the library-menu entry were already in the source. A build installed on the phone that lacks
the "Settings" entry in the library menu is older than the source; rebuild and reinstall
(`xcodegen generate`, then run in Xcode, or `./build-ipa.sh`).

## To check after rebuilding

- Settings → Appearance: switch Automatic / Light / Dark, the whole app changes at once, including sheets and menus.
- Automatic follows the iPhone when you change Light/Dark in Control Center.
- Share extension (share a photo from another app) matches the app's choice.
- Widget empty state is readable in both light and dark.
