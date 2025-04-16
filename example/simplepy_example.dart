import 'package:simplepy/simplepy.dart';

void main() {
  String py = """
def fibo(n):
  if n<=2:
    return 1
  return fibo(n-1) + fibo(n-2)

print(fibo(20))
""";
  final tokens = Lexer(py).scanTokens();
  final stmts = Parser(tokens).parse();
  Interpreter().interpret(stmts);
}
