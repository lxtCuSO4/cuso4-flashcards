import 'package:cuso4_flashcards/features/decks/domain/cloze_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = ClozeParser();
  test('distinct indexes are sorted and repeated deletions share a card', () {
    const source = '{{c3::水}} + {{c1::硫酸铜}} + {{c3::结晶水}}';
    expect(parser.indexes(source), [1, 3]);
    expect(parser.renderQuestion(source, 3), '[…] + 硫酸铜 + […]');
    expect(parser.renderAnswer(source, 3), '水 + 硫酸铜 + 结晶水');
  });
  test('hint and Unicode content survive rendering', () {
    const source = 'CuSO₄·5H₂O 呈 {{c1::蓝色::颜色}}，{{c2::易溶于水}}。';
    expect(parser.renderQuestion(source, 1), 'CuSO₄·5H₂O 呈 [颜色]，易溶于水。');
    expect(parser.renderAnswer(source, 1), 'CuSO₄·5H₂O 呈 蓝色，易溶于水。');
  });
  test('malformed syntax stays visible and creates no cards', () {
    const source = '{{c0::零}} {{c1::}} {{c2::未闭合} {{cx::文字}}';
    expect(parser.indexes(source), isEmpty);
    expect(parser.renderQuestion(source, 1), source);
    expect(parser.renderAnswer(source, 1), source);
  });
  test('multiline content and ordinary braces remain usable', () {
    const source = '{示例}\n{{c10::第一行\n第二行}}';
    expect(parser.indexes(source), [10]);
    expect(parser.renderQuestion(source, 10), '{示例}\n[…]');
    expect(parser.renderAnswer(source, 10), '{示例}\n第一行\n第二行');
  });
}
