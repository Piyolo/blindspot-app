import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('labelsV5.txt has exactly the 14 expected class names', () async {
    final text = await rootBundle.loadString('assets/ml/labelsV5.txt');
    final labels = text
        .trim()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    expect(labels.length, 14);
    expect(labels.first, 'Bed');
    expect(labels.last, 'Toilet');
  });

  test('yolov8nV5.tflite loads and matches the frozen model size', () async {
    final data = await rootBundle.load('assets/ml/yolov8nV5.tflite');
    expect(data.lengthInBytes, 12290965);
  });

  test('alarm.mp3 loads', () async {
    final data = await rootBundle.load('assets/audio/alarm.mp3');
    expect(data.lengthInBytes, 50105);
  });
}
