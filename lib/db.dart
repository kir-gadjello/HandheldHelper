/* TASK:
As a professional flutter software engineer, write flutter code to setup sqlite db in app data directory if it is not set up yet and do these tasks on setup:

1. Create "messages" table where columns are:
date, username, index (int), message (text), uuid (blob), client_uuid (blob), chat_uuid (blob), meta (json)
2. Create associated virtual table(s), indices and triggers for seamless sqlite fts (fulltext search) functionality over the "message" field.
3. Create "chats" table where columns are:
date, username, title (text), uuid (blob), client_uuid (blob), chat_uuid, meta (json)
4. Create "metadata" table where columns are:
key (text), value (json).

The db table should be created only If it does not exist. Code should carefully handle macos, linux and android.

Write also a simple class wrapper for Chats and Messages supporting the following functions:
1. Chat creation and deletion
2. Addition of next message to a chat, update and delete of message.
3. Fulltext search for a user-provided substring over all messages.
4. Write a basic wrapper for metadata table to use it as a key-value storage.
*/

import 'dart:io';
import 'dart:core';
import 'dart:math';
import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import "dart:typed_data";

Future<List<Map<String, dynamic>>> fetchAllRows(
    String tableName, Database db) async {
  final List<Map<String, dynamic>> allRows = await db.query(tableName);
  return allRows;
}

Future<List<String>> fetchColumnNames(Database db, String tableName) async {
  final List<Map<String, dynamic>> columnNames =
      await db.rawQuery('PRAGMA table_info($tableName)');
  final columnNameList =
      columnNames.map((column) => column['name'] as String).toList();
  return columnNameList;
}

bytesAsHex(List<int> bytes) {
  String hexString = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toUpperCase();
  return hexString;
}

void dumpTable(
    {String? tableName,
    Database? db,
    String? path,
    Set<String>? columns}) async {
  if (tableName == null || (db == null && path == null)) {
    print('Warning: NO DB');
    return;
  }

  if (path != null) {
    db = await openDatabase(path);
  }

  final _db = db as Database;

  final List<String> columnNames = await fetchColumnNames(_db, tableName);
  final List<Map<String, dynamic>> allRows = await _db.query(tableName);

  if (columns != null) {
    for (var c in columns) {
      columnNames.removeWhere((cn) => !columns.contains(cn));
    }
  }

  // Print the column names
  print("-------------------------------------------------");
  print(
      "<<< TABLE DUMP: ${tableName} (${allRows.length} rows) from ${db.path} >>>");
  print(columnNames.join('\t'));

  // Print the rows
  allRows.forEach((row) {
    final rowValues = columnNames.map((columnName) {
      if (row[columnName] is Uint8List) {
        return bytesAsHex(row[columnName]);
      }
      return row[columnName]?.toString() ?? '';
    }).toList();
    print(rowValues.join('\t'));
  });
  print("-------------------------------------------------");
}

Uint8List intToBytes(int value) {
  return Uint8List(4)..buffer.asInt32List()[0] = value;
}

bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  if (identical(a, b)) {
    return true;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

class Uuid {
  final List<int> _bytes;

  Uuid(this._bytes);

  factory Uuid.fromBytes(List<int> bytes) {
    return Uuid(bytes);
  }

  factory Uuid.fromInt(int id) {
    return Uuid(intToBytes(id));
  }

  @override
  bool operator ==(Object other) {
    bool ret = false;
    if (identical(this, other)) {
      ret = true;
    } else {
      ret = other is Uuid && listEquals(other._bytes, _bytes);
    }
    // print("UUID EQ TEST ==: ${this.toString()} ? ${other.toString()} = $ret");
    return ret;
  }

  @override
  int get hashCode => _bytes.hashCode;

  String get asString => base64UrlEncode(_bytes);

  factory Uuid.generate() {
    final rng = Random();
    final bytes = <int>[];
    for (var i = 0; i < 16; i++) {
      bytes.add(rng.nextInt(256));
    }
    return Uuid(bytes);
  }

  Uint8List toBytes() {
    return Uint8List.fromList(_bytes);
  }

  Map<String, dynamic> toJson() {
    return {'bytes': toBytes()};
  }

  factory Uuid.fromJson(Map<String, dynamic> json) {
    final dynamicList = json['bytes'] as List<dynamic>;
    final List<int> bytes = dynamicList.map((item) => item as int).toList();
    print("UUID BYTES: ${json['bytes']} => $bytes, Uuid(...) = ${Uuid(bytes)}");
    return Uuid(bytes);
  }

  @override
  String toString() {
    // return base64UrlEncode(_bytes);
    return _bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('')
        .toUpperCase();
  }
}

Future<void> createFtsIndex(
    Database db, String tableName, List<String> fieldsToIndex) async {
  String indexName = '${tableName}_fts';
  String fields = fieldsToIndex.join(', ');

  await db.execute('''
    CREATE VIRTUAL TABLE IF NOT EXISTS $indexName USING fts4($fields)
  ''');

  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS ${tableName}_fts_insert AFTER INSERT ON $tableName BEGIN
      INSERT INTO $indexName(rowid, $fields) SELECT new.rowid, ${fieldsToIndex.map((field) => 'new.$field').join(', ')};
    END
  ''');

  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS ${tableName}_fts_update AFTER UPDATE ON $tableName BEGIN
      DELETE FROM $indexName WHERE rowid = old.rowid;
      INSERT INTO $indexName(rowid, $fields) VALUES(new.rowid, ${fieldsToIndex.map((field) => 'new.$field').join(', ')});
    END
  ''');

  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS ${tableName}_fts_delete AFTER DELETE ON $tableName BEGIN
      DELETE FROM $indexName WHERE rowid = old.rowid;
    END
  ''');
}

Future<List<Map<String, dynamic>>> search_fields(
    Database db, String tableName, List<String> fields, String query,
    {bool prefixQuery = false}) async {
  if (fields.isEmpty) {
    return [];
  }

  String indexName = '${tableName}_fts';
  String fieldsMatch = "${fields[0]} MATCH ?";

  if (fields.length > 1) {
    fieldsMatch = fields.join(' MATCH ? OR ');
  }

  if (prefixQuery) {
    query += '*';
  }

  return await db.rawQuery('''
  SELECT * FROM $tableName
  WHERE rowid IN (
    SELECT rowid FROM $indexName WHERE $fieldsMatch
  )
 ''', [query]);
}

Future<List<Map<String, dynamic>>> search_field(
    Database db, String tableName, String field, String query,
    {bool prefixQuery = false}) async {
  String indexName = '${tableName}_fts';

  if (prefixQuery) {
    query += '*';
  }

  return await db.rawQuery('''
  SELECT * FROM $tableName 
  WHERE rowid IN (
    SELECT rowid FROM $indexName WHERE $field MATCH ?
  )
 ''', [query]);
}

int getUnixTime() {
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

class Message {
  int date;
  String username;
  int messageIndex;
  String message;
  Uuid uuid;
  Uuid clientUuid;
  Uuid chatUuid;
  Map<String, dynamic> meta;

  Message({
    required this.username,
    required this.messageIndex,
    required this.message,
    required this.clientUuid,
    required this.chatUuid,
    Map<String, dynamic>? meta,
    int? date,
    Uuid? uuid,
  })  : uuid = uuid ?? Uuid.generate(),
        date = date ?? getUnixTime(),
        meta = meta ?? {};

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      date: json['date'],
      username: json['username'],
      messageIndex: json['message_index'],
      message: json['message'],
      uuid: Uuid.fromBytes(json['uuid']),
      clientUuid: Uuid.fromBytes(json['client_uuid']),
      chatUuid: Uuid.fromBytes(json['chat_uuid']),
      meta: jsonDecode(json['meta']),
    );
  }

  factory Message.fromChat(Chat parent, String message, String username,
      Map<String, dynamic>? meta) {
    return Message(
      date: getUnixTime(),
      username: username,
      messageIndex: parent.lastMsgIndex + 1,
      message: message,
      clientUuid: parent.clientUuid,
      chatUuid: parent.uuid,
      meta: meta ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'username': username,
      'message_index': messageIndex,
      'message': message,
      'uuid': uuid.toBytes(),
      'client_uuid': clientUuid.toBytes(),
      'chat_uuid': chatUuid.toBytes(),
      'meta': jsonEncode(meta),
    };
  }

  @override
  String toString() {
    return "MESSAGE:${jsonEncode(toJson())}";
  }
}

class Chat {
  int date;
  String? title;
  Uuid uuid;
  Uuid clientUuid;
  Map<String, dynamic> meta;
  int lastMsgIndex;

  Chat({
    int? date,
    Uuid? uuid,
    required this.clientUuid,
    this.title,
    Map<String, dynamic>? meta,
    int? lastMsgIndex,
  })  : date = date ?? getUnixTime(),
        lastMsgIndex = lastMsgIndex ?? 0,
        uuid = uuid ?? Uuid.generate(),
        meta = meta ?? {};

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      date: json['date'],
      title: json['title'],
      uuid: Uuid.fromBytes(json['uuid']),
      clientUuid: Uuid.fromBytes(json['client_uuid']),
      meta: jsonDecode(json['meta']),
      lastMsgIndex: json['last_msg_index'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'title': title,
      'uuid': uuid.toBytes(),
      'client_uuid': clientUuid.toBytes(),
      'meta': jsonEncode(meta),
      'last_msg_index': lastMsgIndex,
    };
  }

  String getHeading() => (title == null)
      ? "Chat from ${DateTime.fromMillisecondsSinceEpoch(date * 1000)}"
      : title!;
}

Future<String> resolve_db_dir() async {
  var databaseDir = await getDatabasesPath();
  if (Platform.isMacOS) {
    var userHome = Platform.environment["HOME"];
    if (userHome != null) {
      var userLibrary = join(userHome, "Library/Application Support");
      var userAppLibrary = join(userLibrary, "HHH");
      Directory(userAppLibrary).create();
      databaseDir = userAppLibrary;
    }
  }
  return databaseDir;
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  // final String databaseDir;

  factory DatabaseHelper() => _instance;

  static Database? _database;

  final dbName = Platform.environment.containsKey('FLUTTER_TEST')
      ? "testdb.sqlite"
      : "hhh_sqlite.db";

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    var databaseDir = await resolve_db_dir();
    final path = join(databaseDir, dbName);

    // if (Platform.environment.containsKey('FLUTTER_TEST')) {
    //   print("DB_PATH: ${path}");
    // }

    print("DB_PATH: ${path}");

    if (File(path).existsSync() && await databaseExists(path)) {
      var db = await openDatabase(path);
      final List<Map<String, dynamic>> results = await db
          .rawQuery('SELECT name FROM sqlite_master WHERE type = "table";');
      var tables = results.map((result) => result['name'] as String).toList();
      if (tables.contains('metadata')) {
        print("DB INIT OK, tables: ${tables}");
        return db;
      } else {
        print("DB INIT FAILED, recreating, tables: ${tables}");
        db.close();
        await deleteDatabase(db.path);
      }

      // await db
      //     .insert('metadata', {'key': 'first_run', 'value': jsonEncode(false)});
      // return db;
    }

    print("DB: creating new db at ${path}");

    if (!Directory(dirname(path)).existsSync()) {
      await Directory(dirname(path)).create(recursive: true);
    }

    // await openDatabase(dbName, version: 1);

    var db = await openDatabase(path, version: 1);
    await setupDatabase(db);

    return db;
  }

  Future<void> _resetDatabase({reinit = true}) async {
    var databaseDir = await resolve_db_dir();
    final path = join(databaseDir, dbName);

    await deleteDatabase(path);
    if (reinit) {
      await _initDatabase();
    }
  }

  Future<void> optimize() async {
    final db = await database;
    return db.execute("ANALYZE; PRAGMA optimize;");
  }

  Future<List<String>> getTables() async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db
        .rawQuery('SELECT name FROM sqlite_master WHERE type = "table";');
    return results.map((result) => result['name'] as String).toList();
  }

  Future<Uuid?> getClientUuid() async {
    final db = await database;
    final List<Map<String, Object?>> result = await db
        .rawQuery('SELECT value FROM metadata WHERE key = "client_uuid";');

    if (result.isNotEmpty) {
// Convert the JSON-formatted string to a List<int>
      final jsonString = result.first['value'] as String;
// Convert the List<int> to a Uuid object
      final Uuid uuid = Uuid.fromJson(jsonDecode(jsonString));
      return uuid;
    } else {
      return null;
    }
  }

  Future<void> setupDatabase(db) async {
// Create "messages" table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        uuid BLOB NOT NULL PRIMARY KEY,
        date INTEGER,
        username TEXT,
        message_index INTEGER,
        message TEXT,
        client_uuid BLOB,
        chat_uuid BLOB,
        meta JSON
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_username ON messages(username);
      CREATE INDEX idx_messages_date ON messages(date);
      CREATE INDEX idx_messages_chat_uuid ON messages(chat_uuid);
    ''');

    // Create FTS4 index for "messages" table
    await createFtsIndex(db, 'messages', ['message']);

// Create "chats" table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chats (
        uuid BLOB NOT NULL PRIMARY KEY,
        client_uuid BLOB,
        date INTEGER,
        title TEXT,
        meta JSON,
        last_msg_index INTEGER
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_chats_client_uuid ON chats(client_uuid);
      CREATE INDEX idx_chats_date ON chats(date);
      CREATE INDEX idx_chats_title ON chats(title);
    ''');

// Create "metadata" table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT NOT NULL PRIMARY KEY,
        value JSON
      )
    ''');

    var client_uuid = Uuid.generate();
    await db.insert(
        'metadata', {'key': 'client_uuid', 'value': jsonEncode(client_uuid)});
    // await db
    //     .insert('metadata', {'key': 'first_run', 'value': jsonEncode(true)});
  }
}

class ChatManager {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  Uuid clientUuid = Uuid.generate(); // will be replaced later

  ChatManager();

  Future<Database> db() {
    return _databaseHelper.database;
  }

  Future<void> initClientUUID() async {
    final db = await _databaseHelper.database;
    var ret = await _databaseHelper.getClientUuid();
    if (ret != null) {
      clientUuid = ret;
    }
  }

  Future<void> resetDatabase() async {
    await _databaseHelper._resetDatabase();
  }

// Add this method
  Future<List<String>> getTables() async {
    return await _databaseHelper.getTables();
  }

  Future<Chat> createChat(String? title) async {
    final db = await _databaseHelper.database;
// final chatCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM chats')) ?? 0;
    var chat =
        Chat(title: title, clientUuid: clientUuid, uuid: Uuid.generate());
    print("createChat ${chat.toJson()}");
    await db.insert('chats', chat.toJson());
    return chat;
  }

  Future<void> deleteChat(Uuid chatId) async {
    final db = await _databaseHelper.database;
    await db.delete('chats', where: 'uuid = ?', whereArgs: [chatId.toBytes()]);
  }

  Future<bool> updateChat(Uuid chatId, Map<String, dynamic> fields) async {
    final db = await _databaseHelper.database;
    try {
      await db.update('chats', fields,
          where: 'uuid = ?', whereArgs: [chatId.toBytes()]);
      return true;
    } catch (e) {
      print("Exception $e");
      return false;
    }
  }

  Future<Message?> addMessageToChat(
      Uuid chatId, String messageText, String username,
      {Map<String, dynamic>? meta}) async {
    final db = await _databaseHelper.database;
    print(chatId);

    var parent = await getChat(chatId);
    if (parent != null) {
      var msg = Message.fromChat(parent, messageText, username, meta);
      print("addMessageToChat: ${msg.toJson()}");
      await db.insert('messages', msg.toJson());
      await updateChat(chatId, {'last_msg_index': parent.lastMsgIndex + 1});
      parent.lastMsgIndex++;
      return msg;
    }
  }

  Future<bool> updateMessage(Uuid messageId, String newText,
      {Map<String, dynamic>? other_fields}) async {
    final db = await _databaseHelper.database;
    Map<String, dynamic> row = {'message': newText, ...other_fields ?? {}};
    print("ROW: ${row}");
    try {
      var query = '''
      UPDATE messages
      SET message = ?
      WHERE uuid = ?
      ''';

      var args = [newText, messageId.toBytes()];

      print("updateMessage: $query args = $args");

      int updateCount = await db.rawUpdate(query, args);

      print("updateCount: $updateCount");

      return updateCount > 0;
    } catch (e) {
      print("Exception $e");
      return false;
    }
  }

  Future<bool> deleteMessage(Uuid messageId) async {
    final db = await _databaseHelper.database;
    try {
      int deleted = await db.delete('messages',
          where: 'uuid = ?', whereArgs: [messageId.toBytes()]);
      return deleted == 1;
    } catch (e) {
      print("Exception $e");
      return false;
    }
  }

  Future<List<(Chat, Message)>> searchMessages(String substring,
      {bool prefixQuery = false}) async {
    final db = await _databaseHelper.database;
    final results = await search_fields(db, 'messages', ['message'], substring,
        prefixQuery: prefixQuery);

    if (results.isEmpty) {
      return [];
    }

    List<(Chat, Message)> output = [];

    for (var result in results) {
      Uuid msgUuid = Uuid.fromBytes(result['uuid']);
      Uuid chatUuid = Uuid.fromBytes(result['chat_uuid']);

      Chat? chat = await getChat(chatUuid);
      Message? message = await getMessage(msgUuid);
      if (chat != null && message != null) {
        output.add((chat, message));
      }
    }

    return output;
  }

  Future<Message?> getMessage(Uuid messageId) async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> results = await db.query(
      'messages',
      where: 'uuid = ?',
      whereArgs: [messageId.toBytes()],
    );

    if (results.isNotEmpty) {
      return Message.fromJson(results.first);
    }

    return null;
  }

  Future<Chat?> getChat(Uuid chatId) async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> results = await db.query(
      'chats',
      where: 'uuid = ?',
      whereArgs: [chatId.toBytes()],
    );

    if (results.isNotEmpty) {
      return Chat.fromJson(results.first);
    }

    return null;
  }

  Future<List<Chat>> getAllChats() async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> results = await db.rawQuery('''
    SELECT * FROM chats
  ''');

    return results.map((result) => Chat.fromJson(result)).toList();
  }

  Future<List<Chat>> getChats(List<Uuid> chatUuids) async {
    final db = await _databaseHelper.database;

    var placeholder =
        List<String>.generate(chatUuids.length, (index) => '?').join(',');

    final List<Map<String, dynamic>> results = await db.rawQuery('''
    SELECT * FROM chats WHERE uuid IN ($placeholder)
  ''', List.from(chatUuids.map((c) => c.toBytes())));

    return results.map((result) => Chat.fromJson(result)).toList();
  }

  Future<List<Message>> getMessagesFromChat(Uuid chatId) async {
    final db = await _databaseHelper.database;

    var query = '''
    SELECT * FROM messages WHERE chat_uuid = ?
  ''';

    var args = [chatId.toBytes()];

    print("getMessages - $query , $args");

    final List<Map<String, dynamic>> results = await db.rawQuery(query, args);

    return results.map((result) => Message.fromJson(result)).toList();
  }

  Future<List<Message>> getMessages(List<Uuid> msgUuids) async {
    final db = await _databaseHelper.database;

    var placeholder =
        List<String>.generate(msgUuids.length, (index) => '?').join(',');

    var query = '''
    SELECT * FROM messages WHERE uuid IN ($placeholder)
  ''';

    var args = List.from(msgUuids.map((c) => c.toBytes()));

    print("getMessages - $query , $args");

    final List<Map<String, dynamic>> results = await db.rawQuery(query, args);

    return results.map((result) => Message.fromJson(result)).toList();
  }
}

class MetadataManager {
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<void> setMetadata(String key, dynamic value,
      {String? subspace}) async {
    final db = await _databaseHelper.database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)',
      [
        (subspace == null) ? key : "__${subspace}__${key}",
        value,
      ],
    );
  }

  Future<dynamic> getMetadataCollection(String subspace, String key) async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> results = await db.query(
      'metadata',
      columns: ['value'],
      where: 'key LIKE ?',
      whereArgs: ["__${subspace}__%"],
    );

    return results;
  }

  Future<dynamic> getMetadata(String key) async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> results = await db.query(
      'metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );

    if (results.isNotEmpty) {
      return results.first['value'];
    }

    return null;
  }
}
