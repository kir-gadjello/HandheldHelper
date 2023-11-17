part of dash_chat_2;

/// @nodoc
class InputToolbar extends StatefulWidget {
  const InputToolbar({
    required this.currentUser,
    required this.onSend,
    this.inputOptions = const InputOptions(),
    Key? key,
  }) : super(key: key);

  /// Options to custom the toolbar
  final InputOptions inputOptions;

  /// Function to call when the message is sent (click on the send button)
  final Function(ChatMessage) onSend;

  /// Current user using the chat
  final ChatUser currentUser;

  @override
  State<InputToolbar> createState() => InputToolbarState();
}

class InputToolbarState extends State<InputToolbar>
    with WidgetsBindingObserver {
  late TextEditingController textController;
  OverlayEntry? _overlayEntry;
  int currentMentionIndex = -1;
  String currentTrigger = '';
  late FocusNode focusNode;
  bool _shiftPressed = false;

  @override
  void initState() {
    textController =
        widget.inputOptions.textController ?? TextEditingController();
    focusNode = widget.inputOptions.focusNode ?? FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        _clearOverlay();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS || Platform.isLinux) {
      ServicesBinding.instance.keyboard.addHandler(_onKey);
    }
    super.initState();
  }

  @override
  void didChangeMetrics() {
    final double bottomInset = View.of(context).viewInsets.bottom;
    final bool isKeyboardActive = bottomInset > 0.0;
    if (!isKeyboardActive) {
      _clearOverlay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearOverlay();
    if (Platform.isMacOS || Platform.isLinux) {
      ServicesBinding.instance.keyboard.removeHandler(_onKey);
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey.keyLabel;

    if (event is KeyDownEvent) {
      // print("Key down: $key");
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {
        _shiftPressed = true;
      }
    } else if (event is KeyUpEvent) {
      // print("Key up: $key");
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {
        _shiftPressed = false;
      }
      if (_shiftPressed && event.logicalKey == LogicalKeyboardKey.enter) {
        // print("!!! SHIFT+ENTER");
        if (widget.inputOptions.sendOnShiftEnter) {
          _sendMessage(removeLastNewline: true);
          return false;
        } else if (widget.inputOptions.newlineOnShiftEnter) {
          setState(() {
            textController.text += '\n';
          });
          return false;
        }
      }
    } else if (event is KeyRepeatEvent) {
      // print("Key repeat: $key");
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {
        _shiftPressed = true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback onEscDetected;

    return SafeArea(
      top: false,
      child: Container(
        padding: widget.inputOptions.inputToolbarPadding,
        margin: widget.inputOptions.inputToolbarMargin,
        decoration: widget.inputOptions.inputToolbarStyle,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (widget.inputOptions.leading != null)
              ...widget.inputOptions.leading!,
            Expanded(
              child: Directionality(
                textDirection: widget.inputOptions.inputTextDirection,
                child: TextField(
                  focusNode: focusNode,
                  controller: textController,
                  enabled: !widget.inputOptions.inputDisabled,
                  textCapitalization: widget.inputOptions.textCapitalization,
                  textInputAction: widget.inputOptions.textInputAction,
                  decoration: widget.inputOptions.inputDecoration ??
                      defaultInputDecoration(),
                  maxLength: widget.inputOptions.maxInputLength,
                  minLines: 1,
                  maxLines: widget.inputOptions.sendOnEnter
                      ? 1
                      : widget.inputOptions.inputMaxLines,
                  cursorColor: widget.inputOptions.cursorStyle.color,
                  cursorWidth: widget.inputOptions.cursorStyle.width,
                  showCursor: !widget.inputOptions.cursorStyle.hide,
                  style: widget.inputOptions.inputTextStyle,
                  onSubmitted: (String value) {
                    if (widget.inputOptions.newlineOnShiftEnter &&
                        _shiftPressed) {
                      setState(() {
                        textController.text += '\n';
                      });
                    } else if (widget.inputOptions.sendOnEnter) {
                      _sendMessage();
                    }
                  },
                  onChanged: (String value) async {
                    setState(() {});
                    if (widget.inputOptions.onTextChange != null) {
                      widget.inputOptions.onTextChange!(value);
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (widget.inputOptions.onMention != null) {
                        await _checkMentions(value);
                      }
                    });
                  },
                  autocorrect: widget.inputOptions.autocorrect,
                ),
              ),
            ),
            if (widget.inputOptions.trailing != null &&
                widget.inputOptions.showTraillingBeforeSend)
              ...widget.inputOptions.trailing!,
            if (widget.inputOptions.alwaysShowSend ||
                textController.text.isNotEmpty)
              widget.inputOptions.sendButtonBuilder != null
                  ? widget.inputOptions.sendButtonBuilder!(_sendMessage)
                  : defaultSendButton(color: Theme.of(context).primaryColor)(
                      _sendMessage,
                    ),
            if (widget.inputOptions.trailing != null &&
                !widget.inputOptions.showTraillingBeforeSend)
              ...widget.inputOptions.trailing!,
          ],
        ),
      ),
    );
  }

  Future<void> _checkMentions(String text) async {
    bool hasMatch = false;
    for (final String trigger in widget.inputOptions.onMentionTriggers) {
      final RegExp regexp = RegExp(r'(?<![^\s<>])' + trigger + r'([^\s<>]+)$');
      if (regexp.hasMatch(text)) {
        hasMatch = true;
        currentMentionIndex = textController.text.indexOf(regexp);
        currentTrigger = trigger;
        List<Widget> children = await widget.inputOptions.onMention!(
          trigger,
          regexp.firstMatch(text)!.group(1)!,
          _onMentionClick,
        );
        _showMentionModal(children);
      }
    }
    if (!hasMatch) {
      _clearOverlay();
    }
  }

  void _onMentionClick(String value) {
    textController.text = textController.text.replaceRange(
      currentMentionIndex,
      textController.text.length,
      currentTrigger + value,
    );
    textController.selection = TextSelection.collapsed(
      offset: textController.text.length,
    );
    _clearOverlay();
  }

  void _clearOverlay() {
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      _overlayEntry?.remove();
      _overlayEntry?.dispose();
    }
  }

  void _showMentionModal(List<Widget> children) {
    final OverlayState overlay = Overlay.of(context);
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset topLeftCornerOffset = renderBox.localToGlobal(Offset.zero);

    double bottomPosition =
        MediaQuery.of(context).size.height - topLeftCornerOffset.dy;
    if (widget.inputOptions.inputToolbarMargin != null) {
      bottomPosition -= widget.inputOptions.inputToolbarMargin!.top -
          widget.inputOptions.inputToolbarMargin!.bottom;
    }

    _clearOverlay();

    _overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          width: renderBox.size.width,
          bottom: bottomPosition,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height -
                  bottomPosition -
                  MediaQuery.of(context).padding.top -
                  kToolbarHeight,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).canvasColor,
              border: Border(
                top: BorderSide(
                  width: 0.2,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Material(
              color: Theme.of(context).hoverColor,
              child: SingleChildScrollView(
                child: Column(
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _sendMessage({bool removeLastNewline = false}) {
    if (textController.text.isNotEmpty) {
      var text = textController.text;
      if (removeLastNewline) {
        if (text.endsWith("\n")) {
          text = text.substring(0, text.length - 1);
        }
      }
      final ChatMessage message = ChatMessage(
        text: text,
        user: widget.currentUser,
        createdAt: DateTime.now(),
      );
      widget.onSend(message);
      textController.text = '';
      if (widget.inputOptions.onTextChange != null) {
        widget.inputOptions.onTextChange!('');
      }
    }
  }
}
