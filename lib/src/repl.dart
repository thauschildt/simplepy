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

    // Append the new line (with newline char for lexer consistency)
    currentBlock += '$line\n';

    // Simple check for block continuation: does the line end with ':' or is indented?
    // This is a heuristic and not perfect, a full parser state check would be better.
    bool endsWithColon = line.trimRight().endsWith(':');
    bool isEmptyLine = line.trim().isEmpty;
    int currentIndent =
        line.length - line.trimLeft().length; // Basic indent calculation

    // Attempt to determine if the block is complete *without* running the full parser yet.
    // Heuristic: If the line is empty AND the indentation level is 0,
    // and we have some code already, assume the block is finished.
    // Or if the line doesn't end with ':' and isn't indented more than the start.
    bool likelyComplete = false;
    if (currentBlock.trim().isNotEmpty) {
      if (isEmptyLine && currentIndent == 0) {
        // Empty line at base level likely ends a block/statement sequence
        likelyComplete = true;
      } else if (!endsWithColon) {
        // If it doesn't end with colon, need to check indentation level
        // Try a quick lex to see if the block is likely closed by dedents
        try {
          Lexer tempLexer = Lexer(currentBlock);
          tempLexer.scanTokens(); // Run lexer to check indent/dedent balance
          // If the final indent level is back to 0 (or matches initial), it's likely complete
          if (tempLexer.indentStack.length <= 1) {
            likelyComplete = true;
          }
          // This is still imperfect - e.g., multiline strings, comments complicate it.
        } catch (e) {
          // If lexing fails here, it's likely incomplete or invalid anyway.
          // Let the main 'run' call handle the actual error.
          // Assume potentially complete to try parsing.
          likelyComplete = true;
        }
      }
      // If it ends with a colon, we always need more input.
    } else if (isEmptyLine) {
      // Ignore completely empty input lines
      currentBlock = ""; // Reset
      continue;
    } else {
      // Single non-empty line not ending in colon
      likelyComplete = true;
    }

    // If the heuristic suggests the block isn't complete, prompt for more input
    if (!likelyComplete && !isEmptyLine) {
      // Don't force continuation on empty lines unless indented
      continue;
    }

    // We have determined a block/statement seems complete, try running it
    run(currentBlock, isRepl: true); // Pass the collected block

    // Reset for next input cycle
    currentBlock = "";
    // Reset error flags for the next independent REPL input
    hadError = false;
    hadRuntimeError = false;
  }
  print("\nExiting REPL.");
}

// Main execution function for source code (either from file or REPL block)
void run(String source, {required bool isRepl}) {
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
    interpreter.interpret(statements);
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
}