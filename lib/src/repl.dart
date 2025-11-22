import 'dart:io';

import 'ast_nodes.dart';
import 'interpreter.dart';
import 'lexer.dart';
import 'parser.dart';

final Interpreter interpreter = Interpreter();

void main(List<String> args) {
  if (args.isNotEmpty) {
    runFile(args[0]);
  } else {
    runPrompt();
  }
}

void runFile(String path) {
  try {
    final file = File(path);
    final source = file.readAsStringSync();
    run(source, isRepl: false);
    if (hadError) exit(65); // Indicate syntax error exit code
    if (hadRuntimeError) exit(70); // Indicate runtime error exit code
  } catch (e) {
    print("Error reading file '$path': $e");
    exit(1);
  }
}

void runPrompt() {
  print("Dart Simple Python Subset REPL");
  print("Enter Python code. Use Ctrl+D or 'exit()' to quit.");
  String currentBlock = "";

  while (true) {
    stdout.write(currentBlock.isEmpty ? '>>> ' : '... ');
    String? line = stdin.readLineSync();

    // Handle Ctrl+D (EOF) or exit command
    if (line == null || line.trim() == 'exit()') {
      break;
    }

    // --- Block Completion Logic ---
    bool runTheBlock = false;
    if (currentBlock.isEmpty && line.trim().isEmpty) continue;

    // Append the new line (with newline char for lexer consistency)
    currentBlock += '$line\n';
    String trimmedLine = line.trim();

    // Finish block with empty line
    if (trimmedLine.isEmpty && currentBlock.trim().isNotEmpty) {
      try {
        Lexer tempLexer = Lexer(currentBlock);
        tempLexer.scanTokens(); // scan to fill indentStack

        // no indentation?
        if (tempLexer.indentStack.length <= 1) {
          runTheBlock = checkOpenBrackets(currentBlock) == 0;
        }
      } catch (e) {
        // Lexer error => try to run the code to show the error
        runTheBlock = true;
      }
    } else if (currentBlock.trim().isNotEmpty) {
      // Current line is not empty. Block will be executed when
      // - no open brackets
      // - last line doesnt end with ":"
      // - last relevant line (ignoring comment) is not indented
      List<String> lines = currentBlock.trimRight().split('\n');
      String lastRelevantLine = '';
      for (int i = lines.length - 1; i >= 0; i--) {
        String l = lines[i].trim();
        if (l.isNotEmpty && !l.startsWith('#')) {
          lastRelevantLine = l;
          break;
        }
      }

      if (checkOpenBrackets(currentBlock) > 0) {
        runTheBlock = false; // unclosed brackets -> need more input
      } else if (lastRelevantLine.endsWith(':')) {
        runTheBlock = false; // if, for, while... -> need more input
      } else {
        // Block might be ok for execution. However, Wait for empty line to confirm - unless there
        // is only a single line in the block
        if (lines.where((l) => l.trim().isNotEmpty).length == 1) {
          runTheBlock = true;
        } else {
          runTheBlock = false;
        }
      }
    }

    if (runTheBlock) {
      run(currentBlock, isRepl: true);
      // reset for next input
      currentBlock = "";
      hadError = false;
      hadRuntimeError = false;
    }
  }
  print("\nExiting REPL.");
}

int checkOpenBrackets(String block) {
  int balance = 0;
  bool inString = false;
  String? stringQuote;
  bool possibleFString = false;
  for (int i = 0; i < block.length; i++) {
    String char = block[i];
    String? prevChar = i > 0 ? block[i - 1] : null;

    // String flag (simplified for ' and ")
    if (inString) {
      if (char == stringQuote && prevChar != '\\') {
        inString = false;
        stringQuote = null;
        possibleFString = false;
      } else if (possibleFString && char == '{') {
        // Ignore nested braces in f-string (simplified)
        int braceLevel = 1;
        i++;
        while (i < block.length && braceLevel > 0) {
          if (block[i] == '{') braceLevel++;
          if (block[i] == '}') braceLevel--;
          i++;
        }
        i--;
      }
    } else {
      // f-string detection
      if ((char == '"' || char == "'") && (prevChar?.toLowerCase() == 'f')) {
        inString = true;
        stringQuote = char;
        possibleFString = true;
      } else if (char == '"' || char == "'") {
        inString = true;
        stringQuote = char;
        possibleFString = false;
      }
      // ignore comment until end of line
      else if (char == '#') {
        while (i < block.length && block[i] != '\n') {
          i++;
        }
        if (i < block.length) i--; // don't skip \n at end of line
      } else if (char == '(' || char == '[' || char == '{') {
        balance++;
      } else if (char == ')' || char == ']' || char == '}') {
        balance--;
      }
    }
  }
  return balance;
}

// Main execution function for source code (either from file or REPL block)
void run(String source, {required bool isRepl}) {
  Object? result;
  try {
    final lexer = Lexer(source);
    List<Token> tokens = lexer.scanTokens();

    final parser = Parser(tokens);
    List<Stmt> statements = parser.parse(); // parse() now returns List<Stmt>

    // Stop if there was a syntax error during parsing (indicated by hadError flag)
    // The error message should have been printed by the parser's error handler.
    // Note: Parser exceptions are caught below, this check might be redundant.
    // if (hadError) return; // Let exceptions handle control flow

    // // Optional: Print AST for debugging
    // if (isRepl && !hadError) { // Only print AST if no parse errors
    //   print("--- AST ---");
    //   statements.forEach((stmt) => print(AstPrinter().printStmt(stmt)));
    //   print("-----------");
    // }

    // If parsing was successful, interpret the AST
    result = interpreter.interpret(statements);
    if (result != null) result = interpreter.repr(result);
  } on LexerError catch (e) {
    print(e);
    hadError = true; // Mark static error
  } on ParseError {
    // Error should have been printed by parser's synchronize/error mechanism.
    hadError = true; // Mark static error
  } on RuntimeError {
    // Runtime errors are caught by interpreter.interpret() and printed there.
    hadRuntimeError = true; // Mark runtime error
  } on ReturnValue catch (_) {
    // This should only happen if 'return' is used at the top level (outside any function)
    hadRuntimeError = true; // Treat as runtime error in REPL/script context
  } catch (e, stacktrace) {
    // Catch any other unexpected Dart errors during execution
    print("An unexpected internal error occurred: $e");
    if (isRepl) {
      // Show stacktrace in REPL for debugging the interpreter itself
      print(stacktrace);
    }
    hadError = true; // Treat unexpected errors as critical failures
  }
  if (result != null) {
    print(result.toString());
  }
}
