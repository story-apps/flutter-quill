import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/src/l10n/extensions/localizations_ext.dart';
import 'package:flutter_quill_test/flutter_quill_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QuillController controller;
  var didCopy = false;

  setUp(() {
    controller = QuillController.basic();
  });

  tearDown(() {
    controller.dispose();
  });

  group('QuillEditor', () {
    test('native spell checking is enabled by default and copied', () {
      const config = QuillEditorConfig();

      expect(config.spellCheckConfiguration.spellCheckEnabled, isTrue);
      expect(
        config
            .copyWith(
              spellCheckConfiguration:
                  const SpellCheckConfiguration.disabled(),
            )
            .spellCheckConfiguration
            .spellCheckEnabled,
        isFalse,
      );
    });

    testWidgets('forwards spell checking to the raw editor', (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor.basic(
            controller: controller,
            config: const QuillEditorConfig(
              spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            ),
          ),
        ),
      );

      final rawEditor = tester.widget<QuillRawEditor>(
        find.byType(QuillRawEditor),
      );
      expect(
        rawEditor.config.spellCheckConfiguration.spellCheckEnabled,
        isFalse,
      );
    });

    testWidgets('decorates misspellings and exposes native replacements', (
      tester,
    ) async {
      final editorKey = GlobalKey<QuillRawEditorState>();
      controller.document = Document()..insert(0, 'wrold');
      controller.updateSelection(
        const TextSelection.collapsed(offset: 2),
        ChangeSource.local,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          home: QuillEditor.basic(
            controller: controller,
            config: QuillEditorConfig(
              editorKey: editorKey,
              spellCheckConfiguration: SpellCheckConfiguration(
                spellCheckService: _FakeSpellCheckService(),
                misspelledTextStyle: const TextStyle(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.wavy,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(editorKey.currentState!.spellCheckResults, isNotNull);
      expect(
        tester.widgetList<RichText>(find.byType(RichText)).any(
          (richText) => _hasWavyUnderline(richText.text),
        ),
        isTrue,
      );
      final replacement = editorKey.currentState!.contextMenuButtonItems
          .singleWhere((item) => item.label == 'world');
      replacement.onPressed();

      expect(controller.document.toPlainText(), 'world\n');
    });

    testWidgets('Keyboard entered text is stored in document', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor.basic(
            controller: controller,
            config: const QuillEditorConfig(),
          ),
        ),
      );
      await tester.quillEnterText(find.byType(QuillEditor), 'test\n');

      expect(controller.document.toPlainText(), 'test\n');
    });

    testWidgets('insertContent is handled correctly', (tester) async {
      String? latestUri;
      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor(
            focusNode: FocusNode(),
            scrollController: ScrollController(),
            controller: controller,
            config: QuillEditorConfig(
              autoFocus: true,
              expands: true,
              contentInsertionConfiguration: ContentInsertionConfiguration(
                onContentInserted: (content) {
                  latestUri = content.uri;
                },
                allowedMimeTypes: <String>['image/gif'],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(QuillEditor));
      await tester.quillEnterText(find.byType(QuillEditor), 'test\n');
      await tester.idle();

      const uri =
          'content://com.google.android.inputmethod.latin.fileprovider/test.gif';
      final messageBytes = const JSONMessageCodec().encodeMessage(<
        String,
        dynamic
      >{
        'args': <dynamic>[
          -1,
          'TextInputAction.commitContent',
          jsonDecode(
            '{"mimeType": "image/gif", "data": [0,1,0,1,0,1,0,0,0], "uri": "$uri"}',
          ),
        ],
        'method': 'TextInputClient.performAction',
      });

      Object? error;
      try {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/textinput',
          messageBytes,
          (_) {},
        );
      } catch (e) {
        error = e;
      }
      expect(error, isNull);
      expect(latestUri, equals(uri));
    });

    Widget customBuilder(BuildContext context, QuillRawEditorState state) {
      return AdaptiveTextSelectionToolbar(
        anchors: state.contextMenuAnchors,
        children: [
          Container(
            height: 50,
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  onPressed: () {
                    didCopy = true;
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
        ],
      );
    }

    testWidgets('custom context menu builder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor(
            focusNode: FocusNode(),
            scrollController: ScrollController(),
            controller: controller,
            config: QuillEditorConfig(
              autoFocus: true,
              expands: true,
              contextMenuBuilder: customBuilder,
            ),
          ),
        ),
      );

      // Long press to show menu
      await tester.longPress(find.byType(QuillEditor));
      await tester.pumpAndSettle();

      // Verify custom widget shows
      expect(find.byIcon(Icons.copy), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      expect(didCopy, isTrue);
    });

    testWidgets(
      'QuillEditorOpenSearchAction should not throw an exception when the required localization delegates are provided',
      (tester) async {
        final editorFocusNode = FocusNode();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            home: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(),
              focusNode: editorFocusNode,
            ),
          ),
        );
        // Required, otherwise the action shortcuts won't be invoked.
        editorFocusNode.requestFocus();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

        await tester.pump();

        final exception = tester.takeException();
        expect(
          exception,
          isNot(isInstanceOf<MissingFlutterQuillLocalizationException>()),
        );

        expect(exception, isNull);
      },
    );

    testWidgets(
      'should throw MissingFlutterQuillLocalizationException if the delegate not provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(builder: (context) => Text(context.loc.font)),
          ),
        );

        final exception = tester.takeException();

        expect(exception, isNotNull);
        expect(exception, isA<MissingFlutterQuillLocalizationException>());
      },
    );

    testWidgets(
      'should not throw MissingFlutterQuillLocalizationException if the delegate is provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            home: Builder(builder: (context) => Text(context.loc.font)),
          ),
        );

        final exception = tester.takeException();

        expect(exception, isNull);
        expect(
          exception,
          isNot(isA<MissingFlutterQuillLocalizationException>()),
        );
      },
    );

    testWidgets(
      'should throw MissingFlutterQuillLocalizationException if the delegate is not provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(builder: (context) => Text(context.loc.font)),
          ),
        );

        final exception = tester.takeException();

        expect(exception, isNotNull);
        expect(exception, isA<MissingFlutterQuillLocalizationException>());
      },
    );
  });
}

class _FakeSpellCheckService implements SpellCheckService {
  @override
  Future<List<SuggestionSpan>> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => const [
    SuggestionSpan(TextRange(start: 0, end: 5), ['world']),
  ];
}

bool _hasWavyUnderline(InlineSpan span) {
  if (span.style?.decorationStyle == TextDecorationStyle.wavy) return true;
  var found = false;
  span.visitChildren((child) {
    found = found || _hasWavyUnderline(child);
    return !found;
  });
  return found;
}
