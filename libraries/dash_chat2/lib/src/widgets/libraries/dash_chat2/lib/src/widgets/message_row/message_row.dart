part of dash_chat_2;

Widget stripeDecorator(
    {required Widget child,
    bool none = true,
    bool leftRight = false,
    Color colorLeft = Colors.green,
    Color colorRight = Colors.purple,
    double width = 5.0,
    EdgeInsets padding = const EdgeInsets.all(5.0)}) {
  if (none) {
    return child;
  } else {
    if (leftRight) {
      return Container(
          child: Row(children: [
        Column(children: [
          Padding(
              padding: padding,
              child: Container(color: colorLeft, width: width))
        ]),
        Wrap(children: [child]),
      ]));
    } else {
      return Container(
          child: Row(children: [
        Column(children: [
          Wrap(children: [child]),
          Padding(
              padding: padding,
              child: Container(color: colorLeft, width: width))
        ]),
      ]));
    }
  }
}

// Widget maybeExpand(BuildContext context,
//     {required Widget child, required bool fullWidthRow, double factor = 0.9}) {
//   if (!fullWidthRow) {
//     return child;
//   }
//   return SizedBox(
//       width: MediaQuery.of(context).size.width * factor,
//       child: Row(children: [Expanded(child: child)]));
// }

/// @nodoc
class MessageRow extends StatelessWidget {
  const MessageRow({
    required this.message,
    required this.currentUser,
    this.previousMessage,
    this.nextMessage,
    this.isAfterDateSeparator = false,
    this.isBeforeDateSeparator = false,
    this.messageOptions = const MessageOptions(),
    Key? key,
  }) : super(key: key);

  /// Current message to show
  final ChatMessage message;

  /// Previous message in the list
  final ChatMessage? previousMessage;

  /// Next message in the list
  final ChatMessage? nextMessage;

  /// Current user of the chat
  final ChatUser currentUser;

  /// If the message is preceded by a date separator
  final bool isAfterDateSeparator;

  /// If the message is before a date separator
  final bool isBeforeDateSeparator;

  /// Options to customize the behaviour and design of the messages
  final MessageOptions messageOptions;

  /// Get the avatar widget
  Widget getAvatar() {
    return messageOptions.avatarBuilder != null
        ? messageOptions.avatarBuilder!(
            message.user,
            messageOptions.onPressAvatar,
            messageOptions.onLongPressAvatar,
          )
        : DefaultAvatar(
            user: message.user,
            onLongPressAvatar: messageOptions.onLongPressAvatar,
            onPressAvatar: messageOptions.onPressAvatar,
          );
  }

  @override
  Widget build(BuildContext context) {
    final bool isOwnMessage = message.user.id == currentUser.id;
    bool isPreviousSameAuthor = false;
    bool isNextSameAuthor = false;
    if (previousMessage != null &&
        previousMessage!.user.id == message.user.id) {
      isPreviousSameAuthor = true;
    }
    if (nextMessage != null && nextMessage!.user.id == message.user.id) {
      isNextSameAuthor = true;
    }

    Color? bgColor;

    if (message.customBackgroundColor != null) {
      bgColor = message.customBackgroundColor;
    }

    return Container(
      margin: isAfterDateSeparator
          ? EdgeInsets.zero
          : isPreviousSameAuthor
              ? messageOptions.marginSameAuthor
              : messageOptions.marginDifferentAuthor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          if (messageOptions.showOtherUsersAvatar)
            Opacity(
              opacity:
                  !isOwnMessage && (!isNextSameAuthor || isBeforeDateSeparator)
                      ? 1
                      : 0,
              child: getAvatar(),
            ),
          if (!messageOptions.showOtherUsersAvatar)
            SizedBox(width: messageOptions.spaceWhenAvatarIsHidden),
          GestureDetector(
            onLongPress: messageOptions.onLongPressMessage != null
                ? () => messageOptions.onLongPressMessage!(message)
                : null,
            onTap: messageOptions.onPressMessage != null
                ? () => messageOptions.onPressMessage!(message)
                : null,
            child: Container(
                constraints: BoxConstraints(
                  maxWidth: messageOptions.maxWidth ??
                      MediaQuery.of(context).size.width *
                          (messageOptions.fullWidthRow ? 0.9 : 0.7),
                ),
                child: stripeDecorator(
                  none: true,
                  leftRight: isOwnMessage,
                  child: Column(
                    crossAxisAlignment: isOwnMessage
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (messageOptions.top != null)
                        messageOptions.top!(
                            message, previousMessage, nextMessage),
                      if (!isOwnMessage &&
                          messageOptions.showOtherUsersName &&
                          (!isPreviousSameAuthor || isAfterDateSeparator))
                        messageOptions.userNameBuilder != null
                            ? messageOptions.userNameBuilder!(message.user)
                            : DefaultUserName(user: message.user),
                      if (message.medias != null &&
                          message.medias!.isNotEmpty &&
                          messageOptions.textBeforeMedia)
                        messageOptions.messageMediaBuilder != null
                            ? messageOptions.messageMediaBuilder!(
                                message, previousMessage, nextMessage)
                            : MediaContainer(
                                message: message,
                                isOwnMessage: isOwnMessage,
                                messageOptions: messageOptions,
                              ),
                      if (message.text.isNotEmpty)
                        // maybeExpand(context,
                        //     fullWidthRow: messageOptions.fullWidthRow,
                        //     child:
                        TextContainer(
                          messageOptions: messageOptions,
                          message: message,
                          previousMessage: previousMessage,
                          nextMessage: nextMessage,
                          isOwnMessage: isOwnMessage,
                          isNextSameAuthor: isNextSameAuthor,
                          isPreviousSameAuthor: isPreviousSameAuthor,
                          isAfterDateSeparator: isAfterDateSeparator,
                          isBeforeDateSeparator: isBeforeDateSeparator,
                          messageTextBuilder: messageOptions.messageTextBuilder,
                          color: bgColor,
                        ),
                      if (message.medias != null &&
                          message.medias!.isNotEmpty &&
                          !messageOptions.textBeforeMedia)
                        messageOptions.messageMediaBuilder != null
                            ? messageOptions.messageMediaBuilder!(
                                message, previousMessage, nextMessage)
                            : MediaContainer(
                                message: message,
                                isOwnMessage: isOwnMessage,
                                messageOptions: messageOptions,
                              ),
                      if (messageOptions.bottom != null)
                        messageOptions.bottom!(
                            message, previousMessage, nextMessage),
                    ],
                  ),
                )),
          ),
          if (messageOptions.showCurrentUserAvatar)
            Opacity(
              opacity: isOwnMessage && !isNextSameAuthor ? 1 : 0,
              child: getAvatar(),
            ),
          if (!messageOptions.showCurrentUserAvatar)
            SizedBox(width: messageOptions.spaceWhenAvatarIsHidden),
        ],
      ),
    );
  }
}
