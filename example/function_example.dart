import 'package:simplepy/simplepy.dart';
import 'dart:math';

final random = Random();

// dart function to be executed when python "randint" is called
int randint(List args, Map kwargs) {
  int start = args[0], end = args[1];
  return start + random.nextInt(end - start + 1);
}

void main() {
  String pyx = """
for i in range(10):
  print(randint(1,6))
""";
  final tokens = Lexer(pyx).scanTokens();
  final stmts = Parser(tokens).parse();
  final inter = Interpreter();
  // define python "randint" function
  inter.registerFunction("randint", randint);
  inter.interpret(stmts);
}
