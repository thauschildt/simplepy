import 'package:test/test.dart';
import 'package:simplepy/src/lexer.dart';
import 'package:simplepy/src/parser.dart';
import 'package:simplepy/src/ast_nodes.dart';

// Helper function to parse and print AST
String parseAndPrint(String source) {
  final lexer = Lexer(source);
  final tokens = lexer.scanTokens();
  final parser = Parser(tokens);
  final statements = parser.parse();
  final printer = AstPrinter();
  return statements.map((stmt) => printer.printStmt(stmt)).join('\n');
}

void main() {
  group('Parser Basics', () {
    test('should parse simple arithmetic expression statement', () {
      final source = '1 + 2 * 3';
      final expectedAstString = '(expr_stmt (+ 1 (* 2 3)))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse variable assignment', () {
      final source = 'my_var = 10';
      final expectedAstString = '(expr_stmt (assign my_var 10))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

     test('should parse augmented assignment', () {
      final source = 'count += 1';
      // AST Printer uses 'aug_assign +=' format
      final expectedAstString = '(expr_stmt (aug_assign += count 1))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse if statement', () {
      final source = '''
if x > 0:
  y = 1
''';
      // Note: AstPrinter indents blocks
      final expectedAstString = '''
(if (> x 0)
  (then {
  (expr_stmt (assign y 1))
})
)'''; // Check formatting based on your AstPrinter output
      // Normalize whitespace for comparison if needed
      expect(
        parseAndPrint(source).replaceAll(RegExp(r'\s+'), ' ').trim(),
        equals(expectedAstString.replaceAll(RegExp(r'\s+'), ' ').trim()),
      );
    });

     test('should parse function definition', () {
      final source = '''
def add(a, b=1):
  return a + b
''';
      final expectedAstString = '''
def add(a, b=1):
  (return (+ a b))
'''; // Check AstPrinter's formatting
      expect(
        parseAndPrint(source).replaceAll(RegExp(r'\s+'), ' ').trim(),
        equals(expectedAstString.replaceAll(RegExp(r'\s+'), ' ').trim()),
      );
    });

     test('should parse function call', () {
      final source = 'print("hello", end="")';
      // AST Printer uses 'call <callee>' and lists args
      final expectedAstString = "(expr_stmt (call print 'hello' end=''))";
      expect(parseAndPrint(source), equals(expectedAstString));
     });
  });
}