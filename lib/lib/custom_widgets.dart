import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
// import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_prism/flutter_prism.dart';
import 'package:handheld_helper/flutter_customizations.dart';
import 'package:markdown_viewer/markdown_viewer.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter/material.dart' show Icon, Icons;

final USE_MARKDOWN = true;

Set<int> prismErrorHashes = Set<int>();

class CodeSpanBuilder extends MarkdownElementBuilder {
  CodeSpanBuilder({
    super.context,
    TextStyle? textStyle,
  }) : _textStyle = textStyle;

  @override
  final matchTypes = ['codeSpan'];

  double? _lineHeight;
  final TextStyle? _textStyle;

  @override
  TextStyle? buildTextStyle(element, defaultStyle) {
    Color color;
    Color backgroundColor;

    if (darkMode) {
      color = const Color(0Xffca4219);
      backgroundColor = const Color(0Xff424242);
    } else {
      color = const Color(0xff8b1c1c);
      backgroundColor = const Color(0x10000000);
    }

    final style = super
        .buildTextStyle(element, defaultStyle)
        ?.merge(_textStyle)
        ?.merge(TextStyle(
          color: color,
          fontFamily: 'JetBrainsMono',
          backgroundColor: backgroundColor,
        ).merge(_textStyle));

    _lineHeight = style?.height;

    return style?.copyWith(height: _lineHeight);
  }

  @override
  Widget? buildWidget(element, parent) {
    final richText = element.children.single as RichText;
    // The purpose of this is to make the RichText has the same line height as
    // it should be while the line height of TextSpan has been changed to 1.
    return renderer.createRichText(
      richText.text as TextSpan,
      strutStyle: StrutStyle(
          leading: 15.0, height: _lineHeight, forceStrutHeight: false),
    );
  }
}

Widget MdViewer(
    String data,
    BuildContext context,
    bool isOwnMessage,
    MessageOptions messageOptions,
    Color? customBackgroundColor,
    Color? customTextColor) {
  var extThemeData = Theme.of(context).extension<ExtendedThemeData>()!;
  var codeBackgroundColor = extThemeData.codeBackgroundColor;
  var activeColor = Theme.of(context).primaryColor;

  var bgColor = isOwnMessage
      ? messageOptions.currentUserContainerColor(context)
      : messageOptions.containerColor;
  var textColor = isOwnMessage
      ? messageOptions.currentUserTextColor(context)
      : messageOptions.textColor;

  if (customBackgroundColor != null) {
    bgColor = customBackgroundColor!;
  }

  if (customTextColor != null) {
    textColor = customTextColor;
  }

  var codeTextColor = extThemeData.codeTextColor!;
  var codeBgColor = extThemeData.codeBackgroundColor!;

  final codeSpanStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 14,
    height: 1.5,
    color: codeTextColor,
    backgroundColor: codeBgColor,
    decoration: TextDecoration.none,
    fontWeight: FontWeight.w300,
  );

  const codeBlockStyle = TextStyle(
      fontSize: 14,
      height: 1.5,
      fontFamily: 'JetBrainsMono',
      backgroundColor: Colors.transparent);

  return MarkdownViewer(
    data,
    enableTaskList: true,
    enableSuperscript: false,
    enableSubscript: false,
    enableFootnote: false,
    enableImageSize: false,
    enableKbd: false,
    // syntaxExtensions: [ExampleSyntax()],
    highlightBuilder: (text, language, infoString) {
      final lang = language ?? 'plain';
      final prism = Prism(
        mouseCursor: SystemMouseCursors.text,
        style: PrismStyle.dark(),
        // style: Theme.of(context).scaffoldBackgroundColor == Colors.black
        //     ? const PrismStyle.dark()
        //     : const PrismStyle(),
      );

      // If the set is non-empty, check if the text's hash is in it
      if (prismErrorHashes.isNotEmpty) {
        int textHash = text.hashCode;
        if (prismErrorHashes.contains(textHash)) {
          return [
            TextSpan(
                text: text,
                style: TextStyle(
                    color: bgColor, backgroundColor: Colors.transparent))
          ];
        }
      }

      try {
        return prism.render(text, lang);
      } catch (e) {
        int textHash = text.hashCode;
        // If Prism throws an exception, add the text's hash to the set
        prismErrorHashes.add(textHash);
        print(
            "MARKDOWN ERROR: PRISM FAILED TO RENDER FOR language=${lang} hash=$textHash text_len=${text.length} text=\"${text.substring(0, min(128, text.length))}\"");
      }

      return [
        TextSpan(
            text: text,
            style:
                TextStyle(color: bgColor, backgroundColor: Colors.transparent))
      ];

      try {
        return prism.render(text, lang);
      } catch (e) {
        print("MARKDOWN ERROR: PRISMx FAILED TO RENDER FOR language=${lang}");
      }
      return [
        TextSpan(text: text, style: TextStyle(backgroundColor: Colors.blueGrey))
      ];
    },
    onTapLink: (href, title) {
      print({href, title});
    },
    elementBuilders: [
      CodeSpanBuilder(textStyle: codeSpanStyle),
    ],
    selectable: true,
    selectionColor: activeColor,
    styleSheet: MarkdownStyle(
        textStyle:
            TextStyle(color: textColor, height: 1.4, backgroundColor: bgColor),
        listItemMarkerTrailingSpace: 12,
        codeSpan: codeSpanStyle,
        codeBlock: codeBlockStyle),
  );
}

/// {@category Default widgets}
class RichMessageText extends StatelessWidget {
  const RichMessageText({
    required this.message,
    required this.isOwnMessage,
    this.messageOptions = const MessageOptions(),
    Key? key,
  }) : super(key: key);

  /// Message tha contains the text to show
  final ChatMessage message;

  /// If the message is from the current user
  final bool isOwnMessage;

  /// Options to customize the behaviour and design of the messages
  final MessageOptions messageOptions;

  @override
  Widget build(BuildContext context) {
    var bgColor = Theme.of(context).listTileTheme.tileColor;
    if (message.customBackgroundColor != null) {
      bgColor = message.customBackgroundColor!;
    }
    var extThemeData = Theme.of(context).extension<ExtendedThemeData>()!;

    var _interrupted = false;
    var _canceled_by_user = false;

    if (message.customProperties != null) {
      _interrupted = message.customProperties!.containsKey("_interrupted");
      _canceled_by_user =
          message.customProperties!.containsKey("_canceled_by_user");
    }
    return Column(
      crossAxisAlignment:
          isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          children: USE_MARKDOWN
              ? [
                  MdViewer(message.text, context, isOwnMessage, messageOptions,
                      message.customBackgroundColor, message.customTextColor)
                ]
              : getMessage(context),
        ),
        if (messageOptions.showTime)
          messageOptions.messageTimeBuilder != null
              ? messageOptions.messageTimeBuilder!(message, isOwnMessage)
              : Padding(
                  padding: messageOptions.timePadding,
                  child: Text(
                    (messageOptions.timeFormat ?? intl.DateFormat('HH:mm'))
                        .format(message.createdAt),
                    style: TextStyle(
                      color: isOwnMessage
                          ? messageOptions.currentUserTimeTextColor(context)
                          : messageOptions.timeTextColor(),
                      fontSize: messageOptions.timeFontSize,
                    ),
                  ),
                ),
        if (_interrupted && !_canceled_by_user)
          Padding(
              padding: const EdgeInsets.fromLTRB(4.0, 5.0, 0, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(Icons.warning_amber_sharp,
                    color: extThemeData.warning,
                    size: extThemeData.chatMsgWarningFontSize! + 2),
                const SizedBox(width: 2.0),
                Text("AI answer was interrupted for this message",
                    style: TextStyle(
                        color: extThemeData.warning,
                        fontSize: extThemeData.chatMsgWarningFontSize))
              ])),
        if (_canceled_by_user)
          Padding(
              padding: const EdgeInsets.fromLTRB(4.0, 5.0, 0, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(Icons.warning_amber_sharp,
                    color: extThemeData.info,
                    size: extThemeData.chatMsgWarningFontSize! + 2),
                const SizedBox(width: 2.0),
                Text("You canceled generation of this message",
                    style: TextStyle(
                        color: extThemeData.info,
                        fontSize: extThemeData.chatMsgWarningFontSize))
              ]))
      ],
    );
  }

  List<Widget> getMessage(BuildContext context) {
    if (message.mentions != null && message.mentions!.isNotEmpty) {
      String stringRegex = r'([\s\S]*)';
      String stringMentionRegex = '';
      for (final Mention mention in message.mentions!) {
        stringRegex += '(${mention.title})' r'([\s\S]*)';
        stringMentionRegex += stringMentionRegex.isEmpty
            ? '(${mention.title})'
            : '|(${mention.title})';
      }
      final RegExp mentionRegex = RegExp(stringMentionRegex);
      final RegExp regexp = RegExp(stringRegex);

      RegExpMatch? match = regexp.firstMatch(message.text);
      if (match != null) {
        List<Widget> res = <Widget>[];
        match
            .groups(List<int>.generate(match.groupCount, (int i) => i + 1))
            .forEach((String? part) {
          if (mentionRegex.hasMatch(part!)) {
            Mention mention = message.mentions!.firstWhere(
              (Mention m) => m.title == part,
            );
            res.add(getMention(context, mention));
          } else {
            res.add(getParsePattern(context, part));
          }
        });
        if (res.isNotEmpty) {
          return res;
        }
      }
    }
    return <Widget>[getParsePattern(context, message.text)];
  }

  Widget getParsePattern(BuildContext context, String text) {
    return ParsedText(
      parse: messageOptions.parsePatterns != null
          ? messageOptions.parsePatterns!
          : defaultParsePatterns,
      text: text,
      style: TextStyle(
        color: isOwnMessage
            ? messageOptions.currentUserTextColor(context)
            : messageOptions.textColor,
      ),
    );
  }

  Widget getMention(BuildContext context, Mention mention) {
    return RichText(
      text: TextSpan(
        text: mention.title,
        recognizer: TapGestureRecognizer()
          ..onTap = () => messageOptions.onPressMention != null
              ? messageOptions.onPressMention!(mention)
              : null,
        style: TextStyle(
          color: isOwnMessage
              ? messageOptions.currentUserTextColor(context)
              : messageOptions.textColor,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Widget customMessageTextBuilder(ChatMessage msg, ChatMessage? prev,
    ChatMessage? next, bool? isOwnMessage, MessageOptions? messageOptions) {
  return RichMessageText(
      message: msg,
      isOwnMessage: isOwnMessage!,
      messageOptions: messageOptions!);
}
