# Native spell checking on Android and iOS

Flutter Quill uses the spelling and correction facilities of the Android and
iOS text input systems. Spell checking is enabled by default for editable
`QuillEditor` instances and can be controlled with
`QuillEditorConfig.spellCheckConfiguration`.

## Usage

No platform plugin, permission, API key or remote service is required:

```dart
QuillEditor.basic(
  controller: controller,
  config: const QuillEditorConfig(
    spellCheckConfiguration: SpellCheckConfiguration(
      misspelledTextStyle: TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: Colors.red,
        decorationStyle: TextDecorationStyle.wavy,
      ),
    ),
  ),
);
```

Use the disabled configuration for fields where checking and automatic
corrections are undesirable, such as identifiers or source code:

```dart
const QuillEditorConfig(
  spellCheckConfiguration: SpellCheckConfiguration.disabled(),
)
```

The editor uses the dictionaries and language selected in the user's system
keyboard settings. Consequently, the exact presentation (suggestion strip,
replacement UI, or marked misspellings) and the availability of a language
depend on the installed keyboard, OS version, and user settings. A read-only
editor never requests corrections. Misspelled words are drawn using
`misspelledTextStyle` (a red wavy underline by default).

Tap or long-press an underlined word to put the selection/caret inside it and
open the standard selection menu. Native replacement candidates appear before
the normal cut/copy/paste actions. Choosing one replaces exactly the range
reported by the system checker, updates the Quill document and moves the caret
to the end of the replacement.

## Architecture

The feature deliberately stays in the existing Flutter text-input path:

1. `QuillEditorConfig` exposes Flutter's `SpellCheckConfiguration`, including
   the decoration and an optional custom `SpellCheckService`.
2. `QuillEditor` forwards it to `QuillRawEditorConfig`, keeping the high-level
   and raw editor APIs consistent.
3. When `QuillRawEditorState` attaches its `TextInputClient`, it maps the state
   to `TextInputConfiguration.autocorrect` and
   `TextInputConfiguration.enableSuggestions`.
4. After edits settle, `DefaultSpellCheckService` asks the Android/iOS native
   spell-check channel for `SuggestionSpan` ranges and replacement candidates.
5. The rich-text span builder intersects those document ranges with Quill leaf
   nodes. It adds `misspelledTextStyle` without discarding bold, links, or other
   Quill formatting.
6. The context menu finds the result at the caret, prepends each candidate as a
   button, and applies the chosen value through `QuillController.replaceText`.

### Exact platform call chain

Flutter Quill does not call Java/Kotlin or Objective-C APIs directly. It uses
Flutter's public `DefaultSpellCheckService`, so the call follows the platform
implementation shipped with the application's Flutter engine:

```text
QuillRawEditorState
  -> DefaultSpellCheckService.fetchSpellCheckSuggestions(locale, text)
  -> SystemChannels.spellCheck
  -> "SpellCheck.initiateSpellCheck"([languageTag, text])
  -> Flutter engine platform spell-check plugin
  -> Android TextServicesManager / iOS UITextChecker
  <- [{startIndex, endIndex, suggestions}, ...]
  <- List<SuggestionSpan>
```

On **Android**, Flutter's engine obtains `TextServicesManager`, opens a
`SpellCheckerSession` for the requested locale, and calls
`getSentenceSuggestions`. Android invokes the session listener asynchronously.
Flutter converts every `SentenceSuggestionsInfo` entry into a half-open text
range (`startIndex`, `endIndex`) and up to five replacement strings. The
dictionary/provider is therefore the spell checker selected by the user in
Android settings; it is not bundled with Flutter Quill.

On **iOS**, Flutter's engine lazily creates `UITextChecker`. It validates the
requested locale against `UITextChecker.availableLanguages`, repeatedly calls
`rangeOfMisspelledWordInString` to locate errors, and obtains replacements with
`guessesForWordRange`. These ranges and strings are returned over the same
Flutter spell-check channel.

`DefaultSpellCheckService` converts the platform dictionaries into Flutter
`SuggestionSpan` objects. Flutter Quill consumes only that public Dart model,
which keeps all document-range mapping, decoration, menu construction, and
replacement logic identical on both platforms. No Android/iOS project files,
permissions, or plugin registration are required in the consuming app.

This design has no package-specific platform channel or dictionary implementation.
Flutter Quill does not upload document contents, select a dictionary, or render
a separate suggestion UI. It also means application code should not assume a
particular set of suggestions: those belong to the native checker. The visual
decoration remains fully configurable by the application.

## Platform setup and limitations

- **Android:** enable spell checking and suggestions for the active keyboard in
  system settings. Device vendors and third-party IMEs may behave differently.
- **iOS:** enable **Auto-Correction** and **Check Spelling** under the keyboard
  settings and install the required keyboard language.
- Simulators/emulators may not have the same dictionaries or keyboard settings
  as a physical device, so verify the intended languages on real hardware.
- Configuration changes trigger a new check. Requests are debounced while the
  user types and stale asynchronous results are discarded.

The current results are available from
`QuillRawEditorState.spellCheckResults` for applications that provide a custom
context menu. A custom dictionary or remote checker can be integrated by
supplying an implementation of `SpellCheckService`; document rendering and
replacement behavior remain unchanged.
