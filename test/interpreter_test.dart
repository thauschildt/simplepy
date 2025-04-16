import 'package:test/test.dart';
import 'package:simplepy/src/lexer.dart';
import 'package:simplepy/src/parser.dart';
import 'package:simplepy/src/interpreter.dart';
import 'package:simplepy/src/ast_nodes.dart';

class RunResult {
  final String output; // collected 'print' output
  final Object? error; // caught error (Exception) or null
  final Environment globals; // state of globals after execution
  RunResult(this.output, this.error, this.globals);
}

/// helper function for code execution and registering output and errors
RunResult runCode(String source, [Interpreter? existingInterpreter]) {
  final interpreter = existingInterpreter ?? Interpreter();
  final outputBuffer = StringBuffer();
  Object? caughtError;
  List<Stmt> statements = [];

  try {
    void capturePrint(String message) {
      outputBuffer.write(message);
    }

    // Pipeline: Lexer -> Parser -> Interpreter
    final lexer = Lexer(source);
    final tokens = lexer.scanTokens();
    final parser = Parser(tokens, (errMsg) {
      // Collect parser errors here (if it does not throw).
      caughtError ??= ParseError(Token(TokenType.NONE, "", null, 0,0), errMsg); // TODO: correct token info
    });
    statements = parser.parse();

    interpreter.interpret(
      statements,
      capturePrint,
      (errMsg) {
        caughtError ??= RuntimeError(Token(TokenType.EOF, "", null, 0,0), errMsg); // TODO: correct token info
      }
    );

  } on LexerError catch (e) {
      caughtError = e;
  } on ParseError catch (e) { // assuming parser throws exception
      caughtError = e;
  } on RuntimeError catch (e) {
      caughtError = e;
  } on ReturnValue {
      caughtError = RuntimeError(Token(TokenType.RETURN, 'return', null, 0, 0), "SyntaxError: 'return' outside function");
  } catch (e) { // catch any unexpected errors
    caughtError = e;
    print("Caught unexpected error during test run: $e");
  }

  return RunResult(outputBuffer.toString(), caughtError, interpreter.globals);
}

void main() {
  group('Interpreter Basics', () {
    test('should execute basic arithmetic and print', () {
      final source = '''
a = 10 + 5
b = a * 2
print(b / 4)
''';
      final result = runCode(source);
      expect(result.error, isNull);
      // Interpreter's stringify might add .0
      expect(result.output.trim(), equals('7.5'));
      // Check global variable state
      expect(result.globals.get(Token(TokenType.IDENTIFIER, 'b', null, 0, 0)), equals(30));
    });

    test('should handle variable assignment and lookup', () {
      final source = '''
x = 5
y = x
x = 10
print(x)
print(y)
''';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output, equals('10\n5\n'));
    });

     test('should execute if/else statements correctly', () {
      final source = '''
val = -5
if val > 0:
  print("positive")
elif val == 0:
  print("zero")
else:
  print("negative")
''';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output, equals('negative\n'));
    });

     test('should execute while loop with break', () {
      final source = '''
i = 0
while i < 5:
  print(i)
  if i == 2:
    break
  i += 1
print("done")
''';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output, equals('0\n1\n2\ndone\n'));
    });

     test('should execute for loop with range', () {
      final source = '''
total = 0
for x in range(3):
  total += x
print(total)
''';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output.trim(), equals('3')); // 0 + 1 + 2
    });

     test('should define and call function with return', () {
      final source = '''
def multiply(a, b):
  return a * b

result = multiply(4, 5)
print(result)
''';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output.trim(), equals('20'));
      expect(result.globals.get(Token(TokenType.IDENTIFIER, 'result', null, 0, 0)), equals(20));
    });

    test('should handle function scope (closures)', () {
      final source = '''
multiplier = 3
def make_times(n):
  def times(x):
    # Accesses 'n' from enclosing scope (closure)
    return n * x
  return times # Return the inner function

double = make_times(2)
triple = make_times(multiplier) # Uses global 'multiplier' when make_times runs

print(double(5))
print(triple(4))
''';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output, equals('10\n12\n'));
    });

     test('should handle built-in print with sep/end', () {
      final source = 'print(1, 2, 3, sep="-", end="!")';
      final result = runCode(source);
      expect(result.error, isNull);
      expect(result.output, equals('1-2-3!'));
     });

    test('should throw RuntimeError for division by zero', () {
      final source = 'print(10 / 0)';
      final result = runCode(source);
      expect(result.error, isNotNull);
      expect(result.error, isA<RuntimeError>());
      // Optionally check the error message if it's consistent
      expect((result.error as RuntimeError).message, contains('ZeroDivisionError'));
    });

    test('should throw RuntimeError for undefined variable', () {
      final source = 'print(undefined_variable)';
      final result = runCode(source);
      expect(result.error, isNotNull);
      expect(result.error, isA<RuntimeError>());
      expect((result.error as RuntimeError).message, contains("Undefined variable"));
    });

     test('should handle list creation and indexing', () {
       final source = '''
my_list = [10, 20, 30]
print(my_list[1])
my_list[0] = 5
print(my_list[0])
print(my_list[-1])
''';
       final result = runCode(source);
       expect(result.error, isNull);
       expect(result.output, equals('20\n5\n30\n'));
     });

     test('should handle dictionary creation and access', () {
       final source = '''
my_dict = {"a": 1, "b": 2}
print(my_dict["a"])
my_dict["c"] = 3
print(my_dict["c"])
''';
       final result = runCode(source);
       expect(result.error, isNull);
       expect(result.output, equals('1\n3\n'));
     });

      test('should handle augmented assignment correctly', () {
        final source = '''
x = 10
x += 5
print(x)
items = [1, 2]
items *= 2
print(items)
s = "a"
s += "b"
print(s)
# Test augmented assignment on list element
l = [100]
l[0] -= 10
print(l[0])
''';
        final result = runCode(source);
        expect(result.error, isNull, reason: result.error?.toString() ?? "No error");
        expect(result.output, equals('15\n[1, 2, 1, 2]\nab\n90\n'));
     });

     // Add more tests for:
     // - Other data types (if you add tuples, sets etc.)
     // - More complex function calls (kwargs, defaults, *args, **kwargs)
     // - Bitwise operations
     // - Logical operators (and, or, not) with short-circuiting
     // - Continue statement
     // - Error conditions (TypeError, IndexError, KeyError, etc.)
     
    test('should report ParseError for invalid syntax (missing colon)', () {
        final source = '''
if x > 0  # Missing colon here
  y = 1
''';
        final result = runCode(source);
        expect(result.error, isNotNull);
        expect(result.error, isA<ParseError>());
         if (result.error is ParseError) {
           expect((result.error as ParseError).message, contains("Expect ':' after if condition."));
         }
    });

  });
}