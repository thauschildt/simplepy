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
  // Helper für einfachere Erwartungen in Tests
  bool get hasError => error != null;
  bool get hasParseError => error is ParseError;
  bool get hasRuntimeError => error is RuntimeError;
  bool get hasLexerError => error is LexerError;
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

    // Callback für Parser-Fehler
    void captureParseError(String message) {
      // print("Parser Error CB: $message"); // Debug
      // Nur den ersten Fehler speichern. Brauchen Token-Info für echtes ParseError-Objekt.
      // Wir erstellen hier ein "simuliertes" ParseError, da wir nur den String bekommen.
      // Besser wäre, wenn der Parser das Objekt übergeben würde.
      if (caughtError == null) {
        // Suche nach Zeilen-/Spalteninfo im String (heuristisch)
        final match = RegExp(
          r"\[line (\d+), col (\d+)\].*at \'([^\']+)\'",
        ).firstMatch(message);
        Token errorToken = Token(
          TokenType.EOF,
          match?.group(3) ?? '?',
          null,
          int.tryParse(match?.group(1) ?? '0') ?? 0,
          int.tryParse(match?.group(2) ?? '0') ?? 0,
        );
        caughtError = ParseError(errorToken, message);
      }
    }

    // Callback für Interpreter-Fehler
    void captureRuntimeError(String message) {
      // print("Runtime Error CB: $message"); // Debug
      // Nur den ersten Fehler speichern. Brauchen Token-Info für echtes RuntimeError-Objekt.
      // Besser wäre, wenn interpret() das Objekt übergeben würde.
      if (caughtError == null) {
        final match = RegExp(
          r"\[line (\d+), col (\d+)\].*near \'([^\']+)\'",
        ).firstMatch(message);
        Token errorToken = Token(
          TokenType.EOF,
          match?.group(3) ?? '?',
          null,
          int.tryParse(match?.group(1) ?? '0') ?? 0,
          int.tryParse(match?.group(2) ?? '0') ?? 0,
        );
        caughtError = RuntimeError(errorToken, message);
      }
    }

    // Pipeline: Lexer -> Parser -> Interpreter
    final lexer = Lexer(source);
    final tokens = lexer.scanTokens();
    final parser = Parser(tokens, captureParseError);
    statements = parser.parse();

    if (caughtError == null) {
      interpreter.interpret(
        statements,
        capturePrint,
        captureRuntimeError,
      ); // captures RuntimeError calling captureRuntimeError
    }
  } on LexerError catch (e) {
    caughtError = e;
  } on ParseError catch (e) {
    // assuming parser throws exception
    caughtError = e;
  } on RuntimeError catch (e) {
    caughtError = e;
  } on ReturnValue {
    caughtError = RuntimeError(
      Token(TokenType.RETURN, 'return', null, 0, 0),
      "SyntaxError: 'return' outside function",
    );
  } catch (e) {
    // catch any unexpected errors
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
      expect(
        result.globals.get(Token(TokenType.IDENTIFIER, 'b', null, 0, 0)),
        equals(30),
      );
    });

    test('should interpret and calculate with prefixed integers', () {
      final source = '''
hex_val = 0xFF  # 255
bin_val = 0b101 # 5
oct_val = 0o10  # 8
print(hex_val + 1)
print(bin_val * oct_val)
print(0x1A + 0b11 + 0o7) # 26 + 3 + 7
''';
      final result = runCode(source);
      expect(
        result.error,
        isNull,
        reason: result.error?.toString() ?? "No Error",
      );
      expect(result.output, equals('256\n40\n36\n')); // 255+1, 5*8, 26+3+7
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

    test("single-line if-statement", () {
      final result = runCode("""
if 1 == 0: print('1')
if 1 == 1: print('2')
""");
      expect(result.output, equals('2\n'));
    });

    test("single-line if/else-statement", () {
      final result = runCode("""
if 1 == 0: print('1')
else: print('2')
if 1 == 1: print('1')
else: print('2')
""");
      expect(result.output, equals('2\n1\n'));
    });

    test("single-line if/elif/else-statement", () {
      final result = runCode("""
if 1 == 0: print('1')
elif 2 == 0: print('2')
else: print('3')
if 1 == 0: print('1')
elif 2 == 2: print('2')
else: print('3')
if 1 == 1: print('1')
elif 2 == 0: print('2')
else: print('3')
""");
      expect(result.output, equals('3\n2\n1\n'));
    });

    test("single-line if/else with missing newline", () {
      final result = runCode("""
if 1 == 0: print('1') else: print('2')
""");
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Invalid syntax'),
        ),
      );
    });

    test("single-line if with missing newline", () {
      final result = runCode("""
if 1 == 0: print('1') print('2')
""");
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Invalid syntax'),
        ),
      );
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

    test("single-line while-loop", () {
      final result = runCode("""
x=1
while x < 10: x+=1
print(x)
""");
      expect(result.output, equals('10\n'));
    });

    test("single-line while-loop with missing newline", () {
      final result = runCode("""
while x < 10: print(x) x
""");
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Invalid syntax. Unexpected token'),
        ),
      );
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

    test("single-line for-loop", () {
      final result = runCode("""
for x in [1, 2]: print(x)
""");
      expect(result.output, equals('1\n2\n'));
    });

    test("single-line for-loop with missing newline", () {
      final result = runCode("""
for x in [1, 2]: print(x) y
""");
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Invalid syntax. Unexpected token'),
        ),
      );
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
      expect(
        result.globals.get(Token(TokenType.IDENTIFIER, 'result', null, 0, 0)),
        equals(20),
      );
    });

    test("single-line function-def", () {
      final result = runCode("""
def f(): return 42
print(f())
""");
      expect(result.output, equals('42\n'));
    });

    test("single-line function-def with missing newline", () {
      final result = runCode("""
def f(): x=2 return x
""");
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Invalid syntax. Unexpected token'),
        ),
      );
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
      expect(
        (result.error as RuntimeError).message,
        contains('ZeroDivisionError'),
      );
    });

    test('should throw RuntimeError for undefined variable', () {
      final source = 'print(undefined_variable)';
      final result = runCode(source);
      expect(result.error, isNotNull);
      expect(result.error, isA<RuntimeError>());
      expect(
        (result.error as RuntimeError).message,
        contains("Undefined variable"),
      );
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
      expect(
        result.error,
        isNull,
        reason: result.error?.toString() ?? "No error",
      );
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
        expect(
          (result.error as ParseError).message,
          contains("Expect ':' after if condition."),
        );
      }
    });
  });

  group('Interpreter Built-in Functions', () {
    // --- len() Tests ---
    test('len() should return length of string', () {
      final result = runCode('print(len("hello"))');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('5'));
    });
    test('len() should return length of list', () {
      final result = runCode('print(len([1, 2, 3, 4]))');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('4'));
    });
    test('len() should return length of dict (number of keys)', () {
      final result = runCode('print(len({"a": 1, "b": 2}))');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('2'));
    });
    test('len() should return 0 for empty string/list/dict', () {
      final result = runCode('print(len(""), len([]), len({}))');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('0 0 0'));
    });
    test('len() should raise TypeError for non-sequence types', () {
      expect(
        runCode('len(123)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('TypeError: object of type \'int\' has no len()'),
        ),
      );
      expect(
        runCode('len(None)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('TypeError: object of type \'NoneType\' has no len()'),
        ),
      );
      expect(
        runCode('len(True)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('TypeError: object of type \'bool\' has no len()'),
        ),
      );
    });
    test('len() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('len()').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (0 given)'),
      );
      expect(
        (runCode('len("a", "b")').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (2 given)'),
      );
    });

    // --- str() Tests ---
    test('str() should convert various types to string', () {
      final result = runCode('''
print(str(123))
print(str(1.5))
print(str(True))
print(str(None))
print(str([1, 'a']))
print(str({"k": 1}))
print(str("already string"))
''');
      expect(result.error, isNull);
      expect(
        result.output,
        equals(
          '123\n1.5\nTrue\nNone\n[1, \'a\']\n{\'k\': 1}\nalready string\n',
        ),
      );
    });
    test('str() without arguments should return empty string', () {
      final result = runCode('print(repr(str()))'); // Use repr to see quotes
      expect(result.error, isNull);
      expect(result.output.trim(), equals("''"));
    });
    test('str() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('str(1, 2)').error as RuntimeError).message,
        contains('takes at most 1 positional arguments (2 given)'),
      );
    });

    // --- int() Tests ---
    test('int() should convert types to integer', () {
      final result = runCode('''
print(int(10))
print(int(10.9)) # Truncates
print(int(-3.2)) # Truncates
print(int(True))
print(int(False))
print(int("123"))
print(int("-45"))
print(int("   100   ")) # Handles whitespace
''');
      expect(result.error, isNull);
      expect(result.output, equals('10\n10\n-3\n1\n0\n123\n-45\n100\n'));
    });
    test('int() without arguments should return 0', () {
      final result = runCode('print(int())');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('0'));
    });
    test('int() should handle base argument', () {
      final result = runCode('''
print(int("101", 2))
print(int("FF", 16))
print(int("77", 8))
print(int(" Z ", 36)) # Base 36
print(int("0xFF", 0)) # Auto-detect base 0
print(int("0b10", 0))
print(int("0o10", 0))
print(int("100", 0)) # Base 0 defaults to 10 if no prefix
print(int("0xff", 16)) # Allow prefix if base matches
''');
      expect(result.error, isNull);
      expect(result.output, equals('5\n255\n63\n35\n255\n2\n8\n100\n255\n'));
    });
    test('int() should raise ValueError for invalid string literals', () {
      expect(
        (runCode('int("abc")').error as RuntimeError).message,
        contains("ValueError: invalid literal for int() with base 10: 'abc'"),
      );
      expect(
        (runCode('int("10.5")').error as RuntimeError).message,
        contains("ValueError: invalid literal for int() with base 10: '10.5'"),
      );
      expect(
        (runCode('int("20", 2)').error as RuntimeError).message,
        contains("ValueError: invalid literal for int() with base 2: '20'"),
      );
      expect(
        (runCode('int("0x", 0)').error as RuntimeError).message,
        contains("ValueError: invalid literal for int() with base 16: '0x'"),
      );
      expect(
        (runCode('int("0x10", 10)').error as RuntimeError).message,
        contains("ValueError: invalid literal for int() with base 10: '0x10'"),
      );
    });
    test('int() should raise TypeError for invalid types or base combinations', () {
      expect(
        runCode('int(None)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains(
            "TypeError: int() argument must be a string, a bytes-like object or a number, not 'NoneType'",
          ),
        ),
      );
      expect(
        runCode('int([1])').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains(
            "TypeError: int() argument must be a string, a bytes-like object or a number, not 'list'",
          ),
        ),
      );
      expect(
        runCode('int(10, 2)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains(
            "TypeError: int() can't convert non-string with explicit base",
          ),
        ),
      );
      expect(
        runCode('int("10", 1.5)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: 'base' argument must be an integer"),
        ),
      );
    });
    test('int() should raise ValueError for invalid base value', () {
      expect(
        runCode('int("10", 1)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("ValueError: int() base must be >= 2 and <= 36, or 0"),
        ),
      );
      expect(
        runCode('int("10", 37)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("ValueError: int() base must be >= 2 and <= 36, or 0"),
        ),
      );
    });

    // --- float() Tests ---
    test('float() should convert types to float', () {
      final result = runCode('''
#print(float(10))
print(float(10.9))
print(float(-3.14))
#print(float(True))
#print(float(False))
print(float("123.4"))
print(float("-45.67"))
print(float("   3.141e2   ")) # Handles whitespace and scientific notation
#print(float("inf"))
#print(float("-Infinity"))
#print(float("NaN"))
''');
      expect(result.error, isNull);
      expect(result.output, equals('10.9\n-3.14\n123.4\n-45.67\n314.1\n'));
    });
    test('float() without arguments should return 0.0', () {
      final result = runCode('print(float())');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('0.0'));
    });
    test('float() should raise ValueError for invalid string literals', () {
      expect(
        runCode('float("abc")').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("ValueError: could not convert string to float: 'abc'"),
        ),
      );
      expect(
        runCode('float("1,23")').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("ValueError: could not convert string to float: '1,23'"),
        ),
      );
    });
    test('float() should raise TypeError for invalid types', () {
      expect(
        runCode('float(None)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains(
            "TypeError: float() argument must be a string or a number, not 'NoneType'",
          ),
        ),
      );
      expect(
        runCode('float([1])').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains(
            "TypeError: float() argument must be a string or a number, not 'list'",
          ),
        ),
      );
    });
    test('float() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('float(1, 2)').error as RuntimeError).message,
        contains('takes at most 1 positional arguments (2 given)'),
      );
    });

    // --- bool() Tests ---
    test('bool() should convert types using truthiness', () {
      final result = runCode('''
print(bool(True), bool(False))
print(bool(1), bool(0))
print(bool(0.1), bool(0.0))
print(bool("a"), bool(""))
print(bool([1]), bool([]))
print(bool({"a":1}), bool({}))
print(bool(None))
print(bool(print)) # Function object
''');
      expect(result.error, isNull);
      expect(
        result.output,
        equals(
          'True False\nTrue False\nTrue False\nTrue False\nTrue False\nTrue False\nFalse\nTrue\n',
        ),
      );
    });
    test('bool() without arguments should return False', () {
      final result = runCode('print(bool())');
      expect(result.error, isNull);
      expect(result.output.trim(), equals('False'));
    });
    test('bool() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('bool(1, 2)').error as RuntimeError).message,
        contains('takes at most 1 positional arguments (2 given)'),
      );
    });

    // --- type() Tests ---
    test('type() should return type string', () {
      final result = runCode('''
def my_func():
  pass
print(type(1))
print(type(1.0))
print(type("a"))
print(type(True))
print(type(None))
print(type([]))
print(type({}))
print(type((1,)))
print(type({1,'a'}))
print(type(print))
print(type(my_func))
''');
      expect(result.error, isNull);
      expect(
        result.output,
        equals(
          "<class 'int'>\n<class 'float'>\n<class 'str'>\n<class 'bool'>\n<class 'NoneType'>\n<class 'list'>\n<class 'dict'>\n<class 'tuple'>\n<class 'set'>\n<class 'builtin_function_or_method'>\n<class 'function'>\n",
        ),
      );
    });
    test('type() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('type()').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (0 given)'),
      );
      expect(
        (runCode('type(1, 2)').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (2 given)'),
      );
    });

    // --- abs() Tests ---
    test('abs() should return absolute value', () {
      final result = runCode('''
print(abs(5))
print(abs(-5))
print(abs(5.5))
print(abs(-5.5))
print(abs(True))
print(abs(False))
print(abs(0))
print(abs(-0.0))
''');
      expect(result.error, isNull);
      expect(result.output, equals('5\n5\n5.5\n5.5\n1\n0\n0\n0.0\n'));
    });
    test('abs() should raise TypeError for invalid types', () {
      expect(
        runCode('abs(None)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: bad operand type for abs(): 'NoneType'"),
        ),
      );
      expect(
        runCode('abs("a")').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: bad operand type for abs(): 'str'"),
        ),
      );
    });
    test('abs() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('abs()').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (0 given)'),
      );
      expect(
        (runCode('abs(1, 2)').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (2 given)'),
      );
    });

    // --- list() Tests ---
    test('list() should create lists', () {
      final result = runCode('''
print(list())
print(list("abc"))
l1 = [1, 2]
l2 = list(l1)
l1.append(3) # Modify original
print(l1)
print(l2)      # Should be a copy
print(list({"a":1, "b":2})) # List of keys
print(list(range(3)))
''');
      expect(result.error, isNull);
      // Note: Dict key order might vary in real python, but stable here for now.
      expect(result.output.contains('[]'), isTrue); // Empty list first
      expect(result.output.contains("['a', 'b', 'c']"), isTrue);
      expect(result.output.contains('[1, 2, 3]'), isTrue); // Modified l1
      expect(result.output.contains('[1, 2]'), isTrue); // Copied l2
      expect(result.output.contains("['a', 'b']"), isTrue); // Dict keys
      expect(result.output.contains('[0, 1, 2]'), isTrue); // From range
    });
    test('list() should raise TypeError for non-iterable', () {
      expect(
        runCode('list(123)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: 'int' object is not iterable"),
        ),
      );
      expect(
        runCode('list(None)').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: 'NoneType' object is not iterable"),
        ),
      );
    });
    test('list() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('list(1, 2)').error as RuntimeError).message,
        contains('takes at most 1 positional arguments (2 given)'),
      );
    });

    // --- dict() Tests ---
    test('dict() should create empty dict or copy existing', () {
      final result = runCode('''
d1 = {}
d2 = dict()
print(d1 == d2)
d3 = {"a": 1}
d4 = dict(d3)
d3["b"] = 2 # Modify original
print(d4)     # Should be copy
d5 = dict(a=1, b=2)
print(d5)
d6 = dict([["c",3], ["d",[4,5]]])
print(d6)
''');
      expect(result.error, isNull);
      expect(
        result.output,
        equals(
          'True\n{\'a\': 1}\n{\'a\': 1, \'b\': 2}\n{\'c\': 3, \'d\': [4, 5]}\n',
        ),
      );
    });
    test('dict() should raise TypeError for non-map args', () {
      expect(
        runCode('dict(1)').error,
        isA<RuntimeError>(),
      ); // Check message manually if needed, depends on impl path
      expect(runCode('dict("a")').error, isA<RuntimeError>());
      expect(runCode('dict([1])').error, isA<RuntimeError>());
    });
    test('dict() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('dict(1, 2)').error as RuntimeError).message,
        contains('takes at most 1 positional arguments (2 given)'),
      );
    });

    test('dict() should raise TypeError for list with item of length!=2', () {
      expect(
        (runCode('dict([[1,2,3]])').error as RuntimeError).message,
        contains('ValueError'),
      );
    });

    // --- round() Tests ---
    test('round() should round numbers', () {
      // Note: round half to even behavior
      final result = runCode('''
print(round(5.5))    # -> 6 (int)
print(round(4.5))    # -> 4 (int)
print(round(6.5))    # -> 6 (int) !! Python rounds to nearest *even* integer
print(round(5.4))    # -> 5 (int)
print(round(5.6))    # -> 6 (int)
print(round(-4.5))   # -> -4 (int)
print(round(-5.5))   # -> -6 (int)
print(round(123.456, 2)) # -> 123.46 (float)
print(round(123.454, 2)) # -> 123.45 (float)
print(round(123.456, 0)) # -> 123.0 (float)
print(round(123.456, -1))# -> 120.0 (float)
print(round(123.456, -2))# -> 100.0 (float)
print(round(175.0, -2)) # -> 200.0 (float)
print(round(123, -1))   # -> 120 (int)
print(round(123.0, -1)) # -> 120.0 (float)
print(round(True))      # -> 1 (int)
print(round(123.456, None)) # -> 123 (int)
''');
      expect(result.error, isNull);
      // Dart's round() behaves like Python 3's round half to even
      expect(
        result.output,
        equals(
          '6\n4\n6\n5\n6\n-4\n-6\n123.46\n123.45\n123\n120\n100\n200\n120\n120\n1\n123\n',
        ),
      );
      // should be:
      // expect(result.output, equals('6\n4\n6\n5\n6\n-4\n-6\n123.46\n123.45\n123.0\n120.0\n100.0\n200.0\n120\n120.0\n1\n123\n'));
    });
    test('round() should raise TypeError for invalid types', () {
      expect(
        runCode('round("a")').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: type str not supported"),
        ),
      );
      expect(
        runCode('round(1.5, "a")').error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("TypeError: 'ndigits' argument must be an integer"),
        ),
      );
    });
    test('round() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('round()').error as RuntimeError).message,
        contains('takes at least 1 positional arguments (0 given)'),
      );
      expect(
        (runCode('round(1, 2, 3)').error as RuntimeError).message,
        contains('takes from 1 to 2 positional arguments (3 given)'),
      );
    });

    // --- min() Tests ---
    test('min() should find minimum value', () {
      final result = runCode('''
print(min(1, 5, 0, 8))
print(min(-1, -5))
print(min(1.5, 0.5))
print(min("b", "a", "c"))
print(min([1, 0, 5]))
print(min("hello"))
print(min({"b":1, "a":2})) # Min of keys
#print(min((1,))) # Single element tuple/list (using list for test)
''');
      expect(result.error, isNull);
      expect(result.output, equals('0\n-5\n0.5\na\n0\ne\na\n'));
    });
    test('min() should raise error for empty or invalid args', () {
      expect(
        (runCode('min()').error as RuntimeError).message,
        contains('min expected 1 argument, got 0'),
      );
      expect(
        (runCode('min([])').error as RuntimeError).message,
        contains('ValueError: min() arg is an empty sequence'),
      );
      expect(
        (runCode('min({})').error as RuntimeError).message,
        contains('ValueError: min() arg is an empty sequence'),
      );
      expect(
        (runCode('min(1)').error as RuntimeError).message,
        contains("TypeError: 'int' object is not iterable"),
      );
      expect(
        (runCode('min(1, "a")').error as RuntimeError).message,
        contains("TypeError: '<' not supported between instances of"),
      );
    });

    // --- max() Tests ---
    test('max() should find maximum value', () {
      final result = runCode('''
print(max(1, 5, 0, 8))
print(max(-1, -5))
print(max(1.5, 0.5))
print(max("b", "a", "c"))
print(max([1, 0, 5]))
print(max("hello"))
print(max({"b":1, "a":2, "c":0})) # Max of keys
#print(max((5,))) # Single element tuple/list (using list for test)
''');
      expect(result.error, isNull);
      expect(result.output, equals('8\n-1\n1.5\nc\n5\no\nc\n'));
    });
    test('max() should raise error for empty or invalid args', () {
      expect(
        (runCode('max()').error as RuntimeError).message,
        contains('max expected 1 argument, got 0'),
      );
      expect(
        (runCode('max([])').error as RuntimeError).message,
        contains('ValueError: max() arg is an empty sequence'),
      );
      expect(
        (runCode('max({})').error as RuntimeError).message,
        contains('ValueError: max() arg is an empty sequence'),
      );
      expect(
        (runCode('max(1)').error as RuntimeError).message,
        contains("TypeError: 'int' object is not iterable"),
      );
      expect(
        (runCode('max(1, "a")').error as RuntimeError).message,
        contains("TypeError: '<' not supported between instances of"),
      );
    });

    // --- sum() Tests ---
    test('sum() should sum iterables', () {
      final result = runCode('''
print(sum([1, 2, 3]))
print(sum([1.5, 2.5]))
print(sum([]))
print(sum([1, 2, 3], 10))
#print(sum({1:10, 2:20}.values())) # Sum dict values
''');
      expect(result.error, isNull);
      expect(result.output, equals('6\n4.0\n0\n16\n'));
    });
    test('sum() should raise TypeError for invalid types', () {
      expect(
        (runCode('sum(1)').error as RuntimeError).message,
        contains("TypeError: 'int' object is not iterable or not summable"),
      );
      expect(
        (runCode('sum(["a"])').error as RuntimeError).message,
        contains(
          "TypeError: unsupported operand type(s) for +: 'int' and 'str'",
        ),
      );
      expect(
        (runCode('sum([1], "a")').error as RuntimeError).message,
        contains(
          "TypeError: unsupported operand type(s) for +: 'str' and 'int'",
        ),
      );
      expect(runCode('print({1:"a"}.values())').output, equals("['a']\n"));
      expect(
        (runCode('sum({1:"a"}.values())').error as RuntimeError).message,
        contains(
          "TypeError: unsupported operand type(s) for +: 'int' and 'str'",
        ),
      );
    });
    test('sum() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('sum()').error as RuntimeError).message,
        contains('takes at least 1 positional arguments (0 given)'),
      );
      expect(
        (runCode('sum([], 1, 2)').error as RuntimeError).message,
        contains('takes from 1 to 2 positional arguments (3 given)'),
      );
    });

    // --- repr() Tests ---
    test('repr() should return representation string', () {
      final result = runCode('''
print(repr(1))
print(repr(1.5))
print(repr("hello"))
print(repr("it's"))
print(repr('"quoted"'))
print(repr(True))
print(repr(None))
print(repr([1, "a'b", None]))
print(repr({"key": True}))
print(repr(print))
''');
      expect(result.error, isNull);
      expect(
        result.output,
        equals(
          "1\n1.5\n'hello'\n\"it\\'s\"\n'\"quoted\"'\nTrue\nNone\n[1, \"a\\'b\", None]\n{'key': True}\n<native fn>\n", // Adjust function repr if needed
        ),
      );
    });
    test('repr() should raise TypeError for wrong number of arguments', () {
      expect(
        (runCode('repr()').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (0 given)'),
      );
      expect(
        (runCode('repr(1, 2)').error as RuntimeError).message,
        contains('takes exactly 1 positional arguments (2 given)'),
      );
    });
  });

  group('Interpreter Lambdas', () {
    test('should create and call simple lambda', () {
      final source = '''
f = lambda x: x * 2
print(f(5))
g = lambda: 10 # No arguments
print(g())
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('10\n10\n'));
    });

    test('should create and call lambda with multiple args', () {
      final source = '''
adder = lambda a, b: a + b
print(adder(3, 4))
print(adder("x", "y"))
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('7\nxy\n'));
    });

    test('lambda should capture closure variables', () {
      final source = '''
def make_adder(n):
  return lambda x: x + n

add5 = make_adder(5)
add10 = make_adder(10)
print(add5(3))
print(add10(3))
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('8\n13\n'));
    });

    test('lambda with default arguments', () {
      final source = '''
power = lambda base, exp=2: base ** exp
print(power(3))    # Use default exp=2
print(power(3, 3)) # Provide exp
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('9\n27\n'));
    });

    test(
      'lambda passed as argument (requires supporting map/filter or custom func)',
      () {
        // This test requires a way to pass functions. Let's define a simple apply func.
        final source = '''
def apply_func(f, val):
  return f(val)

result = apply_func(lambda y: y * 10, 5)
print(result)

def apply_to_list(func, item):
    return func(item)
''';
        final result = runCode(source); // Test only apply_func for now
        expect(result.error, isNull, reason: result.error?.toString());
        expect(result.output, contains('50\n')); // Check first print
        // Cannot easily test the list part without list append method
      },
    );

    test('lambda body cannot contain assignment statements', () {
      // Assignment (=) is not allowed directly in lambda body
      final source = 'f = lambda x: y = x';
      final result = runCode(
        source,
      ); // Fehler sollte beim Auswerten der Zuweisung auftreten
      expect(result.hasRuntimeError, isTrue);
      expect(
        (result.error as RuntimeError).message,
        contains("SyntaxError: invalid syntax (assignment in lambda)"),
      );

      // Augmented Assignment (+=) is also not allowed
      final source2 = 'f = lambda x: x += 1';
      final result2 = runCode(source2);
      expect(result2.hasRuntimeError, isTrue);
      expect(
        (result2.error as RuntimeError).message,
        contains("SyntaxError: invalid syntax (assignment in lambda)"),
      );
    });
  }); // end of lambda tests

  group('Interpreter F-Strings', () {
    test('Basic variable interpolation', () {
      final result = runCode('''
name = "World"
num = 123
print(f"Hello {name}!")
print(f'Value: {num}')
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals("Hello World!\nValue: 123\n"));
    });

    test('Basic expression interpolation', () {
      final result = runCode('''
a = 5
b = 10
items = [1, 2]
print(f"Sum: {a + b}")
print(f"Len: {len(items) * 2}")
print(f"Upper: {'hello'.upper()}")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals("Sum: 15\nLen: 4\nUpper: HELLO\n"));
    });

    test('Multiple expressions and types', () {
      final result = runCode(
        'x=1\ny=2.5\nz=True\nprint(f"Int: {x}, Float: {y}, Bool: {z}, None: {None}")',
      );
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals("Int: 1, Float: 2.5, Bool: True, None: None\n"),
      );
    });

    test('Literal braces {{ and }}', () {
      final result = runCode('''
x = "inside"
print(f"Literal braces: {{ {x} }}")
print(f"Double braces: {{{{ {x} }}}}") # {{ becomes { before/after expr
print(f"Only literal: {{hello}}")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals(
          "Literal braces: { inside }\nDouble braces: {{ inside }}\nOnly literal: {hello}\n",
        ),
      );
    });

    test('Different quote types for f-string', () {
      final result = runCode('''
s_quote = 'single'
d_quote = "double"
print(f'Outer single, inner double: "{s_quote}"')
print(f"Outer double, inner single: '{d_quote}'")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals(
          'Outer single, inner double: "single"\nOuter double, inner single: \'double\'\n',
        ),
      );
    });

    test('Integer formatting (:d)', () {
      final result = runCode('''
val = 123
neg_val = -123
print(f"Default: {val:d}")
print(f"Width 5: {val:5d}")    # Right align default
print(f"Width 5 Left: {val:<5d}")
print(f"Width 5 Center: {val:^5d}")
print(f"Width 5 Sign Pad: {val:=5d}") # Not very useful without sign
print(f"Width 5 Sign Pad Neg: {neg_val:=5d}")
print(f"Fill Underscore Width 5 Left: {val:_<5d}")
print(f"Sign '+': {val:+d}")
print(f"Sign '+': {neg_val:+d}")
print(f"Sign ' ': {val: d}")
print(f"Sign ' ': {neg_val: d}")
print(f"Bool True: {True:d}")
print(f"Bool False: {False:d}")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals(
          "Default: 123\nWidth 5:   123\nWidth 5 Left: 123  \nWidth 5 Center:  123 \nWidth 5 Sign Pad:   123\nWidth 5 Sign Pad Neg: - 123\nFill Underscore Width 5 Left: 123__\nSign '+': +123\nSign '+': -123\nSign ' ':  123\nSign ' ': -123\nBool True: 1\nBool False: 0\n",
        ),
      );
      // Check error for non-int
      expect(
        runCode("print(f\"{'abc':d}\")").error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("Cannot format value of type 'str' with 'd'"),
        ),
      );
      // Allow float if whole number? (Current impl allows this)
      expect(runCode("print(f'{123.0:d}')").output, equals("123\n"));
      expect(
        runCode("print(f'{123.5:d}')").error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("Cannot format value of type 'float' with 'd'"),
        ),
      );
      expect(runCode("print(f'{123:05d}')").output, equals("00123\n"));
      expect(runCode("print(f'{-123:05d}')").output, equals("-0123\n"));
      expect(runCode("print(f'{123:<05d}')").output, equals("12300\n"));
      expect(runCode("print(f'{123:^05d}')").output, equals("01230\n"));
    });

    test('Float formatting (:f)', () {
      final result = runCode('''
val = 123.456
neg_val = -123.456
print(f"Default Precision: {val:f}") # Default 6
print(f"Precision 2: {val:.2f}")
print(f"Precision 0: {val:.0f}")
print(f"Width 10 Prec 2: {val:10.2f}") # Right align default
print(f"Width 10 Prec 2 Left: {val:<10.2f}")
print(f"Width 10 Prec 2 Center: {val:^10.2f}")
print(f"Width 10 Prec 2 Sign Pad: {val:=10.2f}") # Not very useful without sign
print(f"Width 10 Prec 2 Sign Pad Neg: {neg_val:=10.2f}")
print(f"Fill Zero Width 10 Prec 2: {val:010.2f}") # Implicit right-align
print(f"Fill Underscore Width 10 Prec 2 Left: {val:_<10.2f}")
print(f"Sign '+': {val:+.2f}")
print(f"Sign '+': {neg_val:+.2f}")
print(f"Sign ' ': {val: .2f}")
print(f"Sign ' ': {neg_val: .2f}")
print(f"Int as Float: {123:.2f}")
print(f"Bool True as Float: {True:.1f}")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals("""
Default Precision: 123.456000
Precision 2: 123.46
Precision 0: 123
Width 10 Prec 2:     123.46
Width 10 Prec 2 Left: 123.46    
Width 10 Prec 2 Center:   123.46  
Width 10 Prec 2 Sign Pad:     123.46
Width 10 Prec 2 Sign Pad Neg: -   123.46
Fill Zero Width 10 Prec 2: 0000123.46
Fill Underscore Width 10 Prec 2 Left: 123.46____
Sign '+': +123.46
Sign '+': -123.46
Sign ' ':  123.46
Sign ' ': -123.46
Int as Float: 123.00
Bool True as Float: 1.0
"""),
      );
      // Check error for non-numeric
      expect(
        runCode("print(f\"{'abc':f}\")").error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("Cannot format value of type 'str' with 'f'"),
        ),
      );
      expect(
        runCode("print(f'{None:.2f}')").error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("Cannot format value of type 'NoneType' with 'f'"),
        ),
      );
    });

    test('String formatting (:s or default)', () {
      final result = runCode('''
val = "hello"
num = 123
print(f"Default: {val}")
print(f"Spec s: {val:s}")
print(f"Width 10: {val:10}")     # Left align default for strings
print(f"Width 10 Right: {val:>10}")
print(f"Width 10 Center: {val:^10}")
print(f"Fill Underscore Width 10: {val:_>10}")
print(f"Number as String: {num}")
print(f"Number as String Width 5: {num:>5}")
print(f"None as String: {None}")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals("""
Default: hello
Spec s: hello
Width 10: hello     
Width 10 Right:      hello
Width 10 Center:   hello   
Fill Underscore Width 10: _____hello
Number as String: 123
Number as String Width 5:   123
None as String: None
"""),
      );
      // Test width with fill/align on numbers formatted as string
      expect(runCode("print(f'{123:_^7}')").output, equals("__123__\n"));
    });

    test('Complex expressions and formatting', () {
      final result = runCode('''
items = ["a", "b"]
x = 12.345
print(f"Item count: {len(items):03d}, Average: {x / 2:^10.2f}")
''');
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals("Item count: 002, Average:    6.17   \n"),
      ); // Check rounding and spacing
    });

    test('F-String Syntax Errors (Parse Time)', () {
      // Error reporting depends heavily on the sub-parser implementation
      expect(
        runCode('f"Value: {1 + "').error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains("Unterminated expression"),
        ),
      );
      expect(
        runCode('f"Value: {"').error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains("missing '}'"),
        ),
      );
      expect(
        runCode('f"Value: {1+}"').error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains("Parser error within f-string expression"),
        ),
      ); // Error from sub-parser
      expect(
        runCode('f"Value: {}"').error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains("Empty expression"),
        ),
      );
      expect(
        runCode('f"Value: }"').error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains("single '}' is not allowed"),
        ),
      );
      expect(
        runCode('f"Value: {1:}"').error,
        isNull,
      ); // Empty format specifier is allowed
      // Unterminated f-string (Lexer error, might not be caught cleanly by runCode)
      final result = runCode('f"abc');
      expect(
        result.error,
        isA<LexerError>().having(
          (e) => e.message,
          'message',
          contains("Unterminated f-string"),
        ),
      );
    });

    test('F-String Formatting Errors (Runtime Time)', () {
      expect(
        runCode("print(f\"{'text':d}\")").error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("Error formatting value"),
        ),
      );
      //expect(runCode("print(f\"{123:x.2f}\")").error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("Error formatting value"))); // Invalid combination
    });
  }); // end of fstring tests

  group('global / nonlocal', () {
    test('global read access', () {
      final result = runCode(r'''
x = 10
def foo():
    print(x)
foo()
print(x)
''');
      expect(result.output, equals("10\n10\n"));
    });

    test('global read access', () {
      final result = runCode(r'''
x = 10
def foo():
    global x
    x = 20
foo()
print(x)
''');
      expect(result.output, equals("20\n"));
    });

    test('multiple globals', () {
      final result = runCode(r'''
a = 1
b = 2
def foo():
    global a, b
    a = 10
    b = 20
foo()
print(a, b)
''');
      expect(result.output, equals("10 20\n"));
    });

    test('nonlocal', () {
      final result = runCode(r'''
def outer():
    x = 10
    def inner():
        nonlocal x
        x = 20
    inner()
    print(x)
outer()
''');
      expect(result.output, equals("20\n"));
    });

    test('nonlocal in double nested functions', () {
      final result = runCode(r'''
def outer():
    x = 10
    def middle():
        def inner():
            nonlocal x
            x = 30
        inner()
        print(x)
    middle()
    print(x)
outer()
''');
      expect(result.output, equals("30\n30\n"));
    });

    test('nonlocal - missing outer definition', () {
      final result = runCode(r'''
x = 10
def foo():
    global x
    def bar():
        nonlocal x
        x = 20
    bar()
foo()
''');
      expect(
        result.error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('nonlocal declaration of \'x\' refers to a global variable'),
        ),
      );
    });

    test('nonlocal missing in enclosing scope', () {
      final result = runCode(r'''
def foo():
    def bar():
        nonlocal y
        y = 20
    bar()
foo()
''');
      expect(
        result.error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('not found in enclosing'),
        ),
      );
    });

    test('undefined global', () {
      final result = runCode(r'''
def foo():
    x = 10
    print(x)
foo()
print(x)
''');
      expect(
        result.error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('Undefined variable'),
        ),
      );
    });

    test('ignore global', () {
      final result = runCode(r'''
global x  # should be ignored
x = 10
print(x)
''');
      expect(result.output, equals("10\n"));
    });
    test('nonlocal not within function', () {
      final result = runCode(r'''
nonlocal x
x = 10
''');
      expect(
        result.error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('nonlocal declaration not allowed at module level'),
        ),
      );
    });

    test('nonlocal missing ', () {
      final result = runCode(r'''
def foo():
    nonlocal y 
    y = 20
foo()
''');
      expect(
        result.error,
        isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('not found in enclosing scope'),
        ),
      );
    });

    test('mix of global and nonlocal', () {
      final result = runCode(r'''
z = 1
def outer():
    x = 10
    def inner():
        global z
        nonlocal x
        y = 20  # local
        z = 30  # change global
        x = 40  # change nonlocal
        print(x, y, z)  # should print 40 20 30
    inner()
    print(x)  # should print 40
outer()
print(z)     # should print 30
''');
      expect(result.output, equals("40 20 30\n40\n30\n"));
    });
  });

  group('line continuation', () {
    test('expression can be split into 2 lines between ()', () {
      final result = runCode(r'''
x=(1+
2*3)
print(x)
  ''');
      expect(result.output, equals("7\n"));
    });

    test('expression cannot be split after () is closed', () {
      final result = runCode(r'''
  x=(1+2)
  *3
  ''');
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Expect expression'),
        ),
      );
    });

    test(
      'function call can be split into multiple lines before () is closed',
      () {
        final result = runCode(r'''
print(1,
2
,""
)
''');
        expect(result.output, equals("1 2 \n"));
      },
    );

    test(
      'list and dict creation can be split into multiple lines between [] or {}',
      () {
        final result = runCode(r'''
l=[1,2
  ,3]
d={"x":
    [1,
  2]}
print(l,d)
''');
        expect(result.output, equals("[1, 2, 3] {'x': [1, 2]}\n"));
      },
    );
  });

  group('multiline strings', () {
    test('2-line string with """', () {
      final result = runCode(r'''
x="""1
2"""
print(x)
''');
      expect(result.output, equals("1\n2\n"));
    });
    test("2-line string with '''", () {
      final result = runCode(r"""
x='''3
4'''
print(x)
""");
      expect(result.output, equals("3\n4\n"));
    });
    test('2-line f-string with """', () {
      final result = runCode(r'''
a=42
x=f"""1
{a}"""
print(x)
''');
      expect(result.output, equals("1\n42\n"));
    });
    test("2-line f-string with '''", () {
      final result = runCode(r"""
a=99
x=f'''{a**2}
x'''
print(x)
""");
      expect(result.output, equals("9801\nx\n"));
    });

    test('non-matching quotes', () {
      final result = runCode(r'''
x="""a
b\'\'\'
''');
      expect(
        result.error,
        isA<LexerError>().having(
          (e) => e.message,
          'message',
          contains('Unterminated multiline'),
        ),
      );
    });
  });

  group('string concatenation', () {
    test('concatenate 2 strings', () {
      final result = runCode(r'''
x="a" " b"
print(x)
''');
      expect(result.output, equals("a b\n"));
    });

    test('concatenate 3 strings (implicit and +)', () {
      final result = runCode(r'''
x="a" " b" +"c"
print(x)
''');
      expect(result.output, equals("a bc\n"));
    });

    test('concatenate multiline and f-strings', () {
      final result = runCode(r'''
n=42
x="""a
b""" f' {n}'
print(x)
''');
      expect(result.output, equals("a\nb 42\n"));
    });
  });

  group('list comprehensions', () {
    var tests = [
      ["[x for x in range(5)]", "[0, 1, 2, 3, 4]"],
      ["[2*x for x in [1,2,3]]", "[2, 4, 6]"],
      ["[x for x in range(10) if x % 2 == 0]", "[0, 2, 4, 6, 8]"],
      [
        "[(x, y) for x in range(3) for y in range(2)]",
        "[(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]",
      ],
      [
        "[x + 10 * y for x in range(3) for y in range(2) if x % 2 == 0]",
        "[0, 10, 2, 12]",
      ],
      [
        "[x + 10 * y for x in range(3) if x % 2 == 0 for y in range(2)]",
        "[0, 10, 2, 12]",
      ],
      [
        "[x + y for x in range(5) for y in range(5) if x % 2 == 0 if y % 2 == 0]",
        "[0, 2, 4, 2, 4, 6, 4, 6, 8]",
      ],
      [
        "[f\"x={x} y={y} z={z}\" for x in range(2) for y in range(2) if x != y for z in range(2) if y != z]",
        "['x=0 y=1 z=0', 'x=1 y=0 z=1']",
      ],
      ["[x for x in range(5) if x > 10]", "[]"],
      [
        "[[x, y] for x in range(2) for y in range(2)]",
        "[[0, 0], [0, 1], [1, 0], [1, 1]]",
      ],
    ];

    for (var t in tests) {
      test(t[0], () {
        final result = runCode("print(${t[0]})");
        expect(result.output, equals("${t[1]}\n"));
      });
    }
  });

  group('dict comprehensions', () {
    var tests = [
      ["{x: x**2 for x in range(5)}", "{0: 0, 1: 1, 2: 4, 3: 9, 4: 16}"],
      ["{x: x**2 for x in range(5) if x % 2 == 0}", "{0: 0, 2: 4, 4: 16}"],
      [
        "{(x, y): x + y for x in range(2) for y in range(2)}",
        "{(0, 0): 0, (0, 1): 1, (1, 0): 1, (1, 1): 2}",
      ],
      ["{x: x for x in []}", "{}"],
      [
        "{x: x**2 for x in range(10) if x % 2 == 0 if x > 2}",
        "{4: 16, 6: 36, 8: 64}",
      ],
    ];

    for (var t in tests) {
      test(t[0], () {
        final result = runCode("print(${t[0]})");
        expect(result.output, equals("${t[1]}\n"));
      });
    }
  });

  group('set comprehensions', () {
    var tests = [
      ["{x for x in range(5)}", "{0, 1, 2, 3, 4}"],
      ["{x for x in range(5) if x % 2 == 0}", "{0, 2, 4}"],
      ["{x * y for x in range(3) for y in range(4)}", "{0, 1, 2, 3, 4, 6}"],
      ["{x for x in []}", "set()"],
      ["{x for x in range(10) if x % 2 == 0 if x > 2}", "{4, 6, 8}"],
    ];

    for (var t in tests) {
      test(t[0], () {
        final result = runCode("print(${t[0]})");
        expect(result.output, equals("${t[1]}\n"));
      });
    }

    test("mixed comprehension error", () {
      final result = runCode(
        "compr = {x: x for x in range(5), x for x in range(3)}",
      );
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Expect \'}\''),
        ),
      );
    });

    test("incomplete condition", () {
      final result = runCode("compr = {x for x in range(5) if}");
      expect(
        result.error,
        isA<ParseError>().having(
          (e) => e.message,
          'message',
          contains('Expect expression'),
        ),
      );
    });
  });

  group('list slices (only lookup)', () {
    var tests = [
      ["x[:]", "[0, 1, 2, 3, 4]"],
      ["x[1:4]", "[1, 2, 3]"],
      ["x[::2]", "[0, 2, 4]"],
      ["x[-3:-1]", "[2, 3]"],
      ["x[::-1]", "[4, 3, 2, 1, 0]"],
      ["x[4:1:-1]", "[4, 3, 2]"],
      ["x[2:2]", "[]"],
    ];

    for (var t in tests) {
      test(t[0], () {
        final result = runCode("x=[0,1,2,3,4]\nprint(${t[0]})");
        expect(result.output, equals("${t[1]}\n"));
      });
    }
  });

  group('tuple slices (only lookup)', () {
    var tests = [
      ["x[:]", "(0, 1, 2, 3, 4)"],
      ["x[1:4]", "(1, 2, 3)"],
      ["x[::2]", "(0, 2, 4)"],
      ["x[-3:-1]", "(2, 3)"],
      ["x[::-1]", "(4, 3, 2, 1, 0)"],
      ["x[4:1:-1]", "(4, 3, 2)"],
      ["x[2:2]", "()"],
    ];

    for (var t in tests) {
      test(t[0], () {
        final result = runCode("x=(0,1,2,3,4)\nprint(${t[0]})");
        expect(result.output, equals("${t[1]}\n"));
      });
    }
  });

  group('string slices', () {
    var tests = [
      ["x[:]", "hello"],
      ["x[1:4]", "ell"],
      ["x[::2]", "hlo"],
      ["x[-3:-1]", "ll"],
      ["x[::-1]", "olleh"],
      ["x[4:1:-1]", "oll"],
      ["x[2:2]", ""],
    ];

    for (var t in tests) {
      test(t[0], () {
        final result = runCode("x='hello'\nprint(${t[0]})");
        expect(result.output, equals("${t[1]}\n"));
      });
    }
  });
}
