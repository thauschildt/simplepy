import 'dart:math';

import 'ast_nodes.dart';
import 'lexer.dart';


// Global flags indicating error states, potentially used by REPL.
/// Flag indicating if a static error (Lexer or Parser) occurred.
bool hadError = false;
/// Flag indicating if a runtime error occurred during interpretation.
bool hadRuntimeError = false;

/// An exception thrown by the [Interpreter] when an error occurs during
/// the execution (runtime) of the script.
///
/// Examples include undefined variables, type mismatches, division by zero, etc.
/// It holds the [token] near where the error occurred for location information
/// and a descriptive [message].
class RuntimeError implements Exception {
  final Token token; // Token near the error
  final String message;
  RuntimeError(this.token, this.message);
  @override
  String toString() =>
      '[line ${token.line}, col ${token.column}] Runtime Error near \'${token.lexeme}\': $message';
}

/// A special exception used internally to handle the unwinding of the call stack
/// when a `return` statement is encountered.
///
/// It carries the optional [value] being returned from the function. This should
/// always be caught within the function call mechanism (`visitCallExpr` or `PyCallable.call`).
class ReturnValue implements Exception {
  final Object? value;
  ReturnValue(this.value);
}

/// Interface for objects that can be called like functions within the interpreted language.
///
/// This abstraction allows both user-defined functions ([PyFunction]) and
/// native Dart functions ([NativeFunction]) to be treated uniformly during calls.
abstract class PyCallable {
  /// Executes the callable's logic.
  ///
  /// Takes the current [interpreter] instance, a list of evaluated [positionalArgs],
  /// and a map of evaluated [keywordArgs].
  /// Implementations are responsible for validating arguments against the callable's
  /// signature and performing the function's operations, potentially modifying
  /// the environment or returning a value.
  /// Throws [RuntimeError] if argument validation fails or an error occurs during execution.
  Object? call(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  );
}

/// Represents a user-defined function declared using the `def` keyword.
///
/// It stores the function's definition ([declaration]) from the AST and captures
/// the lexical environment ([closure]) where the function was defined. This closure
/// is used to resolve non-local variables when the function is called.
class PyFunction extends PyCallable {
  /// The AST node representing the function definition (`def name(...) ...`).
  final FunctionStmt declaration;

  /// The environment that was active when the function was defined.
  /// This enables lexical scoping (closures).
  final Environment closure;

  /// Flag indicating if this function is an initializer (e.g., `__init__` if classes were supported).
  final bool isInitializer; // Currently unused but kept for potential class extension

  /// Creates a callable representation of a user-defined function.
  /// [declaration] is the function's AST node.
  /// [closure] is the environment captured at definition time.
  PyFunction(this.declaration, this.closure, {this.isInitializer = false});

  /// Executes the user-defined function.
  ///
  /// This method performs the complex logic of binding the provided [positionalArgs]
  /// and [keywordArgs] to the function's declared parameters ([declaration].params),
  /// considering required, optional (with default value evaluation in the [closure]),
  /// `*args`, and `**kwargs` parameters.
  /// It creates a new [Environment] for the function call, enclosed by the [closure],
  /// defines the parameters as local variables within that environment, and then
  /// executes the function's body ([declaration].body) using [Interpreter.executeBlock].
  /// Handles `return` statements via [ReturnValue] exceptions and implicit `None` returns.
  /// Throws [RuntimeError] for argument mismatches (wrong number, type, unexpected keywords).
  @override
  Object? call(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs) {
    Environment environment = Environment(closure);
    int positionalArgIndex = 0;
    Set<String> usedKeywordArgs = {}; // Track keywords used to detect unexpected ones
    Set<String> assignedParams = {}; // Track params assigned to prevent duplicates

    StarArgsParameter? starArgsParam;
    StarStarKwargsParameter? starStarKwargsParam;
    List collectedStarArgs = [];
    Map<String, Object?> collectedKwargs = {};

    // --- Argument to Parameter Binding ---
    for (Parameter param in declaration.params) {
      String name = param.name.lexeme;

      if (param is RequiredParameter) {
        if (positionalArgIndex < positionalArgs.length) {
          // Argument provided positionally
          if (keywordArgs.containsKey(name)) {
            throw RuntimeError(
              param.name,
              "Argument '$name' given both positionally and as keyword.",
            );
          }
          environment.define(name, positionalArgs[positionalArgIndex]);
          assignedParams.add(name);
          positionalArgIndex++;
        } else if (keywordArgs.containsKey(name)) {
          // Argument provided by keyword
          environment.define(name, keywordArgs[name]);
          assignedParams.add(name);
          usedKeywordArgs.add(name); // Mark keyword as used
        } else {
          // Argument not provided
          throw RuntimeError(
            declaration.name,
            "Missing required argument: '$name'.",
          );
        }
      } else if (param is OptionalParameter) {
        if (positionalArgIndex < positionalArgs.length) {
          // Argument provided positionally
          if (keywordArgs.containsKey(name)) {
            throw RuntimeError(
              param.name,
              "Argument '$name' given both positionally and as keyword.",
            );
          }
          environment.define(name, positionalArgs[positionalArgIndex]);
          assignedParams.add(name);
          positionalArgIndex++;
        } else if (keywordArgs.containsKey(name)) {
          // Argument provided by keyword
          environment.define(name, keywordArgs[name]);
          assignedParams.add(name);
          usedKeywordArgs.add(name); // Mark keyword as used
        } else {
          // Use default value - IMPORTANT: Evaluate in the CLOSURE environment!
          Object? defaultValue;
          try {
            // Use a helper to evaluate in the correct scope without changing the *current* interpreter env
            defaultValue = interpreter.evaluateInEnvironment(
              param.defaultValue,
              closure,
            );
          } catch (e) {
            // Error during default value evaluation
            throw RuntimeError(
              param.name,
              "Error evaluating default value for '$name': $e",
            );
          }
          environment.define(name, defaultValue);
          assignedParams.add(name); // Parameter is assigned even if default
        }
      } else if (param is StarArgsParameter) {
        starArgsParam = param; // Store to collect remaining positionals later
      } else if (param is StarStarKwargsParameter) {
        starStarKwargsParam =
            param; // Store to collect remaining keywords later
      }
    } // End parameter definition loop

    // --- Handle *args ---
    if (starArgsParam != null) {
      // Collect all remaining positional arguments
      while (positionalArgIndex < positionalArgs.length) {
        collectedStarArgs.add(positionalArgs[positionalArgIndex]);
        positionalArgIndex++;
      }
      environment.define(
        starArgsParam.name.lexeme,
        collectedStarArgs,
      ); // Define the *args variable (as a List)
    } else {
      // If there's no *args parameter, check for excess positional arguments
      if (positionalArgIndex < positionalArgs.length) {
        // Calculate expected number of positional params (req + opt)
        int maxPositional =
            declaration.params
                .where((p) => p is RequiredParameter || p is OptionalParameter)
                .length;
        throw RuntimeError(
          declaration.name, // Or maybe the call paren token?
          "Expected at most $maxPositional positional arguments, but got ${positionalArgs.length}.",
        );
      }
    }

    // --- Handle **kwargs ---
    if (starStarKwargsParam != null) {
      // Collect all keyword arguments that haven't been used yet for named parameters
      for (var entry in keywordArgs.entries) {
        if (!usedKeywordArgs.contains(entry.key)) {
          collectedKwargs[entry.key] = entry.value;
          // Don't add to usedKeywordArgs here, we are checking against it
        }
      }
      environment.define(
        starStarKwargsParam.name.lexeme,
        collectedKwargs,
      ); // Define the **kwargs variable (as a Map)
    } else {
      // If there's no **kwargs parameter, check for unexpected keyword arguments
      for (var key in keywordArgs.keys) {
        if (!usedKeywordArgs.contains(key)) {
          // Check if a parameter with this name exists at all
          bool paramExists = declaration.params.any(
            (p) => p.name.lexeme == key,
          );
          if (paramExists) {
            // This case *shouldn't* happen if logic above is correct
            // (means keyword arg matched param name but wasn't used)
            throw RuntimeError(
              declaration.name,
              "Internal error: Keyword argument '$key' conflict.",
            );
          } else {
            throw RuntimeError(
              declaration
                  .name, // Try to find token for keyword if possible from parser? Hard here.
              "Got an unexpected keyword argument '$key'.",
            );
          }
        }
      }
    }

    // --- Execute Function Body ---
    try {
      interpreter.executeBlock(declaration.body, environment);
    } on ReturnValue catch (returnValue) {
      // If it's an initializer (__init__), it should return None implicitly (or the instance)
      // Standard Python __init__ returns None. If we return self, do it here.
      return isInitializer ? closure.getThis() : returnValue.value;
    }

    // Implicit return None if no return statement is hit
    // For __init__, return self (stored in closure?) or null if not class-related
    return isInitializer ? closure.getThis() : null;
  }

  @override
  String toString() => '<fn ${declaration.name.lexeme}>';
}

/// Wraps a native Dart function, making it callable from the interpreted language.
///
/// Allows defining built-in functions (like `print`, `range`, `len`, etc.)
/// implemented in Dart.
class NativeFunction extends PyCallable {
  /// The underlying Dart function to be executed.
  /// Its signature must match the expected pattern for handling interpreter state and arguments:
  /// `Object? Function(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs)`
  final Function _function;

  /// Creates a callable wrapper around a native Dart function [_function].
  NativeFunction(this._function);

  /// Executes the wrapped native Dart function.
  ///
  /// Passes the [interpreter], [positionalArgs], and [keywordArgs] directly to the
  /// underlying [_function]. Catches potential exceptions thrown by the Dart function
  /// and wraps them in a [RuntimeError] if they are not already one.
  @override
  Object? call(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs) {
    // Native functions now need to handle positional and keyword args themselves.
    try {
      // Directly call the wrapped Dart function, passing the structures
      return _function(interpreter, positionalArgs, keywordArgs);
    } catch (e) {
      // Catch errors from the Dart function and wrap them
      // Provide a dummy token for location info
      Token dummyToken = Token(TokenType.IDENTIFIER, '<native>', null, 0, 0);
      if (e is RuntimeError) {
        // Allow native funcs to throw RuntimeError
        rethrow;
      }
      throw RuntimeError(dummyToken, "Error executing native function: $e");
    }
  }

  /// Returns a generic string representation (e.g., `<native fn>`).
  @override
  String toString() => '<native fn>';
}

/// Manages the state (variables, functions, potentially classes) within a specific scope.
///
/// Environments can be nested using the [enclosing] field to represent lexical scoping.
/// Variable lookup ([get]) proceeds from the current environment up through its ancestors.
/// Assignment ([assign]) modifies variables in the nearest enclosing scope where they exist,
/// or creates them in the global scope if not found (following Python's behavior for assignment).
class Environment {
  /// The parent environment in the scope chain (null for the global scope).
  final Environment? enclosing;

  /// The storage for variables and other bindings defined in *this* scope.
  final Map<String, Object?> values = {};

  // Flags/Fields potentially for class support (currently unused effectively):
  /// Indicates if this environment represents a class scope.
  final bool isClassScope;
  /// Stores the instance ('self' or 'this') when inside a method call.
  Object? _thisInstance;

  /// Creates a new environment.
  /// [enclosing] specifies the parent scope (optional, defaults to null for global).
  /// [isClassScope] flags if this is for class definitions (defaults to false).
  Environment([this.enclosing, this.isClassScope = false]);

  /// Defines a new variable or binding with the given [name] and [value]
  /// strictly within the *current* environment scope. Replaces existing value if name conflicts.
  void define(String name, Object? value) {
    values[name] = value;
  }

  /// Retrieves the value associated with the variable [name] (from the token lexeme).
  ///
  /// Searches the current environment first. If not found, recursively searches
  /// the [enclosing] environments up to the global scope.
  /// Throws a [RuntimeError] if the variable is not defined in any accessible scope.
  Object? get(Token name) {
    if (values.containsKey(name.lexeme)) {
      return values[name.lexeme];
    }
    if (enclosing != null) {
      return enclosing!.get(name);
    }
    throw RuntimeError(name, "Undefined variable '${name.lexeme}'.");
  }

  /// Retrieves the value of 'self' or 'this' for method calls.
  /// Searches up the environment chain. Throws if called outside an instance context.
  Object? getThis() {
    if (_thisInstance != null) return _thisInstance;
    if (enclosing != null) return enclosing!.getThis();
    // Should not happen if called correctly:
    throw RuntimeError(Token(TokenType.IDENTIFIER, "self", null, 0, 0),
      "'self' is not defined in this context.");
  }

  /// Binds the instance ('self'/'this') for a method call within this environment.
  void bindThis(Object? instance) {
    _thisInstance = instance;
  }

  /// Assigns a [value] to an *existing* variable represented by [name].
  ///
  /// Searches the current environment first. If found, updates the value.
  /// If not found, recursively attempts assignment in the [enclosing] scopes.
  /// If the variable is not found in any ancestor scope, it implicitly creates
  /// the variable in the *global* scope (by default, mimicking Python).
  /// Throws a [RuntimeError] if assignment target is invalid (e.g., assigning to a literal).
  /// Note: This implementation allows implicit global creation. A stricter version might throw.
  void assign(Token name, Object? value) {
    if (values.containsKey(name.lexeme)) {
      values[name.lexeme] = value;
      return;
    }
    if (enclosing != null) {
      enclosing!.assign(name, value);
      return;
    }
    // If not found anywhere, Python assigns to the current (which might be global) scope.
    // If strict definition before assignment is needed, throw error here instead.
    values[name.lexeme] = value;
    // throw RuntimeError(name, "Undefined variable '${name.lexeme}' for assignment.");
  }
}

// Internal exceptions for loop control flow.
class _BreakException implements Exception {}
final _breakException = _BreakException(); // Singleton instance
class _ContinueException implements Exception {}
final _continueException = _ContinueException(); // Singleton instance

/// Executes the Abstract Syntax Tree (AST) representing the script.
///
/// It walks the AST using the Visitor pattern ([ExprVisitor], [StmtVisitor]),
/// evaluating expressions and executing statements according to the language semantics.
/// It manages the program's state (variables, functions) using an [Environment] stack.
/// Handles runtime errors and control flow constructs.
class Interpreter implements ExprVisitor<Object?>, StmtVisitor<void> {
  /// The top-level global environment. Holds built-ins and global variables.
  final Environment globals = Environment();

  /// The currently active environment during execution. Changes as scopes are entered/exited.
  late Environment _environment;

  /// Callback function used for the `print` built-in. Allows redirecting output.
  void Function(String)? _print;

  /// Internal buffer sometimes used by the default print implementation.
  final StringBuffer _outbuf = StringBuffer();

  /// Flag indicating if the interpreter is currently executing inside a loop (`while` or `for`).
  /// Used to validate `break` and `continue` statements.
  bool _isInLoop = false;

  /// Creates a new Interpreter instance.
  /// Initializes the global environment and defines built-in functions like `print` and `range`.
  Interpreter() {
    _environment = globals; // Start in global scope
    
    // Define built-in print functions
    globals.define("print", NativeFunction(_printBuiltin));
    globals.define("range", NativeFunction(_rangeBuiltin));

    // Add more built-ins here (e.g., len, type, input, int, str, list, dict)
    // globals.define("len", NativeFunction(_lenBuiltin));
    // globals.define("str", NativeFunction(_strBuiltin));
    // ...
  }

  /// Default print implementation writing to stdout, handling partial lines.
  void _printWithBuffer(s) {
    int n=s.lastIndexOf("\n");
    String first = "";
    if (n>=0) {
      first = s.substring(0, n);
      String last = s.substring(n+1);
      _outbuf.clear();
      _outbuf.write(last);
    }
    print(_outbuf.toString() + first);
  }

  // --- Built-in Function Implementations ---

  /// Native implementation of the `print()` function.
  /// Handles positional arguments, `sep`, and `end` keyword arguments.
  static Object? _printBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    // Python's print has sep=' ', end='\n', file=sys.stdout, flush=False
    String separator = ' ';
    String end = '\n';
    // TODO: Handle file and flush if needed

    if (keywordArgs.containsKey('sep')) {
      separator = interpreter.stringify(keywordArgs['sep']);
      keywordArgs.remove('sep');
    }
    if (keywordArgs.containsKey('end')) {
      end = interpreter.stringify(keywordArgs['end']);
      keywordArgs.remove('end');
    }

    if (keywordArgs.isNotEmpty) {
      String unexpected = keywordArgs.keys.first;
      throw RuntimeError(
        Token(TokenType.PRINT, 'print', null, 0, 0),
        "print() got unexpected keyword argument '$unexpected'",
      );
    }

    String output = positionalArgs
        .map((arg) => interpreter.stringify(arg))
        .join(separator);
    if (interpreter._print != null) {
      interpreter._print!(output + end);
    } else {
      interpreter._printWithBuffer(output + end);
    }
    return null; // print returns None
  }

  /// Native implementation of the `range()` function.
  /// Handles 1, 2, or 3 integer arguments to generate a list of numbers.
  static Object? _rangeBuiltin(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs) {
    if (keywordArgs.isNotEmpty) {
      throw RuntimeError(
        Token(TokenType.RANGE, 'range', null, 0, 0),
        "range() doesn't accept keyword arguments.",
      );
    }

    int start = 0, stop = 0, step = 1;

    if (positionalArgs.isEmpty || positionalArgs.length > 3) {
      throw RuntimeError(
        Token(TokenType.RANGE, 'range', null, 0, 0),
        "range() takes 1 to 3 arguments (${positionalArgs.length} given).",
      );
    }

    // Check types and assign start/stop/step
    try {
      if (positionalArgs.length == 1) {
        stop = _expectInt(positionalArgs[0], 'range()');
      } else if (positionalArgs.length == 2) {
        start = _expectInt(positionalArgs[0], 'range()');
        stop = _expectInt(positionalArgs[1], 'range()');
      } else {
        // length == 3
        start = _expectInt(positionalArgs[0], 'range()');
        stop = _expectInt(positionalArgs[1], 'range()');
        step = _expectInt(positionalArgs[2], 'range()');
        if (step == 0) {
          throw RuntimeError(
            Token(TokenType.RANGE, 'range', null, 0, 0),
            "range() step cannot be zero.",
          );
        }
      }
    } catch (e) {
      throw RuntimeError(
        Token(TokenType.RANGE, 'range', null, 0, 0),
        e.toString(),
      );
    }

    // Generate the list (handle step direction)
    List<int> result = [];
    if (step > 0) {
      for (int i = start; i < stop; i += step) {
        result.add(i);
      }
    } else {
      // step < 0
      for (int i = start; i > stop; i += step) {
        result.add(i);
      }
    }
    return result; // Return a list of integers
  }

  // Helper to ensure an argument is an integer for built-ins.
  static int _expectInt(Object? arg, String funcName) {
    if (arg is int) return arg;
    // Python often converts floats to ints here, but let's be stricter
    if (arg is double && arg == arg.truncateToDouble()) return arg.toInt();
    throw "'$funcName' argument must be an integer (got ${arg?.runtimeType ?? 'None'}).";
  }

  /// Interprets a list of top-level [statements] (the AST).
  ///
  /// This is the main entry point to start execution. It iterates through the
  /// statements, calling [execute] for each one.
  /// Catches and reports [RuntimeError]s.
  /// Allows providing optional callbacks: [printCallback] to handle `print` output,
  /// and [errorCallback] to handle runtime error messages.
  void interpret(
    List<Stmt> statements, [
    void Function(String)? printCallback,
    void Function(String)? errorCallback,
  ]) {
    _print = printCallback ?? _printWithBuffer;
    try {
      for (final statement in statements) {
        execute(statement);
      }
    } on RuntimeError catch (e) {
      // TODO: Improve error reporting context (stack trace?)
      if (errorCallback != null) errorCallback(e.toString());
      print(e); // Report runtime errors
      // Set flag for REPL?
      hadRuntimeError = true; // Assuming hadRuntimeError is defined globally for REPL
    } on ReturnValue catch (_) {
      // A ReturnValue exception should only be caught inside a function call.
      // If it reaches here, it's an error (return outside function).
      if (errorCallback != null) errorCallback("SyntaxError: 'return' outside function");
      print(
        RuntimeError(
          Token(TokenType.RETURN, 'return', null, 0, 0),
          "SyntaxError: 'return' outside function",
        ),
      ); // Python gives SyntaxError
      hadRuntimeError = true;
    }
  }

  // --- Statement Execution ---

  /// Executes a single [Stmt] node by dispatching to the appropriate `visit` method.
  void execute(Stmt stmt) {
    stmt.accept(this);
  }

  /// Executes a block of [statements] within a specific [environment].
  /// Sets the interpreter's current environment to the given one for the duration
  /// of the block's execution and restores the previous environment afterwards.
  /// Crucial for function calls and potentially other scoped constructs.
    void executeBlock(List<Stmt> statements, Environment environment) {
    Environment previous = _environment;
    try {
      _environment = environment; // Switch to the new environment
      for (final statement in statements) {
        execute(statement);
      }
    } finally {
      _environment = previous; // Restore previous environment when block exits
    }
  }

  /// Visitor method for executing a [BlockStmt].
  /// Simply executes the statements within the current environment.
  /// Note: Scope creation is handled by the calling context (e.g., `executeBlock`).
  @override
  void visitBlockStmt(BlockStmt stmt) {
    for (final statement in stmt.statements) {
      execute(statement);
    }
  }

  /// Visitor method for executing an [ExpressionStmt].
  /// Evaluates the expression and discards the result.
  @override
  void visitExpressionStmt(ExpressionStmt stmt) {
    evaluate(stmt.expression);
  }

  /// Visitor method for handling a [FunctionStmt] (function definition).
  /// Creates a [PyFunction] object, capturing the current environment as its closure,
  /// and defines it in the current environment.
  @override
  void visitFunctionStmt(FunctionStmt stmt) {
    // Create the function object, capturing the *current* environment as its closure.
    PyFunction function = PyFunction(stmt, _environment);
    _environment.define(
      stmt.name.lexeme,
      function,
    ); // Define the function in the current scope.
  }

  /// Visitor method for executing an [IfStmt].
  /// Evaluates the condition, executes the `thenBranch` if truthy.
  /// If falsey, evaluates `elif` conditions sequentially, executing the first truthy one.
  /// Executes `elseBranch` if no previous condition was met.
  @override
  void visitIfStmt(IfStmt stmt) {
    if (isTruthy(evaluate(stmt.condition))) {
      execute(stmt.thenBranch); // thenBranch is likely a BlockStmt
    } else {
      bool executedElif = false;
      for (final elif in stmt.elifBranches) {
        if (isTruthy(evaluate(elif.condition))) {
          execute(elif.thenBranch); // elif.thenBranch is likely a BlockStmt
          executedElif = true;
          break; // Execute only the first matching elif
        }
      }
      if (!executedElif && stmt.elseBranch != null) {
        execute(stmt.elseBranch!); // elseBranch is likely a BlockStmt
      }
    }
  }

  /// Visitor method for executing a [ReturnStmt].
  /// Evaluates the optional return value and throws a [ReturnValue] exception
  /// to unwind the stack to the function call site.
  @override
  void visitReturnStmt(ReturnStmt stmt) {
    Object? value;
    if (stmt.value != null) {
      value = evaluate(stmt.value!); // Evaluate the return value expression
    }
    // Throw the special ReturnValue exception to unwind the stack to the function call boundary
    throw ReturnValue(value);
  }

  /// Visitor method for executing a [WhileStmt].
  /// Repeatedly evaluates the condition; if truthy, executes the body.
  /// Handles [_BreakException] and [_ContinueException] to control loop flow.
  /// Sets/resets the [_isInLoop] flag. Includes basic infinite loop protection.
  @override
  void visitWhileStmt(WhileStmt stmt) {
     bool previousLoopState = _isInLoop; // remember if while is inside another loop
    _isInLoop = true;
    try {
      while (isTruthy(evaluate(stmt.condition))) {
        try {
          execute(stmt.body);
        } on _BreakException {
          break; // leave the dart `while` loop in the interpreter
        } on _ContinueException {
          continue; // jump to next iteration of the while loop
        } on ReturnValue {
          rethrow; // Propagate return upwards out of the loop and function
        }
      }
    } finally {
      _isInLoop = previousLoopState; // restore previous state
    }
  }

  /// Visitor method for executing a [ForStmt].
  /// Evaluates the [iterable] expression. If it's a Dart [Iterable] or [String],
  /// iterates through its elements. In each iteration, defines the loop [variable]
  /// in the current environment and executes the [body].
  /// Handles [_BreakException] and [_ContinueException]. Sets/resets [_isInLoop].
  @override
  void visitForStmt(ForStmt stmt) {
    Object? iterableValue = evaluate(stmt.iterable);
    Token iterableToken = stmt.iterable is VariableExpr?
      (stmt.iterable as VariableExpr).name
      : stmt.variable; // Best guess for token

    if (iterableValue is! Iterable) {
      // Check if it's a Dart Iterable (List, Set, etc.)
      // Check if it's a String (also iterable)
      if (iterableValue is String) {
        iterableValue = iterableValue.split(''); // Iterate over characters
      } else {
        throw RuntimeError(
          iterableToken,
          "For loop target must be iterable (e.g., list, string).",
        );
      }
    }

    // Loop through the elements
    bool previousLoopState = _isInLoop; // Vorherigen Zustand speichern
    _isInLoop = true;
    try {
      for (var element in iterableValue) {
        try {
          _environment.define(stmt.variable.lexeme, element);
          execute(stmt.body);
        } on _BreakException {
            break;
        } on _ContinueException {
            continue;
        } on ReturnValue {
        rethrow; // Propagate return upwards
        }
      }
    } finally {
        _isInLoop = previousLoopState; // Vorherigen Zustand wiederherstellen
    }
  }

  /// Visitor method for executing a [PassStmt]. Does nothing.
  @override
  void visitPassStmt(PassStmt stmt) {
    // Nothing to do
  }

  /// Visitor method for executing a [BreakStmt].
  /// Throws [_BreakException] if inside a loop, otherwise throws [RuntimeError].
  @override
  void visitBreakStmt(BreakStmt stmt) {
    if (!_isInLoop) {
      throw RuntimeError(stmt.token, "SyntaxError: 'break' outside loop");
    }
    throw _breakException;
  }

  /// Visitor method for executing a [ContinueStmt].
  /// Throws [_ContinueException] if inside a loop, otherwise throws [RuntimeError].
  @override
  void visitContinueStmt(ContinueStmt stmt) {
     if (!_isInLoop) {
      throw RuntimeError(stmt.token, "SyntaxError: 'continue' outside loop");
    }
    throw _continueException;
  }
    
  // --- Expression Evaluation ---

  /// Helper to evaluate an expression within a specific [environment].
  /// Used primarily for evaluating default parameter values in the correct closure scope.
  Object? evaluateInEnvironment(Expr expr, Environment environment) {
    Environment previous = _environment;
    try {
      _environment = environment;
      return evaluate(expr);
    } finally {
      _environment = previous;
    }
  }

  /// Evaluates a single [Expr] node by dispatching to the appropriate `visit` method.
  /// Returns the result of the expression evaluation.
  Object? evaluate(Expr expr) {
    return expr.accept(this);
  }

  /// Visitor method for evaluating an [AssignExpr].
  /// Evaluates the right-hand side [value], then assigns it to the variable [name]
  /// in the current environment chain using [_environment.assign]. Returns the assigned value.
  @override
  Object? visitAssignExpr(AssignExpr expr) {
    Object? value = evaluate(expr.value);
    // Assign in the current environment (or enclosing ones)
    _environment.assign(expr.name, value);
    return value;
  }

  /// Visitor method for evaluating an [AugAssignExpr] (e.g., `+=`, `*=`).
   /// Evaluates the target (variable or index/key) to get the current value,
   /// evaluates the right-hand side value, performs the operation,
   /// and assigns the result back to the target. Handles both variable and index targets.
  @override
  Object? visitAugAssignExpr(AugAssignExpr expr) {
    Object? rightValue = evaluate(expr.value);
    if (expr.target is VariableExpr) {
      VariableExpr targetVar = expr.target as VariableExpr;
      Token name = targetVar.name;
      Object? currentValue = _environment.get(name);
      Object? result = _performAugmentedOperation(expr.operator, currentValue, rightValue);
      _environment.assign(name, result);
      return result;
    } else if (expr.target is GetExpr) {
      GetExpr targetGet = expr.target as GetExpr;
      Object? object = evaluate(targetGet.object);
      Object? keyOrIndex = evaluate(targetGet.index);
      Object? currentValue = _performGetOperation(object, keyOrIndex, targetGet.bracket);
      Object? result = _performAugmentedOperation(expr.operator, currentValue, rightValue);
      _performSetOperation(object, keyOrIndex, result, targetGet.bracket);  
      return result;
    } else {
      throw RuntimeError(
        expr.operator,
        "Invalid target for augmented assignment.",
      );
    }
  }

  /// Helper for augmented assignment: performs the actual operation (e.g., +, *)
  /// based on the operator token type. Includes type checking.
  Object? _performAugmentedOperation(Token operator, Object? left, Object? right) {
    void checkNumbers(String op) {
        if (left is! num || right is! num) {
            throw RuntimeError(operator, "Unsupported operand type(s) for $op: '${left?.runtimeType}' and '${right?.runtimeType}'");
        }
    }
    void checkInts(String op) {
        if (left is! int || right is! int) {
            throw RuntimeError(operator, "Unsupported operand type(s) for $op: '${left?.runtimeType}' and '${right?.runtimeType}'. Operands must be integers.");
        }
    }

    switch (operator.type) {
      case TokenType.STAR_EQUAL:
        if (left is num && right is num) return left * right;
        if ((left is String || left is List) && right is int) return _multiplySequence(left!, right, operator);
        if (left is int && (right is String || right is List)) return _multiplySequence(right!, left, operator);
        throw RuntimeError(operator, "Unsupported operand type(s) for *=: '${left?.runtimeType}' and '${right?.runtimeType}'");
      case TokenType.STAR_STAR_EQUAL:
        checkNumbers("**=");
        return pow(left as num, right as num);
      case TokenType.PLUS_EQUAL:
        if (left is num && right is num) return left + right;
        if (left is String && right is String) return left + right;
        if (left is List && right is List) return [...left, ...right];
        throw RuntimeError(operator, "Unsupported operand type(s) for +=: '${left?.runtimeType}' and '${right?.runtimeType}'");
      case TokenType.MINUS_EQUAL:
        checkNumbers("-=");
        return (left as num) - (right as num);
      case TokenType.SLASH_EQUAL:
        checkNumbers("/=");
        if (right == 0) throw RuntimeError(operator,"ZeroDivisionError");
        return (left as num) / (right as num);
      case TokenType.SLASH_SLASH_EQUAL:
        checkNumbers("//=");
        if (right == 0) throw RuntimeError(operator,"ZeroDivisionError");
        return (left as num) ~/ (right as num);
      case TokenType.PERCENT_EQUAL:
        checkNumbers("%=");
        return _pythonModulo(left as num, right as num);
      case TokenType.AMPERSAND_EQUAL:   checkInts("&="); return (left as int) & (right as int);
      case TokenType.PIPE_EQUAL:        checkInts("|="); return (left as int) | (right as int);
      case TokenType.CARET_EQUAL:       checkInts("^="); return (left as int) ^ (right as int);
      case TokenType.LEFT_SHIFT_EQUAL:  checkInts("<<="); return (left as int) << (right as int);
      case TokenType.RIGHT_SHIFT_EQUAL: checkInts(">>="); return (left as int) >> (right as int);
      default:
        throw RuntimeError(
          operator,
          "Unsupported augmented assignment operator.",
        );
    }
  }

  /// Helper for augmented assignment: performs the 'get' part for index/key targets.
  Object? _performGetOperation(Object? object, Object? keyOrIndex, Token bracket) {
    if (object is List) {
      if (keyOrIndex is! int) throw RuntimeError(bracket, "List indices must be integers.");
      int index = keyOrIndex;
      if (index < 0) index += object.length;
      if (index < 0 || index >= object.length) throw RuntimeError(bracket, "List index out of range.");
      return object[index];
    }
    if (object is Map) {
      if (!object.containsKey(keyOrIndex)) throw RuntimeError(bracket, "KeyError: ${stringify(keyOrIndex)}");
      return object[keyOrIndex];
    }
    throw RuntimeError(bracket, "Object type does not support getting items for augmented assignment.");
  }

  /// Helper for augmented assignment: performs the 'set' part for index/key targets.
  void _performSetOperation(Object? object, Object? keyOrIndex, Object? value, Token bracket) {
    if (object is List) {
      if (keyOrIndex is! int) throw RuntimeError(bracket, "List indices must be integers.");
      int index = keyOrIndex;
      if (index < 0) index += object.length;
      if (index < 0 || index >= object.length) throw RuntimeError(bracket, "List index out of range.");
      object[index] = value;
      return;
    }
    if (object is Map) {
      if (!_isHashable(keyOrIndex)) throw RuntimeError(bracket, "TypeError: unhashable type: '${keyOrIndex?.runtimeType ?? 'None'}'");
      object[keyOrIndex] = value;
      return;
    }
    // String set etc. (Strings are immutable)
    throw RuntimeError(
      bracket,
      "Object type does not support setting items for augmented assignment.",
    );
  }
  
  /// Visitor method for evaluating a [UnaryExpr] (`-`, `+`, `~`, `not`).
  /// Evaluates the operand, performs the unary operation, and returns the result.
  /// Includes type checking.
  @override
  Object? visitUnaryExpr(UnaryExpr expr) {
    Object? operand = evaluate(expr.operand);
    switch (expr.operator.type) {
      case TokenType.NOT:
        return !isTruthy(operand);
      case TokenType.MINUS:
        if (operand is num) return -operand;
        throw RuntimeError(expr.operator, "Operand for unary '-' must be a number (got ${operand?.runtimeType}).");
      case TokenType.PLUS:
        if (operand is num) return operand;
        throw RuntimeError(expr.operator, "Operand for unary '+' must be a number (got ${operand?.runtimeType}).");
       case TokenType.TILDE:
        if (operand is int) return -(operand+1);
        // Python allows ~ on bool (True -> -2, False -> -1), but not on float
        if (operand is bool) return operand ? -(1+1) : -(0+1); // results in -2 and -1
        throw RuntimeError(expr.operator, "TypeError: bad operand type for unary ~: '${operand?.runtimeType}'. Must be an integer or boolean.");
      default:
        // should not occur
        throw RuntimeError(expr.operator, "Unreachable: Unknown unary operator.");
    }
  }

  /// Visitor method for evaluating a [BinaryExpr] (arithmetic, comparison, bitwise).
  /// Evaluates the left and right operands, performs the binary operation based on
  /// the operator type, and returns the result. Includes type checking and handling
  /// of Python-specific semantics (e.g., string/list concatenation/repetition, modulo).
  @override
  Object? visitBinaryExpr(BinaryExpr expr) {
    Object? left = evaluate(expr.left);
    Object? right = evaluate(expr.right);

    // Helper for type checks
     void checkInts() {
        if (left is! int || right is! int) {
            throw RuntimeError(expr.operator, "TypeError: unsupported operand type(s) for ${expr.operator.lexeme}: '${left?.runtimeType}' and '${right?.runtimeType}'. Operands must be integers.");
        }
    }
     void checkNumbers() {
       if (left is! num || right is! num) {
         throw RuntimeError(expr.operator, "TypeError: unsupported operand type(s) for ${expr.operator.lexeme}: '${left?.runtimeType}' and '${right?.runtimeType}'");
       }
     }

    switch (expr.operator.type) {
      // --- Arithmetic ---
      case TokenType.MINUS:
        checkNumbers();
        return (left as num) - (right as num);
      case TokenType.PLUS:
         if (left is num && right is num) return left + right;
         if (left is String && right is String) return left + right;
         if (left is List && right is List) return [...left, ...right];
         throw RuntimeError(expr.operator, "TypeError: unsupported operand type(s) for +: '${left?.runtimeType}' and '${right?.runtimeType}'");
      case TokenType.SLASH:
        checkNumbers();
        if (right == 0) throw RuntimeError(expr.operator,"ZeroDivisionError");
        return (left as num).toDouble() / (right as num).toDouble();
      case TokenType.SLASH_SLASH:
        checkNumbers();
        if (right == 0) throw RuntimeError(expr.operator,"ZeroDivisionError");
        return (left as num) ~/ (right as num);
       case TokenType.STAR:
        if (left is num && right is num) return left * right;
        if ((left is String || left is List) && right is int) return _multiplySequence(left!, right, expr.operator);
        if (left is int && (right is String || right is List)) return _multiplySequence(right!, left, expr.operator);
        throw RuntimeError(expr.operator, "TypeError: unsupported operand type(s) for *: '${left?.runtimeType}' and '${right?.runtimeType}'");
      case TokenType.STAR_STAR:
        checkNumbers();
        try {
          return pow(left as num, right as num);
        }  catch (e) {
          throw RuntimeError(expr.operator, "Math error during exponentiation: $e");
        }
      case TokenType.PERCENT:
        checkNumbers();
        return _pythonModulo(left as num, right as num);
      // --- Comparison ---
      case TokenType.GREATER: return _compare(left, right, expr.operator) > 0;
      case TokenType.GREATER_EQUAL: return _compare(left, right, expr.operator) >= 0;
      case TokenType.LESS: return _compare(left, right, expr.operator) < 0;
      case TokenType.LESS_EQUAL: return _compare(left, right, expr.operator) <= 0;
      case TokenType.BANG_EQUAL: return !isEqual(left, right);
      case TokenType.EQUAL_EQUAL: return isEqual(left, right);

      // --- Bitwise operators (&, |, ^, <<, >>) ---
      case TokenType.AMPERSAND:   checkInts(); return (left as int) & (right as int);
      case TokenType.PIPE:        checkInts(); return (left as int) | (right as int);
      case TokenType.CARET:       checkInts(); return (left as int) ^ (right as int);
      case TokenType.LEFT_SHIFT:  checkInts(); return (left as int) << (right as int);
      case TokenType.RIGHT_SHIFT: checkInts(); return (left as int) >> (right as int);

      default:
        // Should not happen if parser is correct
        throw RuntimeError(expr.operator, "Unknown binary operator encountered.");
    }
  }

  /// Helper for comparisons, handling numbers and strings. Throws error for incompatible types.
  int _compare(Object? left, Object? right, Token operator) {
    if (left is num && right is num) return left.compareTo(right);
    if (left is String && right is String) return left.compareTo(right);
    // Python cannot compare different types (except for numbers)
    throw RuntimeError(operator, "TypeError: '${operator.lexeme}' not supported between instances of '${left?.runtimeType}' and '${right?.runtimeType}'");
  }

  /// Helper for Python's specific modulo behavior (result has same sign as divisor).
  num _pythonModulo(num a, num b) {
    print("$a % $b ${a.runtimeType} ${b.runtimeType}");
    if (b == 0) {
      throw RuntimeError(Token(TokenType.PERCENT, '%', null, 0,0),
        a is int && b is int? "ZeroDivisionError: integer modulo by zero" : "ZeroDivisionError: float modulo");
    }
    var result = a%b;
    if (result>=0 != b>=0) result += b;
    return result;
  }

  /// Helper for sequence multiplication (string * int, list * int).
  Object _multiplySequence(Object sequence, int times, Token operator) {
    if (times < 0) times = 0; // Multiply by negative is empty sequence

    if (sequence is String) {
      return sequence * times; // Dart string multiplication works
    } else if (sequence is List) {
      List result = [];
      for (int i = 0; i < times; i++) {
        result.addAll(sequence); // Add copies of elements
      }
      return result;
    }
    // Should not be reached if called correctly
    throw RuntimeError(operator, "Internal error in sequence multiplication.");
  }

  /// Visitor method for evaluating a [CallExpr].
  /// Evaluates the [callee] expression. If it's a [PyCallable], evaluates all arguments
  /// (positional and keyword), then invokes the callable's `call` method.
  /// Throws [RuntimeError] if the callee is not callable or if errors occur during the call.
  @override
  Object? visitCallExpr(CallExpr expr) {
    Object? callee = evaluate(expr.callee); // Evaluate the object being called
    if (callee is! PyCallable) {
      throw RuntimeError(expr.paren, "Object of type '${callee?.runtimeType ?? 'None'}' is not callable.");
    }
    PyCallable function = callee;
    // Evaluate arguments (both positional and keyword values)
    List<Object?> positionalArgs = [];
    Map<String, Object?> keywordArgs = {};

    for (Argument argument in expr.arguments) {
      if (argument is PositionalArgument) {
        // Check if we already saw keyword args (parser should prevent this, but double check)
        if (keywordArgs.isNotEmpty) {
          throw RuntimeError(
            expr.paren,
            "Positional argument follows keyword argument in call.",
          ); // Need better token info
        }
        positionalArgs.add(evaluate(argument.value));
      } else if (argument is KeywordArgument) {
        String name = argument.name.lexeme;
        if (keywordArgs.containsKey(name)) {
          throw RuntimeError(
            argument.name,
            "Duplicate keyword argument '$name' in call.",
          );
        }
        keywordArgs[name] = evaluate(argument.value);
      }
      // TODO: Handle argument unpacking (*args, **kwargs) during call if implemented
      // else if (argument is StarArgument) { ... expand evaluated iterable into positionalArgs ... }
      // else if (argument is StarStarArgument) { ... expand evaluated map into keywordArgs ... }
    }

    // Call the callable object using the collected arguments
    try {
      // The PyCallable's call method is responsible for matching args to params
      return function.call(this, positionalArgs, keywordArgs);
    } on ReturnValue catch (_) {
      // This should not be caught here - ReturnValue propagates up
      rethrow;
    } catch (e) {
      // Catch errors thrown by the call itself (e.g., wrong number of args, native errors)
      if (e is RuntimeError) rethrow; // Re-throw our specific runtime errors
      // Wrap other potential Dart errors
      throw RuntimeError(expr.paren, "Error during function execution: $e");
    }
  }

  /// Visitor method for evaluating a [GetExpr] (indexing like `obj[key]`).
  /// Evaluates the [object] and the [index] expressions. Performs list, string,
  /// or dictionary lookup based on the object's type.
  /// Throws [RuntimeError] for invalid types, index out of bounds, or key errors.
  @override
  Object? visitGetExpr(GetExpr expr) {
    // Handles obj[index]
    Object? object = evaluate(expr.object);
    Object? key = evaluate(expr.index); // The index or key

    // List indexing
    if (object is List) {
      if (key is! int) {
        // Python allows slices, e.g. mylist[1:3]. Not implemented here.
        // if (key is Slice) { ... }
        throw RuntimeError(
          expr.bracket,
          "List indices must be integers (got ${key?.runtimeType}).",
        );
      }
      int index = key;
      // Handle negative indices
      if (index < 0) index += object.length;

      if (index < 0 || index >= object.length) {
        throw RuntimeError(expr.bracket, "List index out of range.");
      }
      return object[index];
    }

    // String indexing/slicing
    if (object is String) {
      if (key is! int) {
        // TODO: Implement string slicing if needed
        throw RuntimeError(
          expr.bracket,
          "String indices must be integers (got ${key?.runtimeType}).",
        );
      }
      int index = key;
      // Handle negative indices
      if (index < 0) index += object.length;

      if (index < 0 || index >= object.length) {
        throw RuntimeError(expr.bracket, "String index out of range.");
      }
      // Return character as a String
      return object[index];
    }

    // Dictionary lookup
    if (object is Map) {
      // Check if the key exists. Python raises KeyError.
      if (!object.containsKey(key)) {
        throw RuntimeError(expr.bracket, "KeyError: ${stringify(key)}");
      }
      return object[key];
    }

    throw RuntimeError(
      expr.bracket,
      "Object of type '${object?.runtimeType ?? 'None'}' does not support indexing ('[]').",
    );
  }

  /// Visitor method for evaluating a [SetExpr] (item assignment like `obj[key] = value`).
  /// Evaluates the object, index/key, and value. Performs assignment on lists or dictionaries.
  /// Throws [RuntimeError] for invalid types (e.g., string assignment), index errors, or unhashable keys.
  @override
  Object? visitSetExpr(SetExpr expr) {
    Object? targetObject = evaluate(expr.object);
    Object? indexOrKey = evaluate(expr.index);
    Object? valueToSet = evaluate(expr.value);

    if (targetObject is List) {
      if (indexOrKey is! int) {
        throw RuntimeError(expr.bracket, "List indices must be integers.");
      }
      int index = indexOrKey;
      if (index < 0) {
        index += targetObject.length;
      }
      if (index < 0 || index >= targetObject.length) {
        throw RuntimeError(expr.bracket, "List assignment index out of range.");
      }
      targetObject[index] = valueToSet;
      return valueToSet;
    } else if (targetObject is Map) {
      if (!_isHashable(indexOrKey)) {
        throw RuntimeError(
          expr.bracket,
          "TypeError: unhashable type: '${indexOrKey?.runtimeType ?? 'None'}'",
        );
      }
      targetObject[indexOrKey] = valueToSet;
      return valueToSet;
    } else if (targetObject is String) {
      throw RuntimeError(
        expr.bracket,
        "TypeError: 'str' object does not support item assignment",
      );
    }

    throw RuntimeError(
      expr.bracket,
      "TypeError: '${targetObject?.runtimeType ?? 'None'}' object does not support item assignment",
    );
  }

  /// Visitor method for evaluating a [GroupingExpr] (`(...)`).
  /// Simply evaluates the inner expression.
  @override
  Object? visitGroupingExpr(GroupingExpr expr) {
    return evaluate(expr.expression);
  }

  /// Visitor method for evaluating a [LiteralExpr] (numbers, strings, True, False, None).
  /// Returns the literal value directly.
  @override
  Object? visitLiteralExpr(LiteralExpr expr) {
    return expr.value;
  }

  /// Visitor method for evaluating a [ListLiteralExpr] (`[...]`).
  /// Evaluates each element expression and returns a new Dart [List].
  @override
  Object? visitListLiteralExpr(ListLiteralExpr expr) {
    List<Object?> elements = [];
    for (Expr elementExpr in expr.elements) {
      elements.add(evaluate(elementExpr));
    }
    return elements;
  }

  /// Visitor method for evaluating a [DictLiteralExpr] (`{...}`).
  /// Evaluates each key and value expression, checks key hashability, and returns a new Dart [Map].
  /// Throws [RuntimeError] for unhashable keys.
  @override
  Object? visitDictLiteralExpr(DictLiteralExpr expr) {
    Map<Object?, Object?> map = {};
    if (expr.keys.length != expr.values.length) {
      // Should be caught by parser, but safety check
      throw RuntimeError(expr.brace, "Internal error: Mismatched keys/values in dictionary literal.");
    }
    for (int i = 0; i < expr.keys.length; i++) {
      Object? key = evaluate(expr.keys[i]);
      // TODO: Check if key is hashable (basic types are in Dart)
      // In Python, lists cannot be keys. We might need a custom hash check.
      if (!_isHashable(key)) {
        throw RuntimeError(
          expr.brace,
          "TypeError: unhashable type: '${key?.runtimeType ?? 'None'}'",
        );
      }
      Object? value = evaluate(expr.values[i]);
      map[key] = value;
    }
    return map;
  }

  /// Helper to check if an object is suitable as a dictionary key (hashable).
  /// Mimics Python's rules (numbers, strings, booleans, None are hashable; lists, dicts are not).
  bool _isHashable(Object? key) {
    if (key == null) return true; // None is hashable
    if (key is num || key is String || key is bool || key is PyCallable)
      return true;
    // Add other immutable types like Tuple if implemented
    // Lists and Dicts are not hashable by default in Python
    if (key is List || key is Map) return false;
    // Assume other unknown types are hashable? Or be stricter? Let's be strict.
    // Could potentially check for a custom __hash__ method if classes are added.
    return false; // Default to not hashable
  }

  /// Visitor method for evaluating a [LogicalExpr] (`and`, `or`).
  /// Implements short-circuiting evaluation:
  /// - For `or`: evaluates left; if truthy, returns left value, otherwise evaluates and returns right.
  /// - For `and`: evaluates left; if falsey, returns left value, otherwise evaluates and returns right.
  @override
  Object? visitLogicalExpr(LogicalExpr expr) {
    Object? left = evaluate(expr.left);
    // Short-circuit evaluation for 'or'
    if (expr.operator.type == TokenType.OR) {
      if (isTruthy(left)) return left;
    } else {
      // Must be AND
      if (!isTruthy(left)) return left;
    }
    return evaluate(expr.right);
  }

  /// Visitor method for evaluating a [VariableExpr].
  /// Looks up the variable's value in the current environment chain using [_environment.get].
  /// Throws [RuntimeError] if the variable is not defined.
  @override
  Object? visitVariableExpr(VariableExpr expr) {
    return _environment.get(expr.name);
  }

  // --- Helper Methods ---

  /// Determines the truthiness of an object according to Python rules.
  /// `False`, `None`, numeric zero, empty strings/lists/maps are falsey.
  /// Everything else is truthy.
  bool isTruthy(Object? object) {
    if (object == null) return false; // None is falsey
    if (object is bool) return object; // Booleans are themselves
    if (object is num) return object != 0; // Zero is falsey, others are truthy
    if (object is String) return object.isNotEmpty; // Empty string is falsey
    if (object is List) return object.isNotEmpty; // Empty list is falsey
    if (object is Map) return object.isNotEmpty; // Empty map is falsey
    // Other objects (like functions, class instances) are generally truthy
    return true;
  }

  /// Compares two objects for equality using Python's `==` semantics.
  /// Handles `None`. Performs deep comparison for lists and maps.
  /// Falls back to Dart's `==` for other types.
  bool isEqual(Object? a, Object? b) {
    if (a == null && b == null) return true; // None == None
    if (a == null || b == null) return false; // None != anything else
    // Use Dart's == operator, which works for primitives (num, bool, String)
    // and relies on List/Map implementations (which compare by identity by default).
    // For deep comparison of lists/maps, we'd need custom logic.
    // Python's == does deep comparison for lists/tuples/dicts. Let's mimic that.
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!isEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (var key in a.keys) {
        if (!b.containsKey(key) || !isEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    return a == b; // Fallback to Dart's default equality for other types
  }

  /// Converts a runtime object into its string representation, similar to Python's `str()`.
  /// Handles `None`, `True`, `False`, numbers, strings, lists, maps, and callables.
  String stringify(Object? object) {
    if (object == null) return "None";
    if (object is bool) return object ? "True" : "False";
    if (object is double) {
      // Avoid trailing .0 for whole numbers when possible
      if (object.truncateToDouble() == object) {
        return object.toInt().toString();
      }
      return object.toString(); // Standard double representation
    }
    if (object is String) {
      // return "'${object.replaceAll("'", "\\'")}'"; // More like repr()
      return object; // More like str()
    }
    if (object is List) {
      // Recursively stringify elements: [item1, item2]
      return '[${object.map(stringify).join(', ')}]';
    }
    if (object is Map) {
      // {key1: value1, key2: value2}
      return '{${object.entries.map((e) => '${stringify(e.key)}: ${stringify(e.value)}').join(', ')}}';
    }
    if (object is PyCallable) {
      return object.toString(); // Use the custom toString from PyFunction/NativeFunction
    }
    // Add custom stringification for other types (classes, etc.) if needed

    // Default fallback using Dart's toString()
    return object.toString();
  }
}
