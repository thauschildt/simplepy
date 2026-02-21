import 'package:simplepy/simplepy.dart';

void main() {
  String write = """
file = open("file.txt", "w")
file.write("Hello!")
file.close()
""";

  String read = """
file = open("file.txt", "r")
text = file.readline()
print("Read from file_", text)
""";

  var tokens = Lexer(write).scanTokens();
  var stmts = Parser(tokens).parse();
  final interpreter = Interpreter();
  interpreter.interpret(stmts);

  var content = interpreter.vfs["file.txt"];
  print("Accessing file content in dart: $content");
  // To store the file content permanently, you can write it to a file using dart:io

  // You can read the virtual file again as long as the same interpreter instance exists:
  tokens = Lexer(read).scanTokens();
  stmts = Parser(tokens).parse();
  interpreter.interpret(stmts);
}
