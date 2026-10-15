import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

List<int> protoInt(int field, int value) {
  List<int> varint(int v) {
    final out = <int>[];
    while (v > 127) {
      out.add((v & 127) | 128);
      v >>= 7;
    }
    return [...out, v];
  }

  return [...varint(field << 3), ...varint(value)];
}

List<int> protoBytes(int field, List<int> value) {
  final header = protoInt(field, value.length);
  header[0] |= 2;
  return [...header, ...value];
}

const fixtureImage = [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10];

Future<File> modernApkgFixture(
  Directory root, {
  int version = 3,
  bool badHash = false,
  bool truncated = false,
  int? declaredSize,
  List<int>? manifestBytes,
  String mediaName = 'salt.png',
  bool missingMedia = false,
}) async {
  final file = File(p.join(root.path, 'modern.sqlite'));
  final anki = sqlite3.open(file.path);
  try {
    anki.createCollation(
      name: 'unicase',
      function: (a, b) =>
          (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase()),
    );
    anki.execute('CREATE TABLE col (ver INTEGER, decks TEXT, models TEXT)');
    anki.execute("INSERT INTO col VALUES (18, '', '')");
    anki.execute(
      'CREATE TABLE decks (id INTEGER PRIMARY KEY, name TEXT COLLATE unicase)',
    );
    anki.execute('CREATE UNIQUE INDEX idx_decks_name ON decks(name)');
    anki.execute(
      'CREATE TABLE notetypes (id INTEGER PRIMARY KEY, name TEXT COLLATE unicase, config BLOB)',
    );
    anki.execute('CREATE UNIQUE INDEX idx_notetypes_name ON notetypes(name)');
    anki.execute(
      'CREATE TABLE fields (ntid INTEGER, ord INTEGER, name TEXT COLLATE unicase, PRIMARY KEY(ntid, ord)) WITHOUT ROWID',
    );
    anki.execute(
      'CREATE TABLE notes (id INTEGER, mid INTEGER, flds TEXT, tags TEXT)',
    );
    anki.execute(
      'CREATE TABLE cards (id INTEGER, nid INTEGER, did INTEGER, ord INTEGER)',
    );
    anki.execute('INSERT INTO decks VALUES (?, ?)', [1, '化学']);
    anki.execute('INSERT INTO decks VALUES (?, ?)', [2, '化学\u001f第一章']);
    for (final id in [100, 101]) {
      anki.execute('INSERT INTO notetypes VALUES (?, ?, ?)', [
        id, id == 100 ? 'Basic' : 'Cloze',
        // Include unknown fields to exercise forward-compatible protobuf skips.
        Uint8List.fromList([
          ...protoInt(1, id == 100 ? 0 : 1),
          ...protoBytes(3, utf8.encode('css')),
        ]),
      ]);
      final names = id == 100
          ? ['Front', 'Back', 'Source']
          : ['Text', 'Extra', 'Source'];
      for (var i = 0; i < names.length; i++) {
        anki.execute('INSERT INTO fields VALUES (?, ?, ?)', [id, i, names[i]]);
      }
    }
    anki.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
      10,
      100,
      'CuSO4<img src="salt.png">\u001f硫酸铜\u001f教材一',
      ' chemistry salt ',
    ]);
    anki.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
      11,
      101,
      '{{c1::蓝色}}与{{c2::晶体}}\u001f补充\u001f教材二',
      ' cloze ',
    ]);
    for (final card in [
      [20, 10, 2, 0],
      [21, 11, 2, 0],
      [22, 11, 2, 1],
    ]) {
      anki.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', card);
    }
  } finally {
    anki.close();
  }
  final encoder = ZstdEncoder();
  var collection = encoder.encodeBytes(await file.readAsBytes());
  if (truncated) collection = collection.sublist(0, collection.length - 3);
  final entry = [
    ...protoBytes(1, utf8.encode(mediaName)),
    ...protoInt(2, declaredSize ?? fixtureImage.length),
    ...protoBytes(
      3,
      badHash ? List.filled(20, 0) : sha1.convert(fixtureImage).bytes,
    ),
  ];
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('meta', protoInt(1, version)))
    ..addFile(ArchiveFile.string('collection.anki2', 'compatibility stub'))
    ..addFile(ArchiveFile.bytes('collection.anki21b', collection))
    ..addFile(
      ArchiveFile.bytes(
        'media',
        encoder.encodeBytes(manifestBytes ?? protoBytes(1, entry)),
      ),
    );
  if (!missingMedia) {
    archive.addFile(ArchiveFile.bytes('0', encoder.encodeBytes(fixtureImage)));
  }
  final apkg = File(p.join(root.path, 'modern.apkg'));
  await apkg.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return apkg;
}
