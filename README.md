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
  - `for` loops, `while` loops (but `else:` block is not yet available)
  - `try`/`except`/`else`/`finally`
  - functions (default arguments, *args, **kwargs are partially implemented), `lambda` functions
  - some built-in functions: `print()`, `range()`, `len()`, `str()`, `repr()`, `int()`, `float()`, `bool()`,
  `type()`, `list()`, `dict()`, `set()`, `tuple()`, `abs()`, `round()`, `min()`, `max()`, `sum()`, `isinstance()`
  - list, dict and set comprehensions
  - list, string and tuple slices - read only
  - classes (no class attributes, no multiple inheritance)
  - `global` and `nonlocal` variables
  - limited file I/O: files can be created using `f=open(filename,mode)`. `mode` can be w,r,a,w+,r+,a+. No binary files.
    Available methods: `f.read(n)`, `f.readline(n)`, `f.readlines(n)`, `f.write(text)`, `f.writelines(list)`, `f.seek(position)`, `f.close()`.
    File contents are kept in memory in a dictionary as long as the Interpreter object exists.
    To make them persistent, you can access them from dart by `interpreter.vfs[filename]`.

  Some more features might be added soon, but this will never become a full python interpreter.

- Missing python features:
  - `dict.key()`, `dict.values()`, `dict.items()` return list copies, not dynamic views as in Python
  - set operators `| & - ^ <= >=` (but available as set1.union(set2)` etc.)
  - ternary conditional expressions
  - `:=`operator
  - `import`
  - slice assignments (like `x[5:10] = [1,2,3])`)
  - decorators
  - async functions, generators
  - `input()` and some other built-in functions
  - complex numbers
  - multiple statements in one line separated by `;`
  - dunder methods (`__xxx__`) except for `__init__`
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
