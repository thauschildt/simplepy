## 1.3.1
- fixed tuple indexing
- extended `str.startswith()` and `str.endswith()` to accept a tuple of strings as first argument
- added `list.sort()`
- added `Exception` classes and exception handling
- added `isinstance` method

## 1.3.0 
- added `global`and `nonlocal`statements
- added single-line if/elif/else, for, while and def (e.g. `def f(x): return 42` without newline)
- enabled line continuation: Function calls, expressions or other code can now span multiple lines as long as there is an unclosed parenthesis `()` or `[]` or `{}`
- added multiline strings and multiline f-strings, e.g. `x="""2\n{3+4}"""`
- added implicit string and f-string concatenation (without + between string literals)
- added list/set/dict comprehensions
- added list/tuple/string slices (read only, no assignment so far)

## 1.2.1
- improve package description and fix linter warnings

## 1.2.0
- first public version

## Internal versions before publishing

### 1.1.5
- added f-strings: `[[fill]align][sign][0][width][.precision][dfs]`
  `#,` and types `b/o/x/e/g/%` are not yet supported.
- interpreter now returns value of last evaluated expression

### 1.1.4
- added set and tuple

### 1.1.3
- added built-in methods for list (but not `list.sort()` yet), dict, str

### 1.1.2
- added lambda functions

### 1.1.1
- added scientific float notation, e.g. 1.6e-19.

### 1.1.0
- added classes. Class attributes and multiple inheritance are not yet supported.

### 1.0.1
- accept 0x, 0b, 0o prefixes for integers
- added some built-in functions: len(), str(), repr(), int(), float(), bool(), type(), list(), dict(), abs(), round(), min(), max(), sum()

### 1.0.0

- Initial version.
