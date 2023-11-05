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
          uuid: Uuid.generate(),
          clientUuid: chatManager.clientUuid,
          title: 'Test Chat');

      _message = Message.fromChat(_chat, 'Test Message', 'user', null);

      print(
          "Test creating chats and messages: ${_chat.toJson()}, ${_message.toJson()}");

      chat = await chatManager.createChat('Test Chat');

      message = await chatManager.addMessageToChat(
          chat.uuid, 'Test message', 'user') as Message;
      print(message);
    });

    test('createChat creates a new chat', () async {
      final chats = await chatManager.getAllChats();
      expect(chats.map((c) => c.title), contains(chat.title));
    });

    test('addMessageToChat adds a message to a chat', () async {
      // previously added msg
      final messages = await chatManager.getMessagesFromChat(chat.uuid);
      var len = messages.length;
      expect(messages.map((m) => m.uuid), contains(message.uuid));

      var _msg = await chatManager.addMessageToChat(
          chat.uuid, 'different msg', 'user');

      final messages2 = await chatManager.getMessagesFromChat(chat.uuid);
      var len2 = messages2.length;
      expect(messages2.map((m) => m.uuid), contains(_msg!.uuid));
      expect(len2, len + 1);
    });

    test('updateMessage updates a message in a chat', () async {
      const ttxt = 'lorem ipsum';
      var _msg = await chatManager.addMessageToChat(chat.uuid, ttxt, 'user')
          as Message;

      var msg_uuid_bytes = _msg.uuid.toBytes();
      var msg_uuid_b64 = _msg.uuid.toString();

      print("Created msg $msg_uuid_b64 with text $ttxt");

      expect((await chatManager.getMessage(_msg.uuid))!.message, _msg.message);

      print("AFTER -> ${await chatManager.getMessagesFromChat(chat.uuid)}");

      dumpTable(tableName: 'messages', db: await chatManager.db());

      expect(
          (await chatManager.getMessagesFromChat(chat.uuid))
              .map((m) => m.uuid.toBytes()),
          containsOnce(msg_uuid_bytes));

      const newText = 'Updated Message';
      print("Updating message ${_msg.uuid}");
      bool ret = await chatManager.updateMessage(_msg.uuid, newText);
      expect(ret, true);
      final messages = await chatManager.getMessagesFromChat(chat.uuid);
      final msg = messages.firstWhere((m) => m.uuid == _msg.uuid);
      expect(msg.message, contains(newText));
    });

    test('deleteMessage deletes a message from a chat', () async {
      await chatManager.deleteMessage(message.uuid);
      final messages = await chatManager.getMessagesFromChat(chat.uuid);
      expect(messages.map((m) => m.uuid), isNot(contains(message.uuid)));
    });

    test('searchMessages returns chats containing a substring', () async {
      // dumpTable(tableName: 'messages', db: await chatManager.db());
      final chatsAndMessages = await chatManager.searchMessages('Updated');
      expect(chatsAndMessages, isNotEmpty);
      expect(chatsAndMessages.length, 1);
      expect(chatsAndMessages, everyElement(isA<(Chat, Message)>()));

      final chatsAndMessages2 = await chatManager.searchMessages('different');
      expect(chatsAndMessages2, isNotEmpty);
      expect(chatsAndMessages2.length, 1);
      expect(chatsAndMessages2, everyElement(isA<(Chat, Message)>()));
    });

    test('searchMessages is consistent after message creation and deletion',
        () async {
      final chatsAndMessagesNone =
          await chatManager.searchMessages('osdhfldsuofn');
      expect(chatsAndMessagesNone, isEmpty);

      // dumpTable(
      //     tableName: 'messages',
      //     db: await chatManager.db(),
      //     columns: {'message'});

      final chatsAndMessages1 = await chatManager.searchMessages('Updated');
      expect(chatsAndMessages1, isNotEmpty);
      expect(chatsAndMessages1.length, 1);
      expect(chatsAndMessages1, everyElement(isA<(Chat, Message)>()));

      // Add a new message to the chat
      var _msg2 = await chatManager.addMessageToChat(
          chat.uuid, 'Another Updated Test Message', 'user');

      print("INSERTION HAPPENED");

      dumpTable(
          tableName: 'messages',
          db: await chatManager.db(),
          columns: {'message'});
      dumpTable(
          tableName: 'messages_fts',
          db: await chatManager.db(),
          columns: {'message', 'rowid'});

      // Check if the search results are still valid
      final chatsAndMessages2 = await chatManager.searchMessages('Updated');
      expect(chatsAndMessages2, isNotEmpty);
      expect(chatsAndMessages2.length, 2);
      expect(chatsAndMessages2, everyElement(isA<(Chat, Message)>()));

      // Delete the new message from the chat
      await chatManager.deleteMessage(_msg2!.uuid);

      print("DELETION HAPPENED");
      //
      // dumpTable(
      //     tableName: 'messages',
      //     db: await chatManager.db(),
      //     columns: {'message'});
      // dumpTable(
      //     tableName: 'messages_fts',
      //     db: await chatManager.db(),
      //     columns: {'message', 'rowid'});

      // Check if the search results are still valid
      final chatsAndMessages3 = await chatManager.searchMessages('Updated');
      expect(chatsAndMessages3, isNotEmpty);
      expect(chatsAndMessages3.length, 1);
      expect(chatsAndMessages3, everyElement(isA<(Chat, Message)>()));
    });
  });

  group('MetadataManager', () {
    late MetadataManager metadataManager;

    setUpAll(() async {
      metadataManager = MetadataManager();
      // Initialize the database or any setup required
    });

    test('setMetadata inserts metadata into the database', () async {
      final key = 'testKey';
      final value = 'testValue';
      await metadataManager.setMetadata(key, value);

      final result = await metadataManager.getMetadata(key);
      expect(result, value);
    });

    test('getMetadataCollection retrieves all metadata in a subspace',
        () async {
      // Set up some metadata in a subspace
      final subspace = 'testSubspace';
      await metadataManager.setMetadata('key1', 'value1', subspace: subspace);
      await metadataManager.setMetadata('key2', 'value2', subspace: subspace);

      final results =
          await metadataManager.getMetadataCollection(subspace, 'key1');
      expect(results.map((r) => r['value']), contains('value1'));
      expect(results.map((r) => r['value']), contains('value2'));
    });

    test('getMetadata retrieves metadata by key', () async {
      final key = 'testKey';
      final value = 'testValue';
      await metadataManager.setMetadata(key, value);

      final result = await metadataManager.getMetadata(key);
      expect(result, value);
    });
  });
}
