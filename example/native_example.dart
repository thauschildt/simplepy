import 'dart:math';

import 'package:simplepy/simplepy.dart';

Object? _pow(
  Interpreter interpreter,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  if (positionalArgs.length == 3) {
    try {
      BigInt base = (positionalArgs[0] as PyNum).intValue!;
      BigInt exp = (positionalArgs[1] as PyNum).intValue!;
      BigInt mod = (positionalArgs[2] as PyNum).intValue!;
      return PyNum.bigInt(base.modPow(exp, mod));
    } catch (e) {
      throw "TypeError: pow() 3rd argument not allowed unless all arguments are integers";
    }
  } else if (positionalArgs.length == 2) {
    PyNum base = positionalArgs[0] as PyNum;
    PyNum exp = positionalArgs[1] as PyNum;
    return base.pow(exp);
  }
  throw "pow() takes 2 or 3 arguments.";
}

void main() {
  String write = """
i1 = pow(123,456,789)
i2 = pow(123,45)
print(i1,i2)
d1 = pow(12.3,45)
d2 = pow(12.3,45.0)
print(d1,d2)
""";

  var tokens = Lexer(write).scanTokens();
  var stmts = Parser(tokens).parse();
  final interpreter = Interpreter();
  interpreter.globals.define("pow", NativeFunction(_pow));
  interpreter.interpret(stmts);
}
