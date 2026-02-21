import 'package:test/test.dart';
import 'package:test/test.dart' as testpkg;
import 'package:simplepy/src/lexer.dart';
import 'package:simplepy/src/parser.dart';
import 'package:simplepy/src/ast_nodes.dart';

final _origExpect = testpkg.expect;
void expect(dynamic actual, dynamic expected, {dynamic matcher, dynamic reason}) {
  matcher ??= expected;
  if (matcher is int && actual is! int) {
    matcher = BigInt.from(matcher);
  }
  _origExpect(actual, matcher, reason: reason);
}

// Helper function to parse and print AST
String parseAndPrint(String source) {
  final lexer = Lexer(source);
  final tokens = lexer.scanTokens();
  final parser = Parser(tokens);
  final statements = parser.parse();
  final printer = AstPrinter();
  return statements.map((stmt) => printer.printStmt(stmt)).join('\n');
}

class ParseResult {
  final List<Stmt> statements;
  final List<String> errors;
  ParseResult(this.statements, this.errors);
  bool get hasErrors => errors.isNotEmpty;
}

// Helper function: Runs lexer and parser and collects errors
ParseResult parseAndCollectErrors(String source) {
  final lexer = Lexer(source);
  List<Token> tokens = [];
  List<String> collectedErrors = [];

  try {
    tokens = lexer.scanTokens();
  } on LexerError catch (e) {
    collectedErrors.add(e.toString());
    return ParseResult([], collectedErrors); // empty AST, report error
  }

  void errorCallback(String message) {
    collectedErrors.add(message);
  }

  final parser = Parser(tokens, errorCallback);
  List<Stmt> statements = [];

  try {
    // parse() catches errors internally and calls errorCallback
    statements = parser.parse();
  } catch (e) {
    // catches unexpected errors *within* the parser
    collectedErrors.add("Unexpected Parser Crash: $e");
  }
  return ParseResult(statements, collectedErrors);
}

String printStatements(List<Stmt> statements) {
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

    test('Parser should report ParseError for invalid token sequences', () {
      final result1 = parseAndCollectErrors('..'); // Two dots
      expect(
        result1.hasErrors,
        isTrue,
      ); // Or potentially LexerError depending on exact error reporting
      // expect((result1.error as ParseError).message, contains("...")); // Specific message depends on where parser fails

      final result2 = parseAndCollectErrors('1..'); // Number followed by dot
      expect(result2.hasErrors, isTrue); // Expect parser error after number
      // expect((result2.error as ParseError).message, contains("..."));

      final result3 = parseAndCollectErrors(
        '.e5',
      ); // Dot followed by identifier
      expect(result3.hasErrors, isTrue); // Expect parser error after dot
      // expect((result3.error as ParseError).message, contains("..."));

      final result4 = parseAndCollectErrors('1.'); // Valid float
      expect(result4.hasErrors, isFalse);

      final result5 = parseAndCollectErrors('.5'); // Valid float
      expect(result5.hasErrors, isFalse);
    });

    test('lambda syntax errors (reported by parser)', () {
      final result1 = parseAndCollectErrors('lambda x'); // Missing colon
      expect(result1.hasErrors, isTrue);
      expect(
        result1.errors.first,
        contains("Expect ':' after lambda parameters"),
      );

      final result2 = parseAndCollectErrors('lambda :'); // Missing expression
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Expect expression"));
    });
  });

  group('Comprehensions', () {
    test('should parse simple list comprehension', () {
      final source = '[i for i in range(5)]';
      final expectedAstString =
          '(expr_stmt (list_comp (elt: i,  generators: [comprehension(target=i, iter=(call range 5), ifs=[])])))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse list comprehension with for-if-if-for-if', () {
      final source =
          '[i for i in range(5) if i>0 if i%2==0 for j in range(5) if j<0]';
      final expectedAstString =
          '(expr_stmt (list_comp (elt: i,  generators: [comprehension(target=i, iter=(call range 5), ifs=[(> i 0), (== (% i 2) 0), ], ), comprehension(target=j, iter=(call range 5), ifs=[(< j 0), ])])))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse simple set comprehension', () {
      final source = '{i for i in range(5)}';
      final expectedAstString =
          '(expr_stmt (set_comp (elt: i, generators: [comprehension(target=i, iter=(call range 5), ifs=[])])))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse simple dict comprehension', () {
      final source = '{i: i*i for i in range(5)}';
      final expectedAstString =
          '(expr_stmt (dict_comp (key: i, value: (* i i), generators: [comprehension(target=i, iter=(call range 5), ifs=[])])))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
  });

  group('Slices', () {
    test('should parse x[a:b] slice', () {
      final source = 'x[1:2]';
      final expectedAstString =
          '(expr_stmt (subscript (x (slice lower 1 upper 2))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[:] slice', () {
      final source = 'x[:]';
      final expectedAstString = '(expr_stmt (subscript (x (slice))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[::] slice', () {
      final source = 'x[::]';
      final expectedAstString = '(expr_stmt (subscript (x (slice))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[a:b:c] slice', () {
      final source = 'x[1:2:3]';
      final expectedAstString =
          '(expr_stmt (subscript (x (slice lower 1 upper 2 step 3))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[a::c] slice', () {
      final source = 'x[1::3]';
      final expectedAstString =
          '(expr_stmt (subscript (x (slice lower 1 step 3))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[a:b:] slice', () {
      final source = 'x[1:2:]';
      final expectedAstString =
          '(expr_stmt (subscript (x (slice lower 1 upper 2))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[:b:c] slice', () {
      final source = 'x[:2:3]';
      final expectedAstString =
          '(expr_stmt (subscript (x (slice upper 2 step 3))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[a:] slice', () {
      final source = 'x[1:]';
      final expectedAstString = '(expr_stmt (subscript (x (slice lower 1))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[a::] slice', () {
      final source = 'x[1::]';
      final expectedAstString = '(expr_stmt (subscript (x (slice lower 1))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[:b:] slice', () {
      final source = 'x[:2:]';
      final expectedAstString = '(expr_stmt (subscript (x (slice upper 2))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
    test('should parse x[::c] slice', () {
      final source = 'x[::3]';
      final expectedAstString = '(expr_stmt (subscript (x (slice step 3))))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
  });

  group('Detect unexpected token errors', () {
    test('unexpected token after expression', () {
      final result1 = parseAndCollectErrors('x = 1 2');
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('2 ""');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));
    });

    test('unexpected token in if statements', () {
      final result1 = parseAndCollectErrors(
        'if 1==1:\n  print(2) else: print(3)',
      );
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('if 1==1: print(2) 3');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));

      final result3 = parseAndCollectErrors(
        'if 1==1: print(2)\nelse: print(3) 4',
      );
      expect(result3.hasErrors, isTrue);
      expect(result3.errors.first, contains("Unexpected token"));

      final result4 = parseAndCollectErrors(
        'if 1==1: print(2)\nelif 2==3: print(3) else',
      ); // Missing expression
      expect(result4.hasErrors, isTrue);
      expect(result4.errors.first, contains("Unexpected token"));
    });

    test('unexpected token in single-line while, for', () {
      final result1 = parseAndCollectErrors('while 1<0: x=2 3');
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('for x in range(1): print(x):');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));
    });

    test('unexpected token after return', () {
      final result1 = parseAndCollectErrors('return 1 2');
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('return "hello" 123');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));
    });

    test('unexpected token after pass/break/continue', () {
      final result1 = parseAndCollectErrors('pass 123');
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('break 123');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));

      final result3 = parseAndCollectErrors('continue 123');
      expect(result3.hasErrors, isTrue);
      expect(result3.errors.first, contains("Unexpected token"));
    });

    test('unexpected token after global/nonlocal', () {
      final result1 = parseAndCollectErrors('global x 123');
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('nonlocal x 123');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));
    });

    test('unexpected token after function definition', () {
      final result1 = parseAndCollectErrors('def foo(): pass 123');
      expect(result1.hasErrors, isTrue);
      expect(result1.errors.first, contains("Unexpected token"));

      final result2 = parseAndCollectErrors('def foo(): return 1 2');
      expect(result2.hasErrors, isTrue);
      expect(result2.errors.first, contains("Unexpected token"));
    });
  });

  group('Parse try, raise', () {
    test('should parse simple try/except', () {
      final source = '''
try:
  x=1/0
except:
  pass
  ''';
      final expectedAstString =
          '(try_stmt body {\n  (expr_stmt (assign x (/ 1 0)))\n}, handlers [(except body {\n  (pass)\n})],)';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse try with exception type, else and finally', () {
      final source = '''
try:
  pass
except ValueError as e:
  pass
else:
  pass
finally:
  pass
  ''';
      final expectedAstString =
          '(try_stmt body {\n  (pass)\n}, handlers [(except type ValueError, name e, body {\n  (pass)\n})], orelse {\n  (pass)\n}, finallybody {\n  (pass)\n})';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse re-raise', () {
      final source = 'raise';
      final expectedAstString = '(raise_stmt)';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse raise with type', () {
      final source = 'raise Exception';
      final expectedAstString = '(raise_stmt Exception)';
      expect(parseAndPrint(source), equals(expectedAstString));
    });

    test('should parse raise with type and variable name', () {
      final source = 'raise Exception("e")';
      final expectedAstString = '(raise_stmt (call Exception \'e\'))';
      expect(parseAndPrint(source), equals(expectedAstString));
    });
  });
}
