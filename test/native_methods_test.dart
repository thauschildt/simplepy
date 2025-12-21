// test/native_methods_test.dart
import 'package:simplepy/src/interpreter.dart';
import 'package:simplepy/src/lexer.dart';
import 'package:simplepy/src/parser.dart';
import 'package:test/test.dart';
import 'interpreter_classes_test.dart';

// Helper function to run SimplePy code and check results/errors
void runSimplePyTest(
  String code, {
  String? expectedOutput,
  Map<String, Object?>? expectedVariables,
  bool expectError = false,
  String? errorContains,
}) {
  final output = StringBuffer();
  Interpreter? interpreter; // Declare here to access globals later
  bool runtimeErrorOccurred = false;
  String runtimeErrorMessage = '';
  Exception? caughtError;

  void printCallback(String s) => output.write(s);

  void errorCallback(String message) {
    if (caughtError == null) {
        final match = RegExp(r"\[line (\d+), col (\d+)\].*near \'([^\']+)\'").firstMatch(message);
        Token errorToken = Token(TokenType.EOF, match?.group(3) ?? '?', null, int.tryParse(match?.group(1) ?? '0') ?? 0, int.tryParse(match?.group(2) ?? '0') ?? 0);
        runtimeErrorOccurred = true;
        caughtError = RuntimeError(errorToken, message);
    }
  }
  
  try {
    interpreter = Interpreter();
    final tokens = Lexer(code).scanTokens();
    final statements = Parser(tokens).parse();
    interpreter.interpret(statements, printCallback, errorCallback);
  } on LexerError catch (e) {
      fail('Test failed due to LexerError: $e\nCode:\n$code');
  } on ParseError catch (e) {
      fail('Test failed due to ParseError: $e\nCode:\n$code');
  } on RuntimeError catch (e) {
    runtimeErrorOccurred = true;
    runtimeErrorMessage = e.toString();
    if (!expectError) {
      fail('Expected success, but got RuntimeError: $e\nCode:\n$code');
    }
    if (errorContains != null && !runtimeErrorMessage.contains(errorContains)) {
      fail('Expected RuntimeError containing "$errorContains", but got: $runtimeErrorMessage\nCode:\n$code');
    }
  } catch (e, stackTrace) {
    // Catch any other unexpected errors
    fail('Test failed with unexpected error: $e\nStackTrace:\n$stackTrace\nCode:\n$code');
  }

  if (expectError && !runtimeErrorOccurred) {
    fail('Expected a RuntimeError, but none occurred.\nCode:\n$code');
  }

  if (expectError && errorContains!=null && !(caughtError! as RuntimeError).message.contains(errorContains)) {
    fail('Expected RuntimeError containing "$errorContains", but got: "$caughtError"\nCode:\n$code');
  }

  if (!expectError) {
    if (expectedOutput != null) {
      expect(output.toString(), expectedOutput, reason: 'Output mismatch for code:\n$code');
    }
    if (expectedVariables != null && interpreter != null) {
      expectedVariables.forEach((varName, expectedValue) {
        final actualValue = interpreter!.globals.values[varName];
        // Use deep comparison for lists/maps
        expect(actualValue, equals(expectedValue), reason: 'Variable "$varName" mismatch for code:\n$code');
      });
    }
  }
}

void main() {
  group('List Methods', () {
    test('list.append()', () {
      runSimplePyTest('''
l = [1, 2]
l.append(3)
l.append("a")
l.append(None)
l.append([4])
print(l)
''', expectedOutput: "[1, 2, 3, 'a', None, [4]]\n");
    });

    test('list.insert()', () {

      runSimplePyTest('''
l = ['a', 'c']
l.insert(0, 'x') # Start
l.insert(2, 'b') # Middle
l.insert(4, 'd') # End
l.insert(-1, 'y') # Before last
l.insert(-10, 'z') # Clamp to start
l.insert(10, 'w') # Clamp to end
l2 = []
l2.insert(0,'a')
print(l,l2)

''', expectedOutput: "['z', 'x', 'a', 'b', 'c', 'y', 'd', 'w'] ['a']\n");
      runSimplePyTest('l=[].insert("a", 1)', expectError: true, errorContains: 'TypeError');
    });

    test('list.remove()', () {
      runSimplePyTest('''
l = [1, 'a', 2, 'a', True, 1]
l.remove('a') # Remove first 'a'
l.remove(1)   # Remove first 1
l.remove(True) # Remove True (which is == 1)
print(l)
''', expectedOutput: "[2, 'a', 1]\n");
      runSimplePyTest("l=[1, 2].remove(3)", expectError: true, errorContains: 'ValueError');
      runSimplePyTest("l=[].remove(1)", expectError: true, errorContains: 'ValueError');
    });

    test('list.clear()', () {
       runSimplePyTest('l = [1, 2]\nl.clear()\nprint(l)', expectedOutput: "[]\n");
       runSimplePyTest('l = []\nl.clear()\nprint(l)', expectedOutput: "[]\n");
    });

    test('list.pop()', () {
      runSimplePyTest('''
l = [1, 2, 3, 4]
p1 = l.pop()    # Pop last
p2 = l.pop(0)   # Pop first
p3 = l.pop(-1)  # Pop new last
print(l,p1,p2,p3)
''', expectedOutput: "[2] 4 1 3\n");
      runSimplePyTest('l=[].pop()', expectError: true, errorContains: 'IndexError: pop from empty list');
      runSimplePyTest('l=[1].pop(1)', expectError: true, errorContains: 'IndexError: pop index out of range');
      runSimplePyTest('l=[1].pop(-2)', expectError: true, errorContains: 'IndexError: pop index out of range');
      runSimplePyTest('l=[1].pop("a")', expectError: true, errorContains: 'TypeError');
    });

     test('list.copy()', () {
      runSimplePyTest('''
l1 = [1, [2, 3]]
l2 = l1.copy()
l1.append(4)
l1[1].append(99) # Modify nested list
print(l1,l2)
''', expectedOutput: "[1, [2, 3, 99], 4] [1, [2, 3, 99]]\n"); // l2 shows shallow copy behaviour
    });

    test('list.count()', () {

      runSimplePyTest('''
l = [1, 'a', 1, [1], 1.0, True]
c1 = l.count(1)      # Counts int 1 and True (==1)
c2 = l.count(1.0)    # Counts float 1.0 (==1) and True
c3 = l.count('a')
c4 = l.count([1])
c5 = l.count(99)
c6 = [].count(1)
print(c1,c2,c3,c4,c5,c6)
''', expectedOutput: "3 3 1 1 0 0\n");
    });

     test('list.index()', () {
      runSimplePyTest('''
l = ['a', 'b', 'c', 'b', 'd']
i1 = l.index('b')       # First occurrence
i2 = l.index('b', 2)    # Start search after first 'b'
i3 = l.index('b', 1, 3) # Search in slice ['b', 'c']
i4 = l.index('d', -2)   # Search using negative start
# i5 = l.index('a', stop=-3) # Search 'a' in l[0:2]
''', expectedVariables: {'i1': 1, 'i2': 3, 'i3': 1, 'i4': 4, 'i5': null});
      runSimplePyTest("l=['a'].index('b')", expectError: true, errorContains: "ValueError: 'b' is not in list");
      runSimplePyTest("l=['a','b'].index('a', 1)", expectError: true, errorContains: "ValueError: 'a' is not in list");
      runSimplePyTest("l=['a'].index('a', [1])", expectError: true, errorContains: "TypeError"); // Non-int index
      runSimplePyTest("l=['a'].index('a', 0, 'a')", expectError: true, errorContains: "TypeError"); // Non-int index
    });

     test('list.reverse()', () {
      runSimplePyTest('l = [1, 2, 3]\nl.reverse()\nprint(l)', expectedOutput: "[3, 2, 1]\n");
      runSimplePyTest('l = [1, 2]\nl.reverse()\nprint(l)', expectedOutput: "[2, 1]\n");
      runSimplePyTest('l = [1]\nl.reverse()\nprint(l)', expectedOutput: "[1]\n");
      runSimplePyTest('l = []\nl.reverse()\nprint(l)', expectedOutput: "[]\n");
    });

  }); // End List Methods group

  group('Tuple Methods', () {
      // Tuples sind intern Listen, also testen wir auf diesen
      test('tuple.count()', () {
        runSimplePyTest('''
t = (1, 'a', 1, (1,), 1.0, True)
c1 = t.count(1)      # Counts int 1 and True (==1)
c2 = t.count(1.0)    # Counts float 1.0 (==1) and True
c3 = t.count('a')
c4 = t.count((1,)) # Needs PyTuple wrapper
c5 = t.count(99)
c6 = ().count(1)
''', expectedVariables: {'c1': 3, 'c2': 3, 'c3': 1, 'c4': 1, 'c5': 0, 'c6': 0});
        // Test type safety (assuming tuple methods are only looked up on PyTuple)
        expect(runCode('[].count(1)').error, isNull); // List method should work
      });

      test('tuple.index()', () {
        runSimplePyTest('''
t = ('a', 'b', 'c', 'b', 'd')
i1 = t.index('b')       # First occurrence
i2 = t.index('b', 2)    # Start search after first 'b'
i3 = t.index('b', 1, 3) # Search in slice ('b', 'c')
i4 = t.index('d', -2)   # Search using negative start
t_nested = (0, (1, 2), 3)
i5 = t_nested.index((1,2))
  ''', expectedVariables: {'i1': 1, 'i2': 3, 'i3': 1, 'i4': 4, 'i5': 1});
        runSimplePyTest("t=('a',).index('b')", expectError: true, errorContains: "ValueError: tuple.index(x): x not in tuple");
        runSimplePyTest("t=('a','b').index('a', 1)", expectError: true, errorContains: "ValueError: tuple.index(x): x not in tuple");
        runSimplePyTest("t=('a',).index('a', 1.0)", expectError: true, errorContains: "TypeError"); // Non-int index
        runSimplePyTest("t=('a',).index('a', 0, 'a')", expectError: true, errorContains: "TypeError"); // Non-int index
      });
    });

  group('Set Methods', () {
    test('set.add()', () {
      runSimplePyTest('''
s = {1, 'a'}
s.add(2)
s.add('a') # Already exists
s.add(True) # Same as 1
s_final = s
''', expectedVariables: {'s_final': {1, 'a', 2}}); // True == 1, 'a' duplicate ignored
       expect(runCode('s={1}\ns.add([])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("TypeError: unhashable type: 'list'")));
    });

    test('set.remove()', () {
      runSimplePyTest('''
s = {1, 'a', 2, True} # {1, 'a', 2}
s.remove('a')
s.remove(1) # Removes 1/True
s_final = s
''', expectedVariables: {'s_final': {2}});
       expect(runCode('s={1}\ns.remove(2)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("KeyError: 2")));
       expect(runCode('s=set()\ns.remove(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("KeyError: 1")));
       expect(runCode('s={1}\ns.remove([])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("TypeError: unhashable type: 'list'")));
    });

    test('set.discard()', () {
      runSimplePyTest('''
s = {1, 'a', 2, True} # {1, 'a', 2}
s.discard('a')
s.discard(1)
s.discard(99) # Not present, no error
s.discard([]) # Unhashable, no error (in Python)
s_final = s
''', expectedVariables: {'s_final': {2}});
       // Check no error for unhashable
       expect(runCode('s={1}\ns.discard([])').error, isNull);
    });

     test('set.pop()', () {
       // Order isn't guaranteed, so test behavior rather than exact element
       runSimplePyTest('''
s = {1, 2, 3}
popped = s.pop()
print(popped in [1, 2, 3]) # Check if it was one of the elements
print(len(s) == 2)         # Check if one element was removed
s.pop()
s.pop()
# Now s should be empty
print(len(s) == 0)
''', expectedOutput: "True\nTrue\nTrue\n");
       expect(runCode('set().pop()').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("KeyError: 'pop from an empty set'")));
    });

    test('set.clear()', () {
       runSimplePyTest('s = {1, 2}\ns.clear()', expectedVariables: {'s': <Object?>{}});
       runSimplePyTest('s = set()\ns.clear()', expectedVariables: {'s': <Object?>{}});
    });

    test('set.copy()', () {
      runSimplePyTest('''
s1 = {1, (2, 3)} # Use tuple
s2 = s1.copy()
s1.add(4)
print(s1 == {1, (2, 3), 4})
print(s2 == {1, (2, 3)})
''', expectedOutput: "True\nTrue\n");
    });

    test('set.union() / |', () {
      runSimplePyTest('''
s1 = {1, 2}
s2 = {2, 3}
s3 = {4}
u1 = s1.union(s2)
# u2 = s1 | s2 | s3 # Operator version
u3 = s1.union([3, 4]) # Union with list
u4 = s1.union(set())
u5 = set().union(s1)
''', expectedVariables: {
        'u1': {1, 2, 3},
        //'u2': {1, 2, 3, 4}, // Need to implement | operator
        'u3': {1, 2, 3, 4},
        'u4': {1, 2},
        'u5': {1, 2},
        });
       // Test operator if implemented
       //final resultOp = runCode('print({1, 2} | {2, 3})');
       //expect(resultOp.output.contains("{1, 2, 3}"), isTrue); // Output might be unordered

       expect(runCode('s={1}.union(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       expect(runCode('s={1}.union([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("unhashable type: 'list'")));
    });

     test('set.intersection() / &', () {
      runSimplePyTest('''
s1 = {1, 2, 3}
s2 = {2, 3, 4}
s3 = {5}
i1 = s1.intersection(s2)
# i2 = s1 & s2 & s3 # Operator version
i3 = s1.intersection([3, 4]) # Intersection with list
i4 = s1.intersection(set())
i5 = set().intersection(s1)
''', expectedVariables: {
        'i1': {2, 3},
        // 'i2': <Object?>{}, // Need to implement & operator
        'i3': {3},
        'i4': <Object?>{},
        'i5': <Object?>{},
        });
        // Test operator if implemented
       //final resultOp = runCode('print({1, 2, 3} & {2, 4})');
       //expect(resultOp.output.contains("{2}"), isTrue);

       expect(runCode('s={1}.intersection(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       expect(runCode('s={1}.intersection([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("unhashable type: 'list'")));

    });

     test('set.difference() / -', () {
      runSimplePyTest('''
s1 = {1, 2, 3}
s2 = {2, 3, 4}
s3 = {1}
d1 = s1.difference(s2)
# d2 = s1 - s2 - s3 # Operator version
d3 = s1.difference([3, 4]) # Difference with list
d4 = s1.difference(set())
d5 = set().difference(s1)
''', expectedVariables: {
        'd1': {1},
        // 'd2': <Object?>{}, // Need to implement - operator
        'd3': {1, 2},
        'd4': {1, 2, 3},
        'd5': <Object?>{},
        });
       // Test operator if implemented
       //final resultOp = runCode('print({1, 2, 3} - {2, 4})');
       //expect(resultOp.output.contains("{1, 3}"), isTrue);

       expect(runCode('s={1}.difference(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       // Difference does not require elements in other to be hashable
       expect(runCode('s={1}.difference([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('unhashable type')));
    });

    test('set.isdisjoint()', () {
      runSimplePyTest('''
b1 = {1, 2}.isdisjoint({3, 4}) # True
b2 = {1, 2}.isdisjoint({2, 3}) # False
b3 = {1, 2}.isdisjoint([3, 4]) # True (with list)
b4 = {1, 2}.isdisjoint([])    # True
b5 = set().isdisjoint({1})     # True
b6 = set().isdisjoint(set())   # True
''', expectedVariables: {'b1': true, 'b2': false, 'b3': true, 'b4': true, 'b5': true, 'b6': true});
       expect(runCode('s={1}.isdisjoint(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       expect(runCode('s={1}.isdisjoint([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("unhashable type: 'list'"))); // isdisjoint requires hashable
    });

    test('set.issubset() / <=', () {
      runSimplePyTest('''
b1 = {1, 2}.issubset({1, 2, 3}) # True
b2 = {1, 2}.issubset({1, 2})    # True
b3 = {1, 2}.issubset({1})       # False
b4 = {1, 2}.issubset([1, 2, 3]) # True (with list)
b5 = set().issubset({1})        # True
b6 = set().issubset(set())      # True
b7 = {1}.issubset(set())        # False
''', expectedVariables: {'b1': true, 'b2': true, 'b3': false, 'b4': true, 'b5': true, 'b6': true, 'b7': false});
        // Test operator if implemented
        //expect(runCode('print({1, 2} <= {1, 2, 3})').output.contains('True'), isTrue);
        //expect(runCode('print({1, 4} <= {1, 2, 3})').output.contains('False'), isTrue);

       expect(runCode('s={1}.issubset(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       expect(runCode('s={1}.issubset([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("unhashable type: 'list'")));

    });

     test('set.issuperset() / >=', () {
       runSimplePyTest('''
b1 = {1, 2, 3}.issuperset({1, 2}) # True
b2 = {1, 2}.issuperset({1, 2})    # True
b3 = {1}.issuperset({1, 2})       # False
b4 = {1, 2, 3}.issuperset([1, 2]) # True (with list)
b5 = {1}.issuperset(set())        # True
b6 = set().issuperset(set())      # True
b7 = set().issuperset({1})        # False
''', expectedVariables: {'b1': true, 'b2': true, 'b3': false, 'b4': true, 'b5': true, 'b6': true, 'b7': false});
        // Test operator if implemented
        //expect(runCode('print({1, 2, 3} >= {1, 2})').output.contains('True'), isTrue);
        //expect(runCode('print({1, 2} >= {1, 3})').output.contains('False'), isTrue);

       expect(runCode('s={1}.issuperset(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       expect(runCode('s={1}.issuperset([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("unhashable type: 'list'")));
    });

    test('set.update() / |=', () {
       runSimplePyTest('''
s = {1, 2}
s.update({2, 3})
s.update([3, 4]) # Update with list
s.update("ab")   # Update with string
s.update(set())  # Update with empty
s_final = s
''', expectedVariables: {'s_final': {1, 2, 3, 4, 'a', 'b'}});
        // Test operator if implemented
       //runSimplePyTest('s={1}; s |= {2}; print(s)', expectedOutput: '{1, 2}\n');

       expect(runCode('s={1}.update(1)').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains('is not iterable')));
       expect(runCode('s={1}.update([[]])').error, isA<RuntimeError>().having((e)=>e.message, 'message', contains("unhashable type: 'list'")));
    });

  });
    
  group('Dictionary Methods', () {
    test('dict.keys()', () {
      runSimplePyTest('k = {"a": 1, "b": 2}.keys()\nprint(k)', expectedOutput: "['a', 'b']\n");
      runSimplePyTest('k = {}.keys()\nprint(k)', expectedOutput: "[]\n");
      // Test order might not be guaranteed, but often follows insertion
      runSimplePyTest('k = {1: "a", 0: "b"}.keys()\nprint(k)', expectedOutput: "[1, 0]\n");
    });

     test('dict.values()', () {
      runSimplePyTest('v = {"a": 1, "b": 2}.values()\nprint(v)', expectedOutput: "[1, 2]\n");
      runSimplePyTest('v = {}.values()\nprint(v)', expectedOutput: "[]\n");
      runSimplePyTest('v = {1: "a", 0: "b"}.values()\nprint(v)', expectedOutput: "['a', 'b']\n");
    });

    test('dict.items()', () {
      runSimplePyTest('i = {"a": 1, "b": 2}.items()\nprint(i)', expectedOutput: "[['a', 1], ['b', 2]]\n");
      runSimplePyTest('i = {}.items()\nprint(i)', expectedOutput: "[]\n");
      runSimplePyTest('i = {1: "a", 0: "b"}.items()\nprint(i)', expectedOutput: "[[1, 'a'], [0, 'b']]\n");
    });

    test('dict.get()', () {
      runSimplePyTest('''
d = {'a': 1}
v1 = d.get('a')
v2 = d.get('b')       # Key not found -> None
v3 = d.get('b', 99)   # Key not found -> default
v4 = d.get('a', 99)   # Key found -> value (not default)
v5 = {}.get('a')
v6 = {}.get('a', 100)
''', expectedVariables: {'v1': 1, 'v2': null, 'v3': 99, 'v4': 1, 'v5': null, 'v6': 100});
      // Test with unhashable key (should return default or None)
      runSimplePyTest("v = {'a':1}.get([])", expectedVariables: {'v': null});
      runSimplePyTest("v = {'a':1}.get([], 'default')", expectedVariables: {'v': 'default'});
    });

    test('dict.pop()', () {
      runSimplePyTest('''
d = {'a': 1, 'b': 2}
p1 = d.pop('a')
p2 = d.pop('c', 99) # Key not found -> default
p3 = d.pop('b')
''', expectedVariables: {'d': {}, 'p1': 1, 'p2': 99, 'p3': 2});
       runSimplePyTest("d={'a':1}.pop('b')", expectError: true, errorContains: "KeyError: 'b'");
       runSimplePyTest("{}.pop('a')", expectError: true, errorContains: "KeyError: 'a'");
       runSimplePyTest("d={'a':1}.pop([])", expectError: true, errorContains: "TypeError: unhashable type");
       runSimplePyTest("d={'a':1}.pop([], 'default')", expectError: true, errorContains: "TypeError: unhashable type");
    });

     test('dict.clear()', () {
       runSimplePyTest('d = {"a": 1}\nd.clear()', expectedVariables: {'d': {}});
       runSimplePyTest('d = {}\nd.clear()', expectedVariables: {'d': {}});
    });

    test('dict.copy()', () {
      runSimplePyTest('''
d1 = {'a': [1, 2]}
d2 = d1.copy()
d1['b'] = 3
d1['a'].append(99) # Modify nested list
print(d1,d2)
''', expectedOutput: "{'a': [1, 2, 99], 'b': 3} {'a': [1, 2, 99]}\n"); // d2 shows shallow copy
    });

     test('dict.update()', () {
      runSimplePyTest('''
d = {'a': 1}
d.update({'b': 2, 'a': 100}) # Update with map
d.update([['c', 3], ['d', 4]]) # Update with list of pairs
d.update() # Update with no args
d2 = {}
d2.update(d)
''', expectedVariables: {'d': {'a': 100, 'b': 2, 'c': 3, 'd': 4}, 'd2': {'a': 100, 'b': 2, 'c': 3, 'd': 4}});
       runSimplePyTest("{'a':1}.update([['b', 2], ['c']])", expectError: true, errorContains: 'ValueError: dictionary update sequence element #1 has length 1; 2 is required'); // Invalid pair
       runSimplePyTest("{'a':1}.update([[]])", expectError: true, errorContains: 'ValueError: dictionary update sequence element #0 has length 0; 2 is required'); // Invalid pair
       runSimplePyTest("{'a':1}.update(123)", expectError: true, errorContains: "TypeError: 'int' object is not iterable");
       runSimplePyTest("{'a':1}.update([[['unhashable'] ,1]])", expectError: true, errorContains: "TypeError: unhashable type: 'list'"); // Unhashable key
    });

  }); // End Dictionary Methods group

  group('String Methods', () {
     test('str.find()', () {
      runSimplePyTest('''
s = "abcabc"
f1 = s.find("b")
f2 = s.find("b", 2)     # Start after first 'b'
f3 = s.find("abc", 1)
f4 = s.find("x")        # Not found
f5 = s.find("a", -3)    # Negative start
f6 = s.find("c", 0, 3)  # Slice [0:3] -> "abc"
f7 = s.find("c", 0, 2)  # Slice [0:2] -> "ab" (not found)
f8 = "".find("a")
f9 = "abc".find("")     # Empty string found at start
f10 = "abc".find("", 1) # Empty string found at start 1
f11 = "abc".find("", 4) # Empty string found at end+1
''', expectedVariables: {'f1': 1, 'f2': 4, 'f3': 3, 'f4': -1, 'f5': 3, 'f6': 2, 'f7': -1, 'f8': -1, 'f9': 0, 'f10': 1, 'f11': 3});
       runSimplePyTest("s='abc'.find(1)", expectError: true, errorContains: 'TypeError: must be str');
       runSimplePyTest("s='abc'.find('a', 'b')", expectError: true, errorContains: 'TypeError');
    });

    test('str.count()', () {
      runSimplePyTest('''
s = "abababab"
c1 = s.count("ab")
c2 = s.count("ab", 1)    # Start at index 1
c3 = s.count("ab", 0, 4) # Slice [0:4] -> "abab"
c4 = s.count("b", 1, 5)  # Slice [1:5] -> "baba"
c5 = s.count("x")
c6 = "".count("a")
c7 = "aaaa".count("aa")  # Overlapping
c8 = "abab".count("")    # Empty string count (len + 1)
c9 = "abab".count("", 1, 3) # Empty count in slice [1:3] -> "ba" (len+1 = 3)
''', expectedVariables: {'c1': 4, 'c2': 3, 'c3': 2, 'c4': 2, 'c5': 0, 'c6': 0, 'c7': 2, 'c8': 5, 'c9': 3});
       runSimplePyTest("s='abc'.count(1)", expectError: true, errorContains: 'TypeError: must be str');
       runSimplePyTest("s='abc'.count('a', 'b')", expectError: true, errorContains: 'TypeError');
    });

    test('str.replace()', () {
      runSimplePyTest('''
s = "abracadabra"
r1 = s.replace("a", "X")       # Replace all
r2 = s.replace("a", "X", 2)   # Replace first 2
r3 = s.replace("abra", "Z")
r4 = s.replace("x", "Y")      # Substring not found
r5 = s.replace("a", "")       # Replace with empty
r6 = "".replace("a", "b")
r7 = "aaa".replace("a", "b", 0) # Count = 0
r8 = "aaa".replace("a", "b", -5) # Count < 0 (replace all)
''', expectedVariables: {
        'r1': "XbrXcXdXbrX", 'r2': "XbrXcadabra", 'r3': "ZcadZ", 'r4': "abracadabra",
        'r5': "brcdbr", 'r6': "", 'r7': "aaa", 'r8': "bbb" });
      runSimplePyTest("s='abc'.replace(1, 'a')", expectError: true, errorContains: 'TypeError');
      runSimplePyTest("s='abc'.replace('a', 1)", expectError: true, errorContains: 'TypeError');
      runSimplePyTest("s='abc'.replace('a', 'b', 'c')", expectError: true, errorContains: 'TypeError');
    });

     test('str.split()', () {
      // Default whitespace split
      runSimplePyTest("l = ' a  b c '.split()", expectedVariables: {'l': ['a', 'b', 'c']});
      runSimplePyTest("l = 'abc'.split()", expectedVariables: {'l': ['abc']});
      runSimplePyTest("l = ''.split()", expectedVariables: {'l': []});
      runSimplePyTest("l = '   '.split()", expectedVariables: {'l': []});
      // Specific separator
      runSimplePyTest("l = 'a,b,c'.split(',')", expectedVariables: {'l': ['a', 'b', 'c']});
      runSimplePyTest("l = 'a,,b'.split(',')", expectedVariables: {'l': ['a', '', 'b']});
      runSimplePyTest("l = ',a,'.split(',')", expectedVariables: {'l': ['', 'a', '']});
      runSimplePyTest("l = 'abc'.split('x')", expectedVariables: {'l': ['abc']});
      runSimplePyTest("l = ''.split(',')", expectedVariables: {'l': ['']});
      // Maxsplit
      runSimplePyTest("l = 'a b c d'.split(None, 1)", expectedVariables: {'l': ['a', 'b c d']});
      runSimplePyTest("l = ' a  b c d '.split(None, 2)", expectedVariables: {'l': ['a', 'b', 'c d']});
      runSimplePyTest("l = 'a,b,c,d'.split(',', 2)", expectedVariables: {'l': ['a', 'b', 'c,d']});
      runSimplePyTest("l = 'a,b,c'.split(',', 0)", expectedVariables: {'l': ['a,b,c']});
      runSimplePyTest("l = 'a,b,c'.split(',', -1)", expectedVariables: {'l': ['a', 'b', 'c']});
      runSimplePyTest("l = 'a,,b'.split(',', 1)", expectedVariables: {'l': ['a', ',b']});
      // Errors
      runSimplePyTest("'abc'.split(1)", expectError: true, errorContains: 'TypeError: must be str or None');
      runSimplePyTest("'abc'.split(',', 'a')", expectError: true, errorContains: 'TypeError');
      runSimplePyTest("'abc'.split('')", expectError: true, errorContains: 'ValueError: empty separator');
    });

    test('str.join()', () {
      runSimplePyTest("s = ','.join(['a', 'b', 'c'])", expectedVariables: {'s': 'a,b,c'});
      runSimplePyTest("s = ' '.join(['hello', 'world'])", expectedVariables: {'s': 'hello world'});
      runSimplePyTest("s = ''.join(['a', 'b', 'c'])", expectedVariables: {'s': 'abc'});
      runSimplePyTest("s = ','.join([])", expectedVariables: {'s': ''});
      runSimplePyTest("s = ','.join('abc')", expectedVariables: {'s': 'a,b,c'}); // Joining a string
       // Errors
      runSimplePyTest("','.join([1, 2])", expectError: true, errorContains: 'TypeError: sequence item 0: expected str instance');
      runSimplePyTest("','.join({})", expectError: true, errorContains: 'TypeError: can only join an iterable of strings'); // Non-iterable or wrong type
    });

    test('str.upper() / str.lower()', () {
      runSimplePyTest("u = 'abc'.upper()", expectedVariables: {'u': 'ABC'});
      runSimplePyTest("u = 'AbC'.upper()", expectedVariables: {'u': 'ABC'});
      runSimplePyTest("u = '123'.upper()", expectedVariables: {'u': '123'});
      runSimplePyTest("u = ''.upper()", expectedVariables: {'u': ''});
      runSimplePyTest("l = 'ABC'.lower()", expectedVariables: {'l': 'abc'});
      runSimplePyTest("l = 'aBc'.lower()", expectedVariables: {'l': 'abc'});
      runSimplePyTest("l = '123'.lower()", expectedVariables: {'l': '123'});
      runSimplePyTest("l = ''.lower()", expectedVariables: {'l': ''});
    });

    test('str.startswith()', () {
      runSimplePyTest('''
s = "abcdef"
b1 = s.startswith("ab")
b2 = s.startswith("abc")
b3 = s.startswith("bc") # False
b4 = s.startswith("ab", 1) # False (starts search at 'b')
b5 = s.startswith("bc", 1) # True
b6 = s.startswith("cd", 2, 4) # True (slice "cd")
b7 = s.startswith("cd", 2, 3) # False (slice "c")
b8 = s.startswith("") # True
b9 = "".startswith("a") # False
b10= "".startswith("") # True
''', expectedVariables: {'b1': true, 'b2': true, 'b3': false, 'b4': false, 'b5': true, 'b6': true, 'b7': false, 'b8': true, 'b9': false, 'b10': true});
       runSimplePyTest("'abc'.startswith(1)", expectError: true, errorContains: 'TypeError: startswith first arg must be str');
       runSimplePyTest("'abc'.startswith('a', 'b')", expectError: true, errorContains: 'TypeError');
    });

    test('str.endswith()', () {
       runSimplePyTest('''
s = "abcdef"
b1 = s.endswith("ef")
b2 = s.endswith("def")
b3 = s.endswith("de") # False
b4 = s.endswith("ef", 0, 5) # False (slice "abcde")
b5 = s.endswith("de", 0, 5) # True (slice "abcde")
b6 = s.endswith("bc", 1, 3) # True (slice "bc")
b7 = s.endswith("bc", 1, 2) # False (slice "b")
b8 = s.endswith("") # True
b9 = "".endswith("a") # False
b10= "".endswith("") # True
''', expectedVariables: {'b1': true, 'b2': true, 'b3': false, 'b4': false, 'b5': true, 'b6': true, 'b7': false, 'b8': true, 'b9': false, 'b10': true});
       runSimplePyTest("'abc'.endswith(1)", expectError: true, errorContains: 'TypeError: endswith first arg must be str');
       runSimplePyTest("'abc'.endswith('a', 'b')", expectError: true, errorContains: 'TypeError');
    });

    test('str.strip() / lstrip() / rstrip()', () {
      runSimplePyTest('''
s = "  spacious  "
s1 = s.strip()
s2 = s.lstrip()
s3 = s.rstrip()
s4 = "   ".strip()
s5 = "".strip()
''', expectedVariables: {'s1': 'spacious', 's2': 'spacious  ', 's3': '  spacious', 's4': '', 's5': ''});
      runSimplePyTest('''
s = "www.example.com"
s1 = s.strip("w.moc") # Strip chars 'w', '.', 'm', 'o', 'c'
s2 = s.lstrip("w.")
s3 = s.rstrip(".com")
s4 = "abc".strip("xyz") # No chars match
s5 = "aaa".strip("a")
s6 = "aba".strip("a")
''', expectedVariables: {'s1': 'example', 's2': 'example.com', 's3': 'www.example', 's4': 'abc', 's5': '', 's6': 'b'});
      runSimplePyTest("'abc'.strip(1)", expectError: true, errorContains: 'TypeError: must be str or None');
      runSimplePyTest("'abc'.lstrip([])", expectError: true, errorContains: 'TypeError: must be str or None');
      runSimplePyTest("'abc'.rstrip({})", expectError: true, errorContains: 'TypeError: must be str or None');
    });

  }); // End String Methods group
}