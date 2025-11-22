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
  group('Interpreter Classes and Methods', () {
    test('should define and instantiate a simple class', () {
      final source = '''
class Point:
  pass # Empty class

p1 = Point()
print(type(p1)) # Check instance type (basic string representation)
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        contains("<class 'Point'>"),
      ); // Output from type() or instance.toString()
    });

    test('should call __init__ on instantiation', () {
      final source = '''
class Greeter:
  def __init__(self, name):
    print("Initializing Greeter with", name)
    self.name = name # Set attribute

g = Greeter("World")
print("Name: "+g.name)
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, contains("Initializing Greeter with World"));
      expect(
        result.output,
        contains("Name: World"),
      ); // Check attribute access print
    });

    test('__init__ should return None implicitly', () {
      final source = '''
class Test:
    def __init__(self):
        self.val = 1
        return 10 # Explicit return in __init__ is ignored

t = Test()
print(type(t))
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, contains("<class 'Test'>"));
    });

    test('should set and get attributes', () {
      final source = '''
class Bag:
  pass

b = Bag()
b.item = "apple"
b.quantity = 5
print(b.item)
print(b.quantity * 2)
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('apple\n10\n'));
    });

    test('should define and call methods', () {
      final source = '''
class Counter:
  def __init__(self):
    self.count = 0
  def increment(self, amount=1):
    self.count += amount
    return self.count
  def get_count(self):
    return self.count

c = Counter()
c.increment()
c.increment(5)
print(c.get_count())
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output.trim(), equals('6')); // 0 + 1 + 5
    });

    test('method calls should bind self correctly', () {
      final source = '''
class Thing:
    def get_self(self):
        return self # Return the instance itself

t = Thing()
t2 = t.get_self()
print(t == t2) # Check if the same instance was returned
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output.trim(), equals('True'));
    });

    test('should handle simple inheritance (method lookup)', () {
      final source = '''
class Parent:
  def greet(self):
    print("Hello from Parent")

class Child(Parent):
  def farewell(self):
    print("Goodbye from Child")

c = Child()
c.greet() # Inherited method
c.farewell() # Own method
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('Hello from Parent\nGoodbye from Child\n'));
    });

    test('should handle method overriding', () {
      final source = '''
class Parent:
  def speak(self):
    print("Parent speaking")

class Child(Parent):
  def speak(self):
    print("Child speaking")

p = Parent()
c = Child()
p.speak()
c.speak()
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('Parent speaking\nChild speaking\n'));
    });

    test('should handle simple inheritance (method lookup)', () {
      final source = '''
class Parent:
  def greet(self):
    print("Hello from Parent")

class Child(Parent):
  def farewell(self):
    print("Goodbye from Child")

c = Child()
c.greet() # Inherited method
c.farewell() # Own method
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(result.output, equals('Hello from Parent\nGoodbye from Child\n'));
    });

    //      test('should handle multiple inheritance', () {
    //       final source = '''
    // class A:
    //   def test(self):
    //     print("A")
    // class B:
    //   def test(self):
    //     print("B")
    // class Child(A,B):
    //   pass
    // c=Child()
    // c.test()
    // ''';
    //       final result = runCode(source);
    //       expect(result.error, isNull, reason: result.error?.toString());
    //       expect(result.output, equals('A\n'));
    //     });

    test('should handle super() calls correctly', () {
      final source = '''
class Parent:
  def __init__(self, name):
    self.name = name
    print("Parent init:", name)
  def method(self):
      print("Parent method called by", self.name)
      return "parent_val"

class Child(Parent):
  def __init__(self, name, age):
    print("Child init start")
    super().__init__(name) # Call Parent's init
    self.age = age
    print("Child init end:", self.name, self.age)
  def method(self):
      print("Child method start")
      parent_result = super().method() # Call Parent's method
      print("Child method end, got:", parent_result)
      return "child_val"

c = Child("Alice", 30)
print(c.name, c.age)
result = c.method()
print("Final result:", result)
''';
      final result = runCode(source);
      expect(result.error, isNull, reason: result.error?.toString());
      expect(
        result.output,
        equals(
          "Child init start\n"
          "Parent init: Alice\n" // From super().__init__
          "Child init end: Alice 30\n"
          "Alice 30\n" // Print attributes
          "Child method start\n"
          "Parent method called by Alice\n" // From super().method()
          "Child method end, got: parent_val\n"
          "Final result: child_val\n",
        ),
      );
    });

    //      test('should handle attribute lookup through inheritance', () {
    //       final source = '''
    // class Base:
    //     base_attr = 100

    // class Derived(Base):
    //     pass

    // d = Derived()
    // print(d.base_attr) # Access attribute defined in base class
    // ''';
    //       // THIS REQUIRES class attributes and lookup logic not fully implemented above.
    //       // The current `get` only looks at instance fields then methods.
    //       // To pass this, PyInstance.get needs to check class attributes too.
    //       // For now, expect an error or implement class attributes.
    //       final result = runCode(source);
    //        expect(result.hasRuntimeError, isTrue); // Expect failure until class attrs implemented
    //        expect((result.error as RuntimeError).message, contains("AttributeError"));
    //     });

    test('should raise AttributeError for missing attributes/methods', () {
      final source = '''
class Simple:
  def method(self):
    pass
s = Simple()
print(s.non_existent_attribute)
''';
      final result = runCode(source);
      expect(
        (result.error as RuntimeError).message,
        contains(
          "AttributeError: 'Simple' object has no attribute 'non_existent_attribute'",
        ),
      );

      final source2 = '''
class Simple2:
  pass
s2 = Simple2()
s2.non_existent_method()
''';
      final result2 = runCode(source2);
      expect(
        (result2.error as RuntimeError).message,
        contains(
          "AttributeError: 'Simple2' object has no attribute 'non_existent_method'",
        ),
      );
    });

    test('should raise error when calling non-callable attribute', () {
      final source = '''
class Test:
    def __init__(self):
        self.data = 10
t = Test()
t.data() # Try calling an integer attribute
''';
      final result = runCode(source);
      expect(result.hasRuntimeError, isTrue);
      expect(
        (result.error as RuntimeError).message,
        contains("Object of type 'int' is not callable"),
      );
    });

    test('should raise error if superclass is not a class', () {
      final source = '''
var = 10
class C(var): # Inherit from an integer
    pass
''';
      final result = runCode(source);
      expect(result.hasRuntimeError, isTrue);
      expect(
        (result.error as RuntimeError).message,
        contains("Superclass must be a class."),
      );
    });

    test('should raise error using super() outside class method', () {
      final source = 'super().something()'; // Top level super
      final result = runCode(source);
      expect(
        (result.error as RuntimeError).message,
        contains("Undefined variable 'super'"),
      ); // Or similar based on Environment.getAtEnclosing failure
    });
  });
}
