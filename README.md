# simplepy

An interpreter for a subset of the Python language, written purely in Dart. It is intended for adding scripting capabilities to Dart projects and for educational purposes.

## Features
- Available python features:
  - Variable types: int (limited to dart int: &plusmn;1<<63 native ; &plusmn;1<<53 in web), float, bool, str, list, dict, NoneType
  - arithmetic operators: + - * / // ** % and bitwise operators
  - assignments: = += -= *= /= **= //= %=
  - comparisons: == > >= < <= !=
  - boolean operators: and, or, not
  - if, else, elif (newline after colon is required, in loops and function definitions as well)
  - for loops, while loops
  - functions (default arguments, *args, **kwargs are partially implemented), lambda functions
  - some built-in functions: print(), range(), len(), str(), repr(), int(), float(), bool(), type(), list(), dict(), abs(), round(), min(), max(), sum()
  - classes (no class attributes, no multiple inheritance)

- Missing python features:
  - import
  - tuples, sets
  - list comprehensions
  - list or string slices
  - list.append(), dict.keys() etc
  - file I/O
  - exceptions
  - decorators
  - async functions, generators
  - f-strings
  - input() and some other built-in functions
  - complex numbers
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

Basic types might behave differently in some cases compared to Python, for example, `print(1.0)` currently outputs 1 instead of 1.0.

Some more features (list.append() etc.) might be added soon,
but this will never become a full python interpreter.

Please report any errors (except for missing features, that are not mentioned as available) at the issue tracker.
