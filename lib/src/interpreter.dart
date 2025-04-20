import 'dart:math';
import 'dart:async';

import 'ast_nodes.dart';
import 'lexer.dart';
import 'native_methods.dart' as native_methods;

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

// StopExecution Exception thrown when the interpreter gets interrupted
class StopExecution implements Exception {
  final String message = "Execution stopped by user request.";
  StopExecution();
  @override
  String toString() => message;
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

/// Signatue of native methods
typedef PyCallableNativeImpl = Object? Function(
  Interpreter interpreter, Object receiver, List<Object?> positionalArgs, Map<String, Object?> keywordArgs
);  

/// Represents a built-in method bound to a specific native Dart object (like a List or String).
///
/// This allows expressions like `my_list.append(item)` to work. The attribute access
/// `my_list.append` evaluates to an instance of this class, which is then called.
class PyBoundNativeMethod extends PyCallable {
  /// The native Dart object instance this method is bound to (e.g., the List).
  final Object receiver;
  /// The actual implementation function for this native method.
  final PyCallableNativeImpl implementation;
  /// The name of the method (e.g., "append"), used for error messages and toString.
  final String methodName;

  PyBoundNativeMethod(this.receiver, this.implementation, this.methodName);

  /// Calls the stored native implementation function.
  ///
  /// It passes the interpreter, the bound receiver object, and the evaluated
  /// arguments from the Python call site to the specialized implementation function
  /// (like `_listAppend`, `_listInsert`, etc.).
  @override
  Object? call(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs) {
    try {
      // Delegate to the specific static implementation function stored
      return implementation(interpreter, receiver, positionalArgs, keywordArgs);
    } on RuntimeError {
      rethrow; // Propagate runtime errors directly
    } catch (e) {
      // Wrap other potential errors from the implementation
      Token errorToken = Token(TokenType.IDENTIFIER, methodName, null, 0, 0);
      throw RuntimeError(errorToken, "Error executing native method '$methodName': $e");
    }
  }
  @override
  String toString() => "<built-in method $methodName of ${receiver.runtimeType}>";
}

/// Represents a class definition at runtime.
class PyClass extends PyCallable {
  final String name;
  final PyClass? superclass;
  final Map<String, PyFunction> methods;

  PyClass(this.name, this.superclass, this.methods);

  /// Finds a method in this class or its superclasses.
  PyFunction? findMethod(String name) {
    if (methods.containsKey(name)) {
      return methods[name];
    }
    // Recurse up the inheritance chain
    if (superclass != null) {
      return superclass!.findMethod(name);
    }
    return null;
  }

  /// Called when the class itself is called (e.g., `MyClass()`). Creates an instance.
  @override
  Object? call(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs) {
    PyInstance instance = PyInstance(this); // Create the instance
    // Look for and call the initializer (__init__)
    PyFunction? initializer = findMethod("__init__");
    if (initializer != null) {
      // Bind the initializer to the instance and call it
      initializer.bind(instance).call(interpreter, positionalArgs, keywordArgs);
    } else if (positionalArgs.isNotEmpty || keywordArgs.isNotEmpty){
      // No __init__, but arguments were passed to the class constructor
      Token classToken = Token(TokenType.IDENTIFIER, name, null, 0, 0);
      throw RuntimeError(classToken, "TypeError: object constructor takes no arguments");
    }
    return instance; // Return the new instance
  }
  @override
  String toString() => "<class '$name'>";
}

/// Represents an instance of a [PyClass] at runtime.
class PyInstance {
  final PyClass klass; // The class this instance belongs to
  final Map<String, Object?> fields = {}; // Instance attributes
  PyInstance(this.klass);
  /// Gets an attribute or method from the instance.
  Object? get(Token name) {
    // 1. Check instance fields first
    if (fields.containsKey(name.lexeme)) {
      return fields[name.lexeme];
    }
    // 2. If not in fields, look for a method in the class hierarchy
    PyFunction? method = klass.findMethod(name.lexeme);
    if (method != null) {
      return method.bind(this); // Return a bound method
    }
    // 3. Not found
    throw RuntimeError(name, "AttributeError: '${klass.name}' object has no attribute '${name.lexeme}'");
  }
  /// Sets an attribute on the instance.
  void set(Token name, Object? value) {
    fields[name.lexeme] = value;
  }
  @override
  String toString() => "<${klass.name} object>"; // Basic representation
}

/// Represents a method that has been bound to a specific instance (`self`).
class PyBoundMethod extends PyCallable {
  final PyInstance receiver; // The instance ('self')
  final PyFunction method;   // The original PyFunction (method definition)
  PyBoundMethod(this.receiver, this.method);
  @override
  Object? call(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs) {
    // When calling a bound method, the interpreter needs to execute the
    // original function's code within an environment where 'self' is defined.
    // We pass the receiver (self) to the method's call implementation.
    return method.call(interpreter, positionalArgs, keywordArgs, receiver: receiver);
  }
  @override
  String toString() => "<bound method ${method.declaration?.name.lexeme} of ${receiver.toString()}>";
}

/// Represents a user-defined function declared using the `def` keyword
/// or the expression body of al `lambda`function.
///
/// It stores the function's definition ([declaration]) from the AST and captures
/// the lexical environment ([closure]) where the function was defined. This closure
/// is used to resolve non-local variables when the function is called.
class PyFunction extends PyCallable {
  /// The AST node representing the function definition (`def name(...) ...`).
  final FunctionStmt? declaration;
  /// expression in case of lambda function
  final Expr? expressionBody;
  /// parameters of function declaration or lambda function
  final List<Parameter> params;
  
  /// The environment that was active when the function was defined.
  /// This enables lexical scoping (closures).
  final Environment closure;

  /// Flag indicating if this function is an initializer (e.g., `__init__` if classes were supported).
  final bool isInitializer; // Currently unused but kept for potential class extension

  /// Constructor for DEF function
  PyFunction.fromDef(FunctionStmt this.declaration, this.closure, {this.isInitializer = false})
    : expressionBody = null, // expressionBody is null for DEF
      params = declaration.params;

  // Constructor for LAMBDA function
  PyFunction.fromLambda(LambdaExpr lambdaExpr, this.closure)
    : declaration = null, // declaration is null for LAMBDA
      expressionBody = lambdaExpr.body,
      params = lambdaExpr.params,
      isInitializer = false
  {
    // Make sure that the body is an Expr but not assignment.
    // In case of an assignment, a SyntaxError should be thrown by the Parser,
    // but it is easier to detect it here.
    if (expressionBody is AssignExpr ||
      expressionBody is AugAssignExpr ||
      expressionBody is IndexSetExpr ||
      expressionBody is AttributeSetExpr) {
      Token errorToken = lambdaExpr.keyword;
      throw RuntimeError(errorToken, "SyntaxError: invalid syntax (assignment in lambda)");
    }
  }

  /// Creates a [PyBoundMethod] instance linking this function to a receiver instance.
  PyBoundMethod bind(PyInstance instance) {
    return PyBoundMethod(instance, this);
  }

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
  Future<Object?> call(Interpreter interpreter, List<Object?> positionalArgs, Map<String, Object?> keywordArgs,
    {PyInstance? receiver}) async {
    Environment environment = Environment(closure);
    // --- Bind 'self' if this is a method call ---
    String? selfParamName;
    int parameterOffset = 0; // How many parameters to skip (0 or 1 for self)
    int paramsAvailableForArgs = params.length;
    if (receiver != null) {
      if (params.isEmpty && declaration!=null) {
        throw RuntimeError(declaration!.name, "TypeError: Method '${declaration!.name.lexeme}' called on instance but has no parameters (missing 'self'?)");
      }
      selfParamName = params[0].name.lexeme;
      environment.define(selfParamName, receiver);
      parameterOffset = 1; // Skip 'self' when matching against passed args
      paramsAvailableForArgs = params.length - 1;
    }
    // --- Argument to Parameter Binding ---
    int positionalArgIndex = 0;
    Set<String> usedKeywordArgs = {}; // Track keywords used to detect unexpected ones
    Set<String> assignedParams = {}; // Track params assigned to prevent duplicates
    StarArgsParameter? starArgsParam;
    StarStarKwargsParameter? starStarKwargsParam;
    List collectedStarArgs = [];
    Map<String, Object?> collectedKwargs = {};

    // Iterate through the function's DECLARED parameters, skipping 'self' if bound
    for (int i = parameterOffset; i < params.length; i++) {
      Parameter param = params[i];
      String name = param.name.lexeme;

      if (param is RequiredParameter) {
        if (positionalArgIndex < positionalArgs.length) {
          // Argum  ent provided positionally
          if (keywordArgs.containsKey(name)) {
            throw RuntimeError(param.name, "Argument '$name' given both positionally and as keyword.");
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
          throw RuntimeError(declaration?.name ?? (expressionBody! as LambdaExpr).keyword,
            "Missing required argument: '$name'.");
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
            defaultValue = await interpreter.evaluateInEnvironment(
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
        starStarKwargsParam = param; // Store to collect remaining keywords later
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
        int maxPositional = params
                .where((p) => p is RequiredParameter || p is OptionalParameter)
                .length;
        throw RuntimeError(
          declaration?.name ?? (expressionBody! as LambdaExpr).keyword,
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
          bool paramExists = params.any(
            (p) => p.name.lexeme == key,
          );
          if (paramExists) {
            // This case *shouldn't* happen if logic above is correct
            // (means keyword arg matched param name but wasn't used)
            throw RuntimeError(
              declaration?.name ?? (expressionBody! as LambdaExpr).keyword,
              "Internal error: Keyword argument '$key' conflict.",
            );
          } else {
            throw RuntimeError(
              declaration?.name ?? (expressionBody! as LambdaExpr).keyword,
              // Try to find token for keyword if possible from parser? Hard here.
              "Got an unexpected keyword argument '$key'.",
            );
          }
        }
      }
    }

    if (expressionBody != null) { // execute lambda body
      try {
        return await interpreter.evaluateInEnvironment(expressionBody!, environment);
      } catch (e) {
        Token errorToken = Token(TokenType.LAMBDA, 'lambda', null, 0, 0);
        throw RuntimeError(errorToken, "Error during lambda execution: $e");
      }
    } else if (declaration != null) { // execute (def-) function
      try {
        await interpreter.executeBlock(declaration!.body, environment);
      } on ReturnValue catch (returnValue) {
          return isInitializer ? null : returnValue.value;
      }
      return null;
    } else {
      // should not happen
      throw StateError("PyFunction has neither declaration nor expression body.");
    }
  }

  @override
  String toString() => declaration != null
    ? '<fn ${declaration!.name.lexeme}>'
    : "<lambda>";
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

  /// Creates a new environment.
  /// [enclosing] specifies the parent scope (optional, defaults to null for global).
  Environment([this.enclosing]);

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

  /// flag to stop the execution
  bool _shouldStop = false;
  bool get shouldStop => _shouldStop;
  int _lastYieldTimestamp = 0;
  final int _yieldIntervalMs = 200;

  /// Creates a new Interpreter instance.
  /// Initializes the global environment and defines built-in functions like `print` and `range`.
  Interpreter() {
    _environment = globals; // Start in global scope
    
    // Register all built-in functions
    _registerBuiltin("print", NativeFunction(_printBuiltin));
    _registerBuiltin("range", NativeFunction(_rangeBuiltin));
    _registerBuiltin("len", NativeFunction(_lenBuiltin));
    _registerBuiltin("str", NativeFunction(_strBuiltin));
    _registerBuiltin("int", NativeFunction(_intBuiltin));
    _registerBuiltin("float", NativeFunction(_floatBuiltin));
    _registerBuiltin("bool", NativeFunction(_boolBuiltin));
    _registerBuiltin("type", NativeFunction(_typeBuiltin));
    _registerBuiltin("abs", NativeFunction(_absBuiltin));
    //_registerBuiltin("input", NativeFunction(_inputBuiltin));
    _registerBuiltin("list", NativeFunction(_listBuiltin));
    _registerBuiltin("dict", NativeFunction(_dictBuiltin));
    _registerBuiltin("round", NativeFunction(_roundBuiltin));
    _registerBuiltin("min", NativeFunction(_minBuiltin));
    _registerBuiltin("max", NativeFunction(_maxBuiltin));
    _registerBuiltin("sum", NativeFunction(_sumBuiltin));
    _registerBuiltin("repr", NativeFunction(_reprBuiltin));
  }

  // Helper to yield and checking the stop flag
  Future<void> _yieldAndCheckStop() async {
    if (_shouldStop) {
      throw StopExecution();
    }
    // Event loop gets control to allow for ui updates etc.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastYieldTimestamp > _yieldIntervalMs) {
      _lastYieldTimestamp = now;
      await Future.delayed(Duration.zero);
    }
    // check again, in case stop was requested during delay
    if (_shouldStop) {
      throw StopExecution();
    }
  }

  /// Helper to define built-ins in the global environment.
  void _registerBuiltin(String name, PyCallable callable) {
    globals.define(name, callable);
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

  /// Helper to get a predictable type name string used by type() and error messages.
  String getTypeString(Object? obj) {
     if (obj == null) return 'NoneType';
     if (obj is bool) return 'bool';
     if (obj is int) return 'int';
     if (obj is double) return 'float';
     if (obj is String) return 'str';
     if (obj is List) return 'list';
     if (obj is Map) return 'dict';
     if (obj is PyFunction) return 'function';
     if (obj is NativeFunction) return 'builtin_function_or_method';
     if (obj is PyInstance) return obj.klass.name;
     if (obj is PyClass) return 'type';
     return 'object'; // Default fallback
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

  /// Implementation of `len(s)`
  static Object? _lenBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    native_methods.checkNumArgs('len', positionalArgs, keywordArgs, required: 1);
    final arg = positionalArgs[0];
    if (arg is String) return arg.length;
    if (arg is List) return arg.length;
    if (arg is Map) return arg.length;

    throw RuntimeError(builtInToken('len'),
      "TypeError: object of type '${interpreter.getTypeString(arg)}' has no len()",
    );
  }

  /// Implementation of `str(object='')`
  static Object? _strBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('str', positionalArgs, keywordArgs, maxOptional: 1);
    return positionalArgs.isEmpty ? "" : interpreter.stringify(positionalArgs[0]);
  }

  /// Implementation of `int(x=0, base=10)`
  static Object? _intBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('int', positionalArgs, keywordArgs, maxOptional: 2);
    if (positionalArgs.isEmpty) return 0;
    final value = positionalArgs[0];
    int? base = 10;

    if (positionalArgs.length > 1) {
      final baseArg = positionalArgs[1];
      if (baseArg is int) base = baseArg;
      else throw RuntimeError(builtInToken('int'), "TypeError: 'base' argument must be an integer");
      if (value is! String) throw RuntimeError(builtInToken('int'), "TypeError: int() can't convert non-string with explicit base");
      if (base != 0 && (base < 2 || base > 36)) throw RuntimeError(builtInToken('int'), "ValueError: int() base must be >= 2 and <= 36, or 0");
    }

    if (value is int && base == 10) return value; // Common case optimization
    if (value is double && base == 10) return value.truncate();
    if (value is bool && base == 10) return value ? 1 : 0;

    if (value is String) {
      String strValue = value.trim();
      int effectiveBase = base;
      String? prefix;

      if (strValue.startsWith('0x') || strValue.startsWith('0X')) { prefix = '0x'; effectiveBase = 16; }
      else if (strValue.startsWith('0b') || strValue.startsWith('0B')) { prefix = '0b'; effectiveBase = 2; }
      else if (strValue.startsWith('0o') || strValue.startsWith('0O')) { prefix = '0o'; effectiveBase = 8; }

      if (base == 0) { // Auto-detect base only if base=0
          if (prefix == null) effectiveBase = 10;
          else strValue = strValue.substring(2);
      } else if (prefix != null && base == effectiveBase) {
          // Allow explicit base matching prefix, remove prefix
          strValue = strValue.substring(2);
      } else if (prefix != null && base != effectiveBase) {
          // Mismatch: e.g., int('0x10', base=10) is an error in Python
          throw RuntimeError(builtInToken('int'), "ValueError: invalid literal for int() with base $base: '$value'");
      }
      // If base was specified (and not 0) and there's no prefix, use the specified base directly.

      if (strValue.isEmpty && prefix != null) { // Handles "0x", "0b", "0o"
         throw RuntimeError(builtInToken('int'), "ValueError: invalid literal for int() with base $effectiveBase: '$value'");
      }

      int? parsedInt = int.tryParse(strValue, radix: effectiveBase);
      if (parsedInt == null) {
        throw RuntimeError(builtInToken('int'), "ValueError: invalid literal for int() with base $effectiveBase: '$value'");
      }
      return parsedInt;
    }

    throw RuntimeError(builtInToken('int'), "TypeError: int() argument must be a string, a bytes-like object or a number, not '${interpreter.getTypeString(value)}'");
  }

  /// Implementation of `float(x=0.0)`
  static Object? _floatBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('float', positionalArgs, keywordArgs, maxOptional: 1);
    if (positionalArgs.isEmpty) return 0.0;
    final value = positionalArgs[0];

    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is bool) return value ? 1.0 : 0.0;
    if (value is String) {
      String strValue = value.trim().toLowerCase();
      if (strValue == 'inf' || strValue == '+inf') return double.infinity;
      if (strValue == '-inf') return double.negativeInfinity;
      if (strValue == 'nan') return double.nan;
      double? parsedFloat = double.tryParse(value); // Use original case
      if (parsedFloat != null) return parsedFloat;
      else throw RuntimeError(builtInToken('float'), "ValueError: could not convert string to float: '$value'");
    }
    throw RuntimeError(builtInToken('float'), "TypeError: float() argument must be a string or a number, not '${interpreter.getTypeString(value)}'");
  }

  /// Implementation of `bool(x=False)`
  static Object? _boolBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('bool', positionalArgs, keywordArgs, maxOptional: 1);
    return positionalArgs.isEmpty ? false : interpreter.isTruthy(positionalArgs[0]);
  }

  /// Implementation of `type(object)`
  static Object? _typeBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('type', positionalArgs, keywordArgs, required: 1);
    return "<class '${interpreter.getTypeString(positionalArgs[0])}'>";
  }

  /// Implementation of `abs(x)`
  static Object? _absBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('abs', positionalArgs, keywordArgs, required: 1);
    final arg = positionalArgs[0];
    if (arg is int) return arg.abs();
    if (arg is double) return arg.abs();
    if (arg is bool) return arg ? 1 : 0; // abs(True)==1, abs(False)==0
    throw RuntimeError(builtInToken('abs'), "TypeError: bad operand type for abs(): '${interpreter.getTypeString(arg)}'");
  }

  /// Implementation of `input([prompt])`
  // static Object? _inputBuiltin(
  //   Interpreter interpreter,
  //   List<Object?> positionalArgs,
  //   Map<String, Object?> keywordArgs,
  // ) {
  //   _checkNumArgs('input', positionalArgs, keywordArgs, maxOptional: 1);
  //   String prompt = positionalArgs.isEmpty ? "" : interpreter.stringify(positionalArgs[0]);
  //   // Ensure prompt is printed via the interpreter's mechanism if available
  //   interpreter._printOutput?.call(prompt);
  //   if (interpreter._printOutput == null) {
  //      stdout.write(prompt); // Fallback to direct stdout
  //   }
  //   String? line = stdin.readLineSync();
  //   if (line == null) throw RuntimeError(_builtInToken('input'), "EOFError: EOF when reading a line");
  //   return line;
  // }

  /// Implementation of `list([iterable])`
  static Object? _listBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('list', positionalArgs, keywordArgs, maxOptional: 1);
    if (positionalArgs.isEmpty) return <Object?>[]; // New empty list

    final iterable = positionalArgs[0];
    if (iterable is List) return List.from(iterable); // Return a shallow copy
    if (iterable is String) return iterable.split(''); // List of characters
    if (iterable is Map) return iterable.keys.toList(); // List of keys

    // Check if it's an iterable result from range() which is already a List
    // No, range() directly returns List<int> in this impl.

    // TODO: Handle other potential iterable types if added (e.g., custom iterators)

    throw RuntimeError(builtInToken('list'), "TypeError: '${interpreter.getTypeString(iterable)}' object is not iterable");
  }

  /// Implementation of `dict(**kwarg)` / `dict(mapping)` / `dict(iterable)`
  /// Simplified: Only supports `dict()` or `dict(map)` for now.
  static Object? _dictBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    // Python's dict is versatile. This is a simplified version.
    // It primarily handles dict() -> {} and dict(existing_map) -> copy.
    _checkNumArgs('dict', positionalArgs, keywordArgs, maxOptional: 1, allowKeywords: true); // 0 or 1 positional

    final Map result = {};

    if (positionalArgs.isNotEmpty) {
      final arg = positionalArgs[0];
      if (arg is Map) {
        result.addAll(arg);
      } else if (arg is List) {
        for (var item in arg) {
          if ((item is List || item is String) && item.length == 2) {
            final key = item[0];
            final value = item[1];
            if (!interpreter.isHashable(key)) {
              throw RuntimeError(builtInToken('dict'), "TypeError: unhashable type: '${interpreter.getTypeString(key)}'");
            }
            result[key] = value;
          } else if (item is List || item is String) {
            throw RuntimeError(builtInToken('dict'),
              "ValueError: dictionary update sequence element #${arg.indexOf(item)} has length ${item.length}; 2 is required");
          } else {
            throw RuntimeError(builtInToken('dict'), "ValueError: cannot convert dictionary update sequence element #${arg.indexOf(item)} to a sequence");
          }
        }
      } else {
        throw RuntimeError(builtInToken('dict'), "TypeError: '${arg.runtimeType}' object is not iterable");
      }
    }

    keywordArgs.forEach((key, value) {
      // Keys from keyword args are always strings and thus hashable in our context
      result[key] = value;
    });

    return result;
    
  }

  /// Implementation of `round(number[, ndigits])`
  /// Implements Python 3's "round half to even" behavior.
  static Object? _roundBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('round', positionalArgs, keywordArgs, required: 1, maxOptional: 1);
    _checkNoKeywords('round', keywordArgs);

    final numberArg = positionalArgs[0];
    int ndigits = 0; // Default ndigits

    if (positionalArgs.length == 2) {
        final ndigitsArg = positionalArgs[1];
        if (ndigitsArg == null) { // round(x, None) -> behaves like ndigits=0 but returns int
            ndigits = 0; // Will return int later
        } else if (ndigitsArg is int) {
            ndigits = ndigitsArg;
        } else if (ndigitsArg is bool) { // Python allows bools here too
             ndigits = ndigitsArg ? 1: 0;
        }
         else {
            throw RuntimeError(builtInToken('round'), "TypeError: 'ndigits' argument must be an integer, not '${interpreter.getTypeString(ndigitsArg)}'");
        }
    }

    num number; // Use num to handle int/double input
    if (numberArg is num) {
        number = numberArg;
    } else if (numberArg is bool) {
        number = numberArg ? 1 : 0;
    } else {
        throw RuntimeError(builtInToken('round'), "TypeError: type ${interpreter.getTypeString(numberArg)} not supported");
    }
    // --- Perform Rounding ---
    num factor = pow(10, ndigits);
    // Handle potential precision issues by working with scaled value
    // Add a small epsilon check for near-half cases if needed, but start simple.
    num scaledValue = number * factor;
    // Check if the scaled value is exactly halfway between two integers
    num remainder = scaledValue.remainder(1.0);
    num roundedScaledValue;
    if ((remainder.abs() - 0.5).abs() < 1e-15) { // Check if effectively x.5 (handle float precision)
      int floorInt = scaledValue.floor().toInt();
      int ceilInt = scaledValue.ceil().toInt();
      // Choose the even neighbor
      if (floorInt % 2 == 0) { // is floor even?
          roundedScaledValue = floorInt;
      } else {
          // If floor is odd, the ceiling must be the even neighbor
          roundedScaledValue = ceilInt;
      }
    } else {
      // Standard rounding (away from zero for > .5, towards zero for < .5)
      // Dart's round() does round half *away* from zero. We can use it here.
      roundedScaledValue = scaledValue.round();
    }
    // --- Determine Return Type and Value ---
    if (ndigits <= 0) { // Return int if ndigits is 0 or negative
      // For negative ndigits, we need to potentially return float if factor is not 1
       num result = roundedScaledValue / factor;
       // If ndigits was 0, return int. If negative, check if result is whole number.
       if (ndigits == 0 || result.truncateToDouble() == result) {
           return result.toInt();
       } else {
           // Should not happen for ndigits <= 0 after rounding logic? Test this.
           // Python seems to return float here if original was float.
           // Let's return int if it's a whole number result.
           return result.toInt(); // Return int for ndigits <= 0
       }

    } else { // Return float if ndigits > 0
        // The result should already be correctly scaled
        num result = roundedScaledValue / factor;
        // Ensure it's a double, even if it looks like an integer (e.g., round(123.0, 1))
        return result.toDouble();
    }
  }

  /// Implementation of `min(iterable, *[, key])` or `min(arg1, arg2, *args[, key])`
  /// Simplified: No key function. Handles iterable or multiple args.
  static Object? _minBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNoKeywords('min', keywordArgs); // Key function not supported yet
    if (positionalArgs.isEmpty) throw RuntimeError(builtInToken('min'), "TypeError: min expected 1 argument, got 0");

    Iterable<Object?>? valuesToCompare;
    if (positionalArgs.length == 1) {
      // Single argument version: min(iterable)
      final arg = positionalArgs[0];
      if (arg is List) valuesToCompare = arg;
      else if (arg is String) valuesToCompare = arg.split('');
      else if (arg is Map) valuesToCompare = arg.keys;
      else throw RuntimeError(builtInToken('min'), "TypeError: '${interpreter.getTypeString(arg)}' object is not iterable");
    } else {
      // Multiple argument version: min(arg1, arg2, ...)
      valuesToCompare = positionalArgs;
    }

    if (valuesToCompare.isEmpty) throw RuntimeError(builtInToken('min'), "ValueError: min() arg is an empty sequence");

    Object? minValue = valuesToCompare.first;
    for (final value in valuesToCompare.skip(1)) {
      try {
        if (interpreter._compareValues(value, minValue) < 0) {
          minValue = value;
        }
      } on RuntimeError { rethrow; } // Propagate comparison errors
        catch(e) { // Catch unexpected comparison issues
             throw RuntimeError(builtInToken('min'), "Error during comparison in min(): $e");
        }
    }
    return minValue;
  }

  /// Implementation of `max(iterable, *[, key])` or `max(arg1, arg2, *args[, key])`
  /// Simplified: No key function. Handles iterable or multiple args.
   static Object? _maxBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNoKeywords('max', keywordArgs); // Key function not supported yet
    if (positionalArgs.isEmpty) throw RuntimeError(builtInToken('max'), "TypeError: max expected 1 argument, got 0");

    Iterable<Object?>? valuesToCompare;
    if (positionalArgs.length == 1) {
      final arg = positionalArgs[0];
      if (arg is List) valuesToCompare = arg;
      else if (arg is String) valuesToCompare = arg.split('');
      else if (arg is Map) valuesToCompare = arg.keys;
      else throw RuntimeError(builtInToken('max'), "TypeError: '${interpreter.getTypeString(arg)}' object is not iterable");
    } else {
      valuesToCompare = positionalArgs;
    }

    if (valuesToCompare.isEmpty) throw RuntimeError(builtInToken('max'), "ValueError: max() arg is an empty sequence");

    Object? maxValue = valuesToCompare.first;
    for (final value in valuesToCompare.skip(1)) {
       try {
        if (interpreter._compareValues(value, maxValue) > 0) {
          maxValue = value;
        }
      } on RuntimeError { rethrow; }
        catch(e) {
             throw RuntimeError(builtInToken('max'), "Error during comparison in max(): $e");
        }
    }
    return maxValue;
  }

  /// Implementation of `sum(iterable[, start])`
  /// Simplified: start defaults to 0.
  static Object? _sumBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('sum', positionalArgs, keywordArgs, required: 1, maxOptional: 1);
    _checkNoKeywords('sum', keywordArgs);

    final iterable = positionalArgs[0];
    Object? start = (positionalArgs.length > 1) ? positionalArgs[1] : 0; // Default start is 0

    Iterable<Object?>? valuesToSum;
    if (iterable is List) valuesToSum = iterable;
    else if (iterable is Map) valuesToSum = iterable.values; // Sum values, not keys
    // Cannot sum strings in Python
    else throw RuntimeError(builtInToken('sum'), "TypeError: '${interpreter.getTypeString(iterable)}' object is not iterable or not summable");

    if (valuesToSum.isEmpty && start == 0) return 0; // Mimic python sum([]) == 0

    Object? currentSum = start;
    Token plusOperatorToken = Token(TokenType.PLUS, '+', null, 0, 0);
    for (final value in valuesToSum) {
       // Try adding - mimics '+' operator logic
       try {
          // Need a way to perform '+' operation reliably
          currentSum = interpreter._performBinaryOperation(plusOperatorToken, currentSum, value, TokenType.PLUS);
       } on RuntimeError catch(e) {
           // Improve error message for sum() specifically
           if (e.message.contains("unsupported operand type(s) for +")) {
               throw RuntimeError(builtInToken('sum'),
                 "TypeError: unsupported operand type(s) for +: '${interpreter.getTypeString(currentSum)}' and '${interpreter.getTypeString(value)}' in sum()"
               );
           }
           rethrow; // Re-throw other RuntimeErrors
       }
    }
    return currentSum;
  }

  /// Implementation of `repr(object)`
  static Object? _reprBuiltin(
    Interpreter interpreter,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs,
  ) {
    _checkNumArgs('repr', positionalArgs, keywordArgs, required: 1);
    // Use a dedicated repr helper for more accurate representations
    return interpreter.repr(positionalArgs[0]);
  }

  // --- Helper for accurate string representation (repr) ---
  String repr(Object? object) {
      if (object == null) return "None";
      if (object is bool) return object ? "True" : "False";
      if (object is String) {
          // Add quotes and escape internal quotes/backslashes
          String escaped = object
              .replaceAll('\\', '\\\\')
              .replaceAll("'", "\\'")
              .replaceAll('\n', '\\n')
              .replaceAll('\r', '\\r')
              .replaceAll('\t', '\\t');
          // Prefer single quotes unless string contains single quotes but not double
          if (escaped.contains("'") && !escaped.contains('"')) {
              return '"$escaped"';
          }
          return "'$escaped'";
      }
      if (object is List) return '[${object.map(repr).join(', ')}]';
      if (object is Map) return '{${object.entries.map((e) => '${repr(e.key)}: ${repr(e.value)}').join(', ')}}';

      // Fallback for other types (numbers, functions) - could refine number formatting
      return stringify(object);
  }

  /// Creates a dummy token for error reporting within built-ins.
  static Token builtInToken(String name) {
    return Token(TokenType.IDENTIFIER, name, null, 0, 0); // No accurate location info
  }

  /// Generic argument count and keyword checker for built-ins.
  static void _checkNumArgs(
    String funcName,
    List<Object?> positionalArgs,
    Map<String, Object?> keywordArgs, // Keep this even if unused by checker for now
    {int required = 0, int maxOptional = 0, bool allowKeywords = false})
  {
    if (!allowKeywords && keywordArgs.isNotEmpty) {
      throw RuntimeError(builtInToken(funcName), "TypeError: $funcName() takes no keyword arguments");
    }
    int totalAllowed = required + maxOptional;
    int actual = positionalArgs.length;

    if (maxOptional == -1) { // Indicates variable args like min/max
       if (actual < required) {
            throw RuntimeError(builtInToken(funcName), "TypeError: $funcName() expected at least $required arguments, got $actual");
       }
       // Max check doesn't apply
    } else { // Fixed number of optional args
        if (actual < required) {
            String takes = "at least $required";
             if (maxOptional == 0) takes = "exactly $required";
            throw RuntimeError(builtInToken(funcName), "TypeError: $funcName() takes $takes positional arguments ($actual given)");
        }
        if (actual > totalAllowed) {
            String takes = "exactly $required";
            if (maxOptional > 0 && required > 0) takes = "from $required to $totalAllowed";
            else if (maxOptional > 0) takes = "at most $totalAllowed";
            throw RuntimeError(builtInToken(funcName), "TypeError: $funcName() takes $takes positional arguments ($actual given)");
        }
    }
  }

  /// Specific checker for functions that take NO keywords.
  static void _checkNoKeywords(String funcName, Map<String, Object?> keywordArgs) {
      if (keywordArgs.isNotEmpty) {
           throw RuntimeError(builtInToken(funcName), "TypeError: $funcName() takes no keyword arguments");
      }
  }

  // --- Comparison Helper used by min/max ---
  int _compareValues(Object? left, Object? right) {
     try {
         // Use the logic from BinaryExpr comparison
         return _compare(left, right, builtInToken('<')); // Operator token is just for error msg context
     } catch (e) {
          // Rethrow comparison errors with a more generic message if needed
          throw RuntimeError(builtInToken('comparison'), "Error during comparison: $e");
     }
  }

  // --- Binary Operation Helper used by sum ---
   Object? _performBinaryOperation(Token operatorToken, Object? left, Object? right, TokenType opType) {
     // This duplicates logic from visitBinaryExpr slightly, could be refactored
     try {
         // Simplified call to the core arithmetic logic
         return _evaluateBinary(operatorToken, left, right);
     } catch (e) {
          // Catch and rethrow errors from the operation
          rethrow;
     }
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
  /// statements, calling [execute] for each one and yielding periodically.
  /// Catches and reports [RuntimeError]s.
  /// Allows providing optional callbacks: [printCallback] to handle `print` output,
  /// and [errorCallback] to handle runtime error messages.
  /// Use the `stop()` method to signal interruption.
  Future<void> interpret (
    List<Stmt> statements, [
    void Function(String)? printCallback,
    void Function(String)? errorCallback,
  ])  async {
    _print = printCallback ?? _printWithBuffer;
    _shouldStop = false; // Reset stop flag at the beginning
    final reportError = errorCallback ?? (String s) => print("Error: $s");

    try {
      for (final statement in statements) {
        await _yieldAndCheckStop();
        await execute(statement);
      }
    } on StopExecution catch (e) {
        print("Interpreter stopped: ${e.message}");
        reportError(e.message);
        hadRuntimeError = true;
    } on RuntimeError catch (e) {
      // TODO: Improve error reporting context (stack trace?)
      reportError(e.message); // Report runtime errors
      hadRuntimeError = true; // Assuming hadRuntimeError is defined globally for REPL
    } on ReturnValue catch (_) {
      // A ReturnValue exception should only be caught inside a function call.
      // If it reaches here, it's an error (return outside function).
      final msg = "SyntaxError: 'return' outside function";
        final token = Token(TokenType.RETURN, 'return', null, 0, 0);
        print(RuntimeError(token, msg));
        reportError(msg);
        hadRuntimeError = true;
    } catch (e, stackTrace) { // Fängt unerwartete Fehler
       final msg = "Unexpected interpreter error: $e\n$stackTrace";
       print(msg);
       reportError(msg);
       hadRuntimeError = true;
    } finally {
      _shouldStop = false; // Reset flag am Ende
    }
  }

  /// Signals the interpreter to stop execution at the next checkpoint.
  void stop() {
    print("interpreter: shouldStop!!!");
    _shouldStop = true;
  }

  // --- Statement Execution ---

  /// Executes a single [Stmt] node by dispatching to the appropriate `visit` method.
  Future<void> execute(Stmt stmt) async {
    await stmt.accept(this);
  }

  /// Executes a block of [statements] within a specific [environment].
  /// Sets the interpreter's current environment to the given one for the duration
  /// of the block's execution and restores the previous environment afterwards.
  /// Crucial for function calls and potentially other scoped constructs.
  Future<void> executeBlock(List<Stmt> statements, Environment environment) async {
    Environment previous = _environment;
    try {
      _environment = environment; // Switch to the new environment
      for (final statement in statements) {
        await _yieldAndCheckStop();
        await execute(statement);
      }
    } finally {
      _environment = previous; // Restore previous environment when block exits
    }
  }

  /// Visitor method for executing a [BlockStmt].
  /// Simply executes the statements within the current environment.
  /// Note: Scope creation is handled by the calling context (e.g., `executeBlock`).
  @override
  Future<void> visitBlockStmt(BlockStmt stmt) async {
    for (final statement in stmt.statements) {
      await _yieldAndCheckStop();
      await execute(statement);
    }
  }

  /// Visitor method for executing an [ExpressionStmt].
  /// Evaluates the expression and discards the result.
  @override
  Future<void> visitExpressionStmt(ExpressionStmt stmt) async {
    await evaluate(stmt.expression);
    await Future.value(); // need Future return type
  }

  /// Visitor method for handling a [FunctionStmt] (function definition).
  /// Creates a [PyFunction] object, capturing the current environment as its closure,
  /// and defines it in the current environment.
  @override
  Future<void> visitFunctionStmt(FunctionStmt stmt) async {
    // Create the function object, capturing the *current* environment as its closure.
    PyFunction function = PyFunction.fromDef(stmt, _environment,
      isInitializer: stmt.name.lexeme == "__init__");
    _environment.define(stmt.name.lexeme, function); // Define the function in the current scope.
    await Future.value();
  }

  @override
  Future<Object?> visitLambdaExpr(LambdaExpr expr) async {
    // Create lambda function at runtime.
    // The closure is the environment where the lambda was defined
    PyFunction lambdaFunc = PyFunction.fromLambda(expr, _environment);
    return lambdaFunc;
  }

  /// Visitor method for executing an [IfStmt].
  /// Evaluates the condition, executes the `thenBranch` if truthy.
  /// If falsey, evaluates `elif` conditions sequentially, executing the first truthy one.
  /// Executes `elseBranch` if no previous condition was met.
  @override
  Future<void> visitIfStmt(IfStmt stmt) async {
    if (isTruthy(await evaluate(stmt.condition))) {
      await execute(stmt.thenBranch); // thenBranch is likely a BlockStmt
    } else {
      bool executedElif = false;
      for (final elif in stmt.elifBranches) {
        await _yieldAndCheckStop();
        if (isTruthy(await evaluate(elif.condition))) {
          await execute(elif.thenBranch); // elif.thenBranch is likely a BlockStmt
          executedElif = true;
          break; // Execute only the first matching elif
        }
      }
      if (!executedElif && stmt.elseBranch != null) {
        await execute(stmt.elseBranch!); // elseBranch is likely a BlockStmt
      }
    }
  }

  /// Defines a class.
  @override
  Future<void> visitClassStmt(ClassStmt stmt) async {
    PyClass? superclassValue;
    Object? evaluatedSuper; // Temporary variable

    if (stmt.superclass != null) {
      evaluatedSuper = await evaluate(stmt.superclass!);
      if (evaluatedSuper is! PyClass) {
        throw RuntimeError(stmt.superclass!.name, "Superclass must be a class.");
      }
      superclassValue = evaluatedSuper;
    }

    // 1. Define class in current scope (für references within methods)
    _environment.define(stmt.name.lexeme, null); //temporary

    // 2. create environment for class body
    Environment classEnvironment = _environment; // default: enclosing environment
    if (superclassValue != null) {
      // If super class exists, create a new environment containing the current one
      // and defining "super".
      classEnvironment = Environment(_environment);
      classEnvironment.define("super", superclassValue);
    }

    // 3. Process methods in class environment
    Map<String, PyFunction> methods = {};
    // Switch to class environment temporarily for setting up method closures correctly
    Environment previousEnv = _environment;
    _environment = classEnvironment;

    for (FunctionStmt methodStmt in stmt.methods) {
      // The closure of the methode *must* be the class environment, so that 'super' can be found
      PyFunction method = PyFunction.fromDef(
        methodStmt,
        classEnvironment, // Closure is the class environment
        isInitializer: methodStmt.name.lexeme == "__init__"
      );
      methods[methodStmt.name.lexeme] = method;
      // The method need not be defined in classEnvironment,
      // because it can be found via self.method or Class.method.
    }
    // Back to enclosing environment
    _environment = previousEnv;

    // 4. Create PyClass object
    PyClass thisClass = PyClass(stmt.name.lexeme, superclassValue, methods);

    // 5. Define class in original scope, overwriting temporary null
    _environment.assign(stmt.name, thisClass);
    await Future.value();
  }

  /// Visitor method for executing a [ReturnStmt].
  /// Evaluates the optional return value and throws a [ReturnValue] exception
  /// to unwind the stack to the function call site.
  @override
  Future<void> visitReturnStmt(ReturnStmt stmt) async {
    Object? value;
    if (stmt.value != null) {
      value = await evaluate(stmt.value!); // Evaluate the return value expression
    }
    // Throw the special ReturnValue exception to unwind the stack to the function call boundary
    throw ReturnValue(value);
  }

  /// Visitor method for executing a [WhileStmt].
  /// Repeatedly evaluates the condition; if truthy, executes the body.
  /// Handles [_BreakException] and [_ContinueException] to control loop flow.
  /// Sets/resets the [_isInLoop] flag. Includes basic infinite loop protection.
  @override
  Future<void> visitWhileStmt(WhileStmt stmt) async {
     bool previousLoopState = _isInLoop; // remember if while is inside another loop
    _isInLoop = true;
    try {
      while (true) {
        await _yieldAndCheckStop();
        Object? conditionValue = await evaluate(stmt.condition);
        if (!isTruthy(conditionValue)) break;
        await _yieldAndCheckStop();
        try {
          await execute(stmt.body);
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
  Future<void> visitForStmt(ForStmt stmt) async {
    Object? iterableValue = await evaluate(stmt.iterable);
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
        await _yieldAndCheckStop();
        try {
          _environment.define(stmt.variable.lexeme, element);
          await execute(stmt.body);
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
  Future<void> visitPassStmt(PassStmt stmt) async {
    // Nothing to do
  }

  /// Visitor method for executing a [BreakStmt].
  /// Throws [_BreakException] if inside a loop, otherwise throws [RuntimeError].
  @override
  Future<void> visitBreakStmt(BreakStmt stmt) async {
    if (!_isInLoop) {
      throw RuntimeError(stmt.token, "SyntaxError: 'break' outside loop");
    }
    throw _breakException;
  }

  /// Visitor method for executing a [ContinueStmt].
  /// Throws [_ContinueException] if inside a loop, otherwise throws [RuntimeError].
  @override
  Future<void> visitContinueStmt(ContinueStmt stmt) async {
     if (!_isInLoop) {
      throw RuntimeError(stmt.token, "SyntaxError: 'continue' outside loop");
    }
    throw _continueException;
  }
    
  // --- Expression Evaluation ---

  /// Helper to evaluate an expression within a specific [environment].
  /// Used primarily for evaluating default parameter values in the correct closure scope.
  Future<Object?> evaluateInEnvironment(Expr expr, Environment environment) async {
    Environment previous = _environment;
    try {
      _environment = environment;
      return await evaluate(expr);
    } finally {
      _environment = previous;
    }
  }

  /// Evaluates a single [Expr] node by dispatching to the appropriate `visit` method.
  /// Returns the result of the expression evaluation.
  Future<Object?> evaluate(Expr expr) async {
    return await expr.accept(this);
  }

  /// Visitor method for evaluating an [AssignExpr].
  /// Evaluates the right-hand side [value], then assigns it to the variable [name]
  /// in the current environment chain using [_environment.assign]. Returns the assigned value.
  @override
  Future<Object?> visitAssignExpr(AssignExpr expr) async {
    Object? value = await evaluate(expr.value);
    // Assign in the current environment (or enclosing ones)
    _environment.assign(expr.name, value);
    return value;
  }

  /// Visitor method for evaluating an [AugAssignExpr] (e.g., `+=`, `*=`).
   /// Evaluates the target (variable or index/key) to get the current value,
   /// evaluates the right-hand side value, performs the operation,
   /// and assigns the result back to the target. Handles both variable and index targets.
  @override
  Future<Object?> visitAugAssignExpr(AugAssignExpr expr) async {
    Object? rightValue = await evaluate(expr.value);
    if (expr.target is VariableExpr) {
      VariableExpr targetVar = expr.target as VariableExpr;
      Token name = targetVar.name;
      Object? currentValue = _environment.get(name);
      Object? result = _performAugmentedOperation(expr.operator, currentValue, rightValue);
      _environment.assign(name, result);
      return result;
    } else if (expr.target is IndexGetExpr) {
      IndexGetExpr targetGet = expr.target as IndexGetExpr;
      Object? object = await evaluate(targetGet.object);
      Object? keyOrIndex = await evaluate(targetGet.index);
      Object? currentValue = _performGetOperation(object, keyOrIndex, targetGet.bracket);
      Object? result = _performAugmentedOperation(expr.operator, currentValue, rightValue);
      _performSetOperation(object, keyOrIndex, result, targetGet.bracket);  
      return result;
    } 
    // Target: Attribute (e.g., self.count += 1)
    else if (expr.target is AttributeGetExpr) {
      AttributeGetExpr targetGet = expr.target as AttributeGetExpr;
      Object? object = await evaluate(targetGet.object);
      if (object is! PyInstance) {
          throw RuntimeError(targetGet.name, "Augmented assignment target must be an instance for attribute access.");
      }
      PyInstance instance = object;
      Token name = targetGet.name;
      Object? currentValue = instance.get(name); // Use instance getter (handles method errors etc.)
      Object? result = _performAugmentedOperation(expr.operator, currentValue, rightValue);
      instance.set(name, result); // Use instance setter
      return result;
    } else {
      throw RuntimeError(expr.operator, "Invalid target for augmented assignment.");
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
      if (!isHashable(keyOrIndex)) throw RuntimeError(bracket, "TypeError: unhashable type: '${keyOrIndex?.runtimeType ?? 'None'}'");
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
  Future<Object?>  visitUnaryExpr(UnaryExpr expr) async {
    Object? operand = await evaluate(expr.operand);
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

  /// Centralized logic for evaluating binary operations.
  Object? _evaluateBinary(Token operator, Object? left, Object? right) {
    void checkNumbers() {
      if (left is! num || right is! num) {
        throw RuntimeError(operator,"TypeError: unsupported operand type(s) for ${operator.lexeme}: '${getTypeString(left)}' and '${getTypeString(right)}'");
      }
    }
    void checkInts() {
      if (left is! int || right is! int) {
        throw RuntimeError(operator, "TypeError: unsupported operand type(s) for ${operator.lexeme}: '${getTypeString(left)}' and '${getTypeString(right)}'. Must be integers.");
      }
    }
    void checkComparable() {
      if (!((left is num && right is num) || (left is String && right is String))) {
        throw RuntimeError(operator, "TypeError: '${operator.lexeme}' not supported between instances of '${getTypeString(left)}' and '${getTypeString(right)}'");
      }
    }
    switch (operator.type) {
      case TokenType.MINUS: checkNumbers(); return (left as num) - (right as num);
      case TokenType.PLUS:
        if (left is num && right is num) return left + right;
        if (left is String && right is String) return left + right;
        if (left is List && right is List) return [...left, ...right];
        throw RuntimeError(operator, "TypeError: unsupported operand type(s) for +: '${getTypeString(left)}' and '${getTypeString(right)}'");
      case TokenType.SLASH:
        checkNumbers();
        if (_isZero(right)) {
          throw RuntimeError(operator,"ZeroDivisionError: float division by zero");
        }
        return (left as num).toDouble() / (right as num).toDouble();
      case TokenType.SLASH_SLASH:
        checkNumbers();
        if (_isZero(right)) {
          throw RuntimeError(operator,"ZeroDivisionError: integer division or modulo by zero");
        } return (left as num) ~/ (right as num);
      case TokenType.STAR:
        if (left is num && right is num) return left * right;
        if ((left is String || left is List) && right is int) return _multiplySequence(left!, right, operator);
        if (left is int && (right is String || right is List)) return _multiplySequence(right!, left, operator);
        throw RuntimeError(operator, "TypeError: unsupported operand type(s) for *: '${getTypeString(left)}' and '${getTypeString(right)}'");
      case TokenType.STAR_STAR:
        checkNumbers();
        return pow(left as num, right as num); // Might need try-catch for domain errors
      case TokenType.PERCENT:
        checkNumbers();
        if (_isZero(right)) {
          throw RuntimeError(operator,"ZeroDivisionError: integer division or modulo by zero");
        } return _pythonModulo(left as num, right as num);
      case TokenType.GREATER: checkComparable(); return _compare(left, right, operator) > 0;
      case TokenType.GREATER_EQUAL: checkComparable(); return _compare(left, right, operator) >= 0;
      case TokenType.LESS: checkComparable(); return _compare(left, right, operator) < 0;
      case TokenType.LESS_EQUAL: checkComparable(); return _compare(left, right, operator) <= 0;
      case TokenType.BANG_EQUAL: return !isEqual(left, right);
      case TokenType.EQUAL_EQUAL: return isEqual(left, right);

      case TokenType.AMPERSAND: checkInts(); return (left as int) & (right as int);
      case TokenType.PIPE: checkInts(); return (left as int) | (right as int);
      case TokenType.CARET: checkInts(); return (left as int) ^ (right as int);
      case TokenType.LEFT_SHIFT: checkInts(); return (left as int) << (right as int);
      case TokenType.RIGHT_SHIFT: checkInts(); return (left as int) >> (right as int);

      default: throw RuntimeError(operator, "Internal error: Unknown binary operator type ${operator.type}");
    }
  }

  bool _isZero(Object? obj) {
      return (obj is num) && obj == 0;
  }

  /// Visitor method for evaluating a [BinaryExpr] (arithmetic, comparison, bitwise).
  @override
  Future<Object?> visitBinaryExpr(BinaryExpr expr) async {
    Object? left = await evaluate(expr.left);
    Object? right = await evaluate(expr.right);
    return _evaluateBinary(expr.operator, left, right);
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
  Future<Object?> visitCallExpr(CallExpr expr) async {
    Object? callee = await evaluate(expr.callee); // Evaluate the object being called
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
        positionalArgs.add(await evaluate(argument.value));
      } else if (argument is KeywordArgument) {
        String name = argument.name.lexeme;
        if (keywordArgs.containsKey(name)) {
          throw RuntimeError(
            argument.name,
            "Duplicate keyword argument '$name' in call.",
          );
        }
        keywordArgs[name] = await evaluate(argument.value);
      }
    }

    // Call the callable object using the collected arguments
    try {
      // The PyCallable's call method is responsible for matching args to params
      // It remains synchronous.
      return await function.call(this, positionalArgs, keywordArgs);
    } on ReturnValue catch (returnValue) {
      // Catch return value *inside* the synchronous part of visitCallExpr
      return returnValue.value;
    } on RuntimeError {
      rethrow; // propagate RuntimeErrors directly
    } catch (e) {
      // Wrap other potential Dart errors
      throw RuntimeError(expr.paren, "Error during function execution: $e");
    }
  }

  /// Visitor method for evaluating a [IndexGetExpr] (indexing like `obj[key]`).
  /// Evaluates the [object] and the [index] expressions. Performs list, string,
  /// or dictionary lookup based on the object's type.
  /// Throws [RuntimeError] for invalid types, index out of bounds, or key errors.
  @override
  Future<Object?> visitIndexGetExpr(IndexGetExpr expr) async {
    // Handles obj[index]
    Object? object = await evaluate(expr.object);
    Object? key = await evaluate(expr.index); // The index or key

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

  /// Visitor method for evaluating a [IndexSetExpr] (item assignment like `obj[key] = value`).
  /// Evaluates the object, index/key, and value. Performs assignment on lists or dictionaries.
  /// Throws [RuntimeError] for invalid types (e.g., string assignment), index errors, or unhashable keys.
  @override
  Future<Object?> visitIndexSetExpr(IndexSetExpr expr) async {
    Object? targetObject = await evaluate(expr.object);
    Object? indexOrKey = await evaluate(expr.index);
    Object? valueToSet = await evaluate(expr.value);

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
      if (!isHashable(indexOrKey)) {
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
  Future<Object?> visitGroupingExpr(GroupingExpr expr) async {
    return await evaluate(expr.expression);
  }

  /// Visitor method for evaluating a [LiteralExpr] (numbers, strings, True, False, None).
  /// Returns the literal value directly.
  @override
  Future<Object?> visitLiteralExpr(LiteralExpr expr) async {
    return expr.value;
  }

  /// Visitor method for evaluating a [ListLiteralExpr] (`[...]`).
  /// Evaluates each element expression and returns a new Dart [List].
  @override
  Future<Object?> visitListLiteralExpr(ListLiteralExpr expr) async {
    List<Object?> elements = [];
    for (Expr elementExpr in expr.elements) {
      elements.add(await evaluate(elementExpr));
    }
    return elements;
  }

  /// Visitor method for evaluating a [DictLiteralExpr] (`{...}`).
  /// Evaluates each key and value expression, checks key hashability, and returns a new Dart [Map].
  /// Throws [RuntimeError] for unhashable keys.
  @override
  Future<Object?> visitDictLiteralExpr(DictLiteralExpr expr) async {
    Map<Object?, Object?> map = {};
    if (expr.keys.length != expr.values.length) {
      // Should be caught by parser, but safety check
      throw RuntimeError(expr.brace, "Internal error: Mismatched keys/values in dictionary literal.");
    }
    for (int i = 0; i < expr.keys.length; i++) {
      Object? key = await evaluate(expr.keys[i]);
      // TODO: Check if key is hashable (basic types are in Dart)
      // In Python, lists cannot be keys. We might need a custom hash check.
      if (!isHashable(key)) {
        throw RuntimeError(
          expr.brace,
          "TypeError: unhashable type: '${key?.runtimeType ?? 'None'}'",
        );
      }
      Object? value = await evaluate(expr.values[i]);
      map[key] = value;
    }
    return map;
  }

  /// Helper to check if an object is suitable as a dictionary key (hashable).
  /// Mimics Python's rules (numbers, strings, booleans, None are hashable; lists, dicts are not).
  bool isHashable(Object? key) {
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
  Future<Object?> visitLogicalExpr(LogicalExpr expr) async {
    Object? left = await evaluate(expr.left);
    // Short-circuit evaluation for 'or'
    if (expr.operator.type == TokenType.OR) {
      if (isTruthy(left)) return left;
    } else {
      // Must be AND
      if (!isTruthy(left)) return left;
    }
    return await evaluate(expr.right);
  }

  /// Visitor method for evaluating a [VariableExpr].
  /// Looks up the variable's value in the current environment chain using [_environment.get].
  /// Throws [RuntimeError] if the variable is not defined.
  @override
  Future<Object?> visitVariableExpr(VariableExpr expr) async {
    return _environment.get(expr.name);
  }

  @override
  Future<Object?> visitAttributeGetExpr(AttributeGetExpr expr) async {
    Object? object = await evaluate(expr.object); // Evaluate the object part first
    String name = expr.name.lexeme;         // The attribute name

    PyCallableNativeImpl? impl;

    // Check for methods on built-in types
    if (object is List) {
      impl = native_methods.listMethodImpls[name];
      if (impl != null) {
        return PyBoundNativeMethod(object, impl, name); // Return the bound method callable
      }
    } else if (object is Map) {
      impl = native_methods.dictMethodImpls[name];
      if (impl != null) {
        return PyBoundNativeMethod(object, impl, name);
      }
    } else if (object is String) {
      impl = native_methods.stringMethodImpls[name];
      if (impl != null) {
        return PyBoundNativeMethod(object, impl, name);
      }
    }
    // If it wasn't a known native method, check if it's an instance attribute/method
    else if (object is PyInstance) {
      try {
        // Let the instance handle the lookup (checks fields, then class methods)
        return object.get(expr.name);
      } on RuntimeError catch(e) {
        // Improve error message consistency - ensure it's an AttributeError
        if (!e.message.startsWith("AttributeError:")) {
          throw RuntimeError(expr.name, "AttributeError: '${object.klass.name}' object has no attribute '$name'");
        }
        rethrow; // Rethrow if it was already an AttributeError
      }
    }

    // If the attribute/method wasn't found on either native types or instances
    throw RuntimeError(expr.name, "AttributeError: '${getTypeString(object)}' object has no attribute '$name'");
  }

   @override
  Future<Object?> visitAttributeSetExpr(AttributeSetExpr expr) async {
    Object? object = await evaluate(expr.object);
    if (object is PyInstance) {
      Object? value = await evaluate(expr.value);
      object.set(expr.name, value); // Let instance handle setting
      return value; // Assignment evaluates to the value
    }
    throw RuntimeError(expr.name, "Only instances have settable attributes.");
  }

  @override
  Future<Object?> visitSuperExpr(SuperExpr expr) async {
      // 1. Lookup 'super' in current environment.
      //    Since methods get their closure from the class environment, this should find the PyClass object from the super class
      Object? superclassObj = _environment.get(expr.keyword);
      if (superclassObj is! PyClass) {
          // This should not happen if 'super()' is used only in class methods
          throw RuntimeError(expr.keyword, "'super' is not bound to a class in this context.");
      }
      PyClass superclass = superclassObj;

      // 2. Get 'self' from the current environment (that is set up during method calls).
      Object? object = _environment.get(Token(TokenType.IDENTIFIER /* war SELF */, "self", null, 0,0));
      if (object is! PyInstance) {
          throw RuntimeError(expr.keyword, "'self' is not bound in this context (needed for super).");
      }

      // 3. Find the method in the super class.
      PyFunction? method = superclass.findMethod(expr.method.lexeme);
      if (method == null) {
          throw RuntimeError(expr.method, "AttributeError: 'super' object (referring to class ${superclass.name}) has no attribute '${expr.method.lexeme}'");
      }

      // 4. Bind the method of the super class to the current instance ('self').
      return method.bind(object);
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
    
    if (object is num) {
       // Handle NaN, Infinity for str()
      if (object is double) {
        if (object.isNaN) return "nan";
        if (object.isInfinite) return object.isNegative ? "-inf" : "inf";
      }
      return object.toString();
    }
    if (object is String) {
      // return "'${object.replaceAll("'", "\\'")}'"; // More like repr()
      return object; // More like str()
    }
    if (object is List) {
      // Recursively stringify elements: [item1, item2]
      return '[${object.map((e) => e is String? "'$e'" : stringify(e)).join(', ')}]';
    }
    if (object is Map) {
      // {key1: value1, key2: value2}
      return '{${object.entries.map((e) {
        var k=e.key;
        if (k is String) k="'$k'";
          return '$k: ${stringify(e.value)}';
        }).join(', ')}}';
    }
    if (object is PyCallable) {
      return object.toString(); // Use the custom toString from PyFunction/NativeFunction
    }
    // Add custom stringification for other types (classes, etc.) if needed

    // Default fallback using Dart's toString()
    return object.toString();
  }

}