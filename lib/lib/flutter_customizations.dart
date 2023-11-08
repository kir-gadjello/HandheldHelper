import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class ExtendedThemeData extends ThemeExtension<ExtendedThemeData> {
  const ExtendedThemeData(
      {required this.warning,
      required this.info,
      required this.chatMsgWarningFontSize});

  final Color? warning;
  final Color? info;
  final double? chatMsgWarningFontSize;

  @override
  ExtendedThemeData copyWith(
      {Color? warning, Color? info, double? chatMsgWarningFontSize}) {
    return ExtendedThemeData(
        warning: warning ?? this.warning,
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
      info: Color.lerp(info, other.info, t),
      chatMsgWarningFontSize: chatMsgWarningFontSize,
    );
  }

  // Optional
  @override
  String toString() => 'ExtendedThemeData(...)';
}
