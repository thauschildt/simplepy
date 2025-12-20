# simplepy

An interpreter for a subset of the Python language, written purely in Dart. It is intended for adding scripting capabilities to Dart projects and for educational purposes.

## Features
- Available python features:
  - Variable types: `int`, `float`, `bool`, `str`, `list`, `dict`, `set`, `tuple`, `NoneType`
    <br>(some `dict` methods with limitations)
  - f-strings: `{value:[[fill]align][sign][0][width][.precision][dfs]}` ; `#,` and types `b/o/x/e/g/%` are not yet supported.
  - arithmetic operators: `+ - * / // ** %` and bitwise operators
  - assignments: `= += -= *= /= **= //= %=`
  - comparisons: `== > >= < <= !=`
  - boolean operators: `and`, `or`, `not`
  - `if`, `else`, `elif`
  - `for` loops, `while` loops
  - functions (default arguments, *args, **kwargs are partially implemented), `lambda` functions
  - some built-in functions: `print()`, `range()`, `len()`, `str()`, `repr()`, `int()`, `float()`, `bool()`,
  `type()`, `list()`, `dict()`, `set()`, `tuple()`, `abs()`, `round()`, `min()`, `max()`, `sum()`
  - classes (no class attributes, no multiple inheritance)
  - `global` and `nonlocal` variables


  Some more features might be added soon, but this will never become a full python interpreter.

- Missing python features:
  - `int` limited to dart int: &plusmn;1<<63 native ; &plusmn;1<<53 in web
  - `list.sort()` not yet implemented
  - `dict.key()`, `dict.values()`, `dict.items()` return list copies, not dynamic views as in Python
  - `str.startswith()`, `str.endswith()`: 1st argument can only be a single string for comparison, no tuple with alternatives
  - set operators `| & - ^ <= >=`
  - `import`
  - list comprehensions
  - list or string slices
  - file I/O
  - exceptions
  - decorators
  - async functions, generators
  - `input()` and some other built-in functions
  - complex numbers
  - multiple statements in one line separated by `;`
  - anything else not mentioned as available

## Usage

```dart
import 'package:simplepy/simplepy.dart';

void main() {
  String py = "print(3**4)";
  final tokens = Lexer(py).scanTokens();
  final stmts = Parser(tokens).parse();
  Interpreter().interpret(stmts);
}
```

## Additional information

Please report any errors (except for missing features, that are not mentioned as available) at the issue tracker.
