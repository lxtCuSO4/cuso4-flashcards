import 'dart:typed_data';
import 'dart:ui' as ui;

Future<Uint8List> imageBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff00a080), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
