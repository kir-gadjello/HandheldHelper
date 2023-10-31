import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import '../lib/db.dart';

void main() async {
  // Initialize FFI
  sqfliteFfiInit();

  // Change the default factory
  databaseFactory = databaseFactoryFfi;

  var chatManager = ChatManager();
  await chatManager.resetDatabase();
  await chatManager.initClientUUID();

  group('DbHelper', () {
    test('database is initialized with the right tables', () async {
      final tables = await chatManager.getTables();
      expect(tables,
          containsAll(['chats', 'messages', 'metadata', 'messages_fts']));
    });
  });

  group('ChatManager', () {
    late Chat _chat, chat;
    late Message _message, message;

    setUpAll(() async {
      _chat = Chat(
          uuid: Uuid.fromBytes([1]),
          clientUuid: chatManager.clientUuid,
          title: 'Test Chat');

      _message = Message.fromChat(_chat, 'Test Message', 'user', null);

      chat = await chatManager.createChat('Test Chat');
      message = await chatManager.addMessageToChat(
          chat.uuid, 'Test message', 'user') as Message;
      // print(message);
    });

    test('createChat creates a new chat', () async {
      final chats = await chatManager.getChats();
      expect(chats.map((c) => c.title), contains(chat.title));
    });

    test('addMessageToChat adds a message to a chat', () async {
      final messages = await chatManager.getMessages(chat.uuid);
      expect(messages.map((m) => m.uuid), contains(message.uuid));
    });

    test('updateMessage updates a message in a chat', () async {
      // print("BEFORE ${await chatManager.getMessages(chat.uuid)}");
      var _msg = await chatManager.addMessageToChat(
          chat.uuid, 'lorem ipsum', 'user') as Message;

      var msg_uuid_bytes = _msg.uuid.toBytes();
      var msg_uuid_b64 = _msg.uuid.toString();

      expect((await chatManager.getMessage(_msg.uuid))!.message, _msg.message);

      // print("AFTER ${await chatManager.getMessages(chat.uuid)}");

      dumpTable(tableName: 'messages', db: await chatManager.db());

      expect(
          (await chatManager.getMessages(chat.uuid))
              .map((m) => m.uuid.toBytes()),
          containsOnce(msg_uuid_bytes));

      const newText = 'Updated Message';
      print("Updating message ${_msg.uuid}");
      bool ret = await chatManager.updateMessage(_msg.uuid, newText);
      expect(ret, true);
      final messages = await chatManager.getMessages(chat.uuid);
      final msg = messages.firstWhere((m) => m.uuid == _msg.uuid);
      expect(msg.message, contains(newText));
    });

    test('deleteMessage deletes a message from a chat', () async {
      await chatManager.deleteMessage(message.uuid);
      final messages = await chatManager.getMessages(chat.uuid);
      expect(messages.map((m) => m.uuid), isNot(contains(message.uuid)));
    });

    test('searchMessages returns chats containing a substring', () async {
      final chatsAndMessages = await chatManager.searchMessages('Test');
      expect(chatsAndMessages, isNotEmpty);
      expect(chatsAndMessages, everyElement(isA<(Chat, Message)>()));
    });

    // test(
    //     'searchMessages is consistent after message creation and deletion', () async {
    //   final chatsAndMessages1 = await chatManager.searchMessages('Test');
    //   expect(chatsAndMessages1, isNotEmpty);
    //   expect(chatsAndMessages1, everyElement(isA<(Chat,Message)>()));
    //
    //
    //   // Add a new message to the chat
    //   await chatManager.addMessageToChat(
    //       chat.uuid, Message(id: 2, text: 'Another Test Message'));
    //
    //   // Check if the search results are still valid
    //   final chatsAndMessages2 = await chatManager.searchMessages('Test');
    //   expect(chatsAndMessages2, isNotEmpty);
    //   expect(chatsAndMessages2, everyElement(isA<(Chat,Message)>()));
    //
    //
    //   // Delete the new message from the chat
    //   await chatManager.deleteMessage(2);
    //
    //   // Check if the search results are still valid
    //   final chatsAndMessages3 = await chatManager.searchMessages('Test');
    //   expect(chatsAndMessages3, isNotEmpty);
    //   expect(chatsAndMessages3, everyElement(isA<Chat>()));
    //   expect(chatsAndMessages3, everyElement(isA<Message>()));
    // });
  });
}
