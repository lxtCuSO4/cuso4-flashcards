import 'dart:typed_data';

/// Small, bounded reader for the public Anki package/config protobuf fields.
/// Unknown scalar fields are skipped; groups and malformed lengths are rejected.
class AnkiProtoField {
  const AnkiProtoField(this.number, this.wire, this.integer, this.bytes);
  final int number, wire;
  final int? integer;
  final Uint8List? bytes;
}

Iterable<AnkiProtoField> readAnkiProto(List<int> input) sync* {
  if (input.length > 8 * 1024 * 1024) {
    throw const FormatException('Protobuf message too large');
  }
  final data = input is Uint8List ? input : Uint8List.fromList(input);
  var offset = 0;
  int varint() {
    var result = 0;
    for (var i = 0; i < 10; i++) {
      if (offset >= data.length) {
        throw const FormatException('Truncated varint');
      }
      final byte = data[offset++];
      if (i == 9 && byte > 1) throw const FormatException('Invalid varint');
      result |= (byte & 127) << (7 * i);
      if (byte < 128) return result;
    }
    throw const FormatException('Invalid varint');
  }

  while (offset < data.length) {
    final tag = varint();
    final number = tag >> 3, wire = tag & 7;
    if (number < 1 || number > 0x1fffffff) {
      throw const FormatException('Invalid field number');
    }
    if (wire == 0) {
      yield AnkiProtoField(number, wire, varint(), null);
    } else {
      final length = switch (wire) {
        1 => 8,
        2 => varint(),
        5 => 4,
        _ => throw const FormatException('Unsupported wire type'),
      };
      if (length < 0 || length > data.length - offset) {
        throw const FormatException('Truncated protobuf field');
      }
      final bytes = Uint8List.sublistView(data, offset, offset + length);
      offset += length;
      yield AnkiProtoField(number, wire, null, bytes);
    }
  }
}
