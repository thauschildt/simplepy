import 'package:simplepy/simplepy.dart';

void main() {
  String import = """
import test as xyz
from math import *
print(sqrt(2))
print(xyz.func("hello "))
""";

  final interpreter = Interpreter();

  interpreter.vfs["test.py"] = """
def func(x):
  return x*3
""";
  var tokens = Lexer(import).scanTokens();
  var stmts = Parser(tokens).parse();
  interpreter.interpret(stmts);
}
