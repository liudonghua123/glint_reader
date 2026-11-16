import 'package:flutter_test/flutter_test.dart';

import 'package:glint_reader/main.dart';
import 'package:glint_reader/models.dart';

void main() {
  testWidgets('App renders empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const GlintApp());
    await tester.pump();
    expect(find.text('打开一个文本文件开始阅读'), findsOneWidget);
  });

  test('FileKind infers language from file name', () {
    expect(FileKind.fromFileName('README.md').id, 'markdown');
    expect(FileKind.fromFileName('changes.diff').id, 'diff');
    expect(FileKind.fromFileName('data.json').id, 'json');
    expect(FileKind.fromFileName('config.yaml').id, 'yaml');
    expect(FileKind.fromFileName('main.py').id, 'python');
    expect(FileKind.fromFileName('Dockerfile').id, 'dockerfile');
    expect(FileKind.fromFileName('notes.txt').id, 'plaintext');
    expect(FileKind.fromFileName('unknown.xyz').id, 'plaintext');
  });
}
