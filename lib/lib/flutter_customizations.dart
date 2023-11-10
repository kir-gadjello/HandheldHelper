import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class ExtendedThemeData extends ThemeExtension<ExtendedThemeData> {
  const ExtendedThemeData(
      {required this.warning,
      required this.info,
      required this.codeBackgroundColor,
      required this.codeTextColor,
      required this.chatMsgWarningFontSize});

  final Color? warning;
  final Color? info;
  final double? chatMsgWarningFontSize;
  final Color? codeBackgroundColor;
  final Color? codeTextColor;

  @override
  ExtendedThemeData copyWith(
      {Color? warning,
      Color? info,
      double? chatMsgWarningFontSize,
      Color? codeBackgroundColor,
      Color? codeTextColor}) {
    return ExtendedThemeData(
        warning: warning ?? this.warning,
        codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
        codeTextColor: codeTextColor ?? this.codeTextColor,
        info: info ?? this.info,
        chatMsgWarningFontSize:
            chatMsgWarningFontSize ?? this.chatMsgWarningFontSize);
  }

  @override
  ExtendedThemeData lerp(ExtendedThemeData? other, double t) {
    if (other is! ExtendedThemeData) {
      return this;
    }
    return ExtendedThemeData(
      warning: Color.lerp(warning, other.warning, t),
      codeBackgroundColor:
          Color.lerp(codeBackgroundColor, other.codeBackgroundColor, t),
      codeTextColor: Color.lerp(codeTextColor, other.codeTextColor, t),
      info: Color.lerp(info, other.info, t),
      chatMsgWarningFontSize: chatMsgWarningFontSize,
    );
  }

  // Optional
  @override
  String toString() => 'ExtendedThemeData(...)';
}
