import 'lexer.dart';

// --- Expressions ---

/// Base class for all expression nodes in the Abstract Syntax Tree (AST).
///
/// Expressions produce values when evaluated by the interpreter.
/// All expression nodes must implement the `accept` method for the Visitor pattern.
abstract class Expr {
  /// Accepts an [ExprVisitor] and calls the appropriate visit method based on
  /// the concrete type of this expression node.
  /// Returns the result produced by the visitor's method.
   Future<R> accept<R>(ExprVisitor<R> visitor);
}

/// Defines the interface for visiting different types of [Expr] nodes.
///
/// This pattern allows operations (like interpretation, printing, analysis)
/// to be performed on the AST without modifying the node classes themselves.
abstract class ExprVisitor<R> {
  /// Visits an [AssignExpr] node (e.g., `name = value`).
  Future<R> visitAssignExpr(AssignExpr expr);
  /// Visits an [AugAssignExpr] node (e.g., `target += value`).
  Future<R> visitAugAssignExpr(AugAssignExpr expr);
  /// Visits a [BinaryExpr] node (e.g., `left + right`).
  Future<R> visitBinaryExpr(BinaryExpr expr);
  /// Visits a [CallExpr] node (e.g., `func(arg1, kwarg=arg2)`).
  Future<R> visitCallExpr(CallExpr expr);
  /// Visits a [IndexGetExpr] node (e.g., `object[index]`).
  Future<R> visitIndexGetExpr(IndexGetExpr expr);
  /// Visits a [IndexSetExpr] node (e.g., `object[index] = value`).
  Future<R> visitIndexSetExpr(IndexSetExpr expr);
  /// Visits a [AttributeGetExpr] node (e.g., `obj.attr`).
  Future<R> visitAttributeGetExpr(AttributeGetExpr expr);
  /// Visits a [AttributeSetExpr] node (e.g., `obj.attr = value`).
  Future<R> visitAttributeSetExpr(AttributeSetExpr expr);
  /// Visits a [GroupingExpr] node (e.g., `(expression)`).
  Future<R> visitGroupingExpr(GroupingExpr expr);
  /// Visits a [LiteralExpr] node (e.g., `123`, `"hello"`, `True`, `None`).
  Future<R> visitLiteralExpr(LiteralExpr expr);
  /// Visits a [ListLiteralExpr] node (e.g., `[elem1, elem2]`).
  Future<R> visitListLiteralExpr(ListLiteralExpr expr);
  /// Visits a [DictLiteralExpr] node (e.g., `{key1: val1, key2: val2}`).
  Future<R> visitDictLiteralExpr(DictLiteralExpr expr);
  /// Visits a [LogicalExpr] node (e.g., `left and right`, `left or right`).
  Future<R> visitLogicalExpr(LogicalExpr expr);
  /// Visits a [UnaryExpr] node (e.g., `-operand`, `not operand`).
  Future<R> visitUnaryExpr(UnaryExpr expr);
  /// Visits a [VariableExpr] node (e.g., `my_variable`).
  Future<R> visitVariableExpr(VariableExpr expr);
  /// Visits a [SuperExpr] node (e.g., in `super().__init__()`).
  Future<R> visitSuperExpr(SuperExpr expr);
  /// Visits a [LambdaExpr] node (e.g., `lambda x: x**2`).
  Future<R> visitLambdaExpr(LambdaExpr expr);
}

/// Represents an assignment expression (e.g., `name = value`).
class AssignExpr extends Expr {
  /// The token representing the variable name being assigned to.
  final Token name;
  /// The expression producing the value to be assigned.
  final Expr value;
  AssignExpr(this.name, this.value);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitAssignExpr(this);
}

/// Represents an augmented assignment expression (e.g., `target += value`, `target *= value`).
class AugAssignExpr extends Expr {
  /// The target expression (L-value) being assigned to (e.g., [VariableExpr], [IndexGetExpr]).
  final Expr target;
  /// The token representing the augmented assignment operator (e.g., `+=`, `-=`).
  final Token operator;
  /// The expression producing the value used in the operation.
  final Expr value;
  AugAssignExpr(this.target, this.operator, this.value);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitAugAssignExpr(this);
}

/// Represents a binary operation (e.g., `left + right`, `left == right`).
class BinaryExpr extends Expr {
  /// The expression on the left side of the operator.
  final Expr left;
  /// The token representing the binary operator (e.g., `+`, `-`, `*`, `/`, `==`, `>`).
  final Token operator;
  /// The expression on the right side of the operator.
  final Expr right;
  BinaryExpr(this.left, this.operator, this.right);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitBinaryExpr(this);
}

/// Base class for different kinds of arguments passed in a function call.
abstract class Argument {}

/// Represents a positional argument in a function call (e.g., the `1` in `f(1)`).
class PositionalArgument extends Argument {
  /// The expression providing the argument's value.
  final Expr value;
  PositionalArgument(this.value);
}

/// Represents a keyword argument in a function call (e.g., `kw=2` in `f(kw=2)`).
class KeywordArgument extends Argument {
  /// The token representing the keyword identifier.
  final Token name;
  /// The expression providing the argument's value.
  final Expr value;
  KeywordArgument(this.name, this.value);
}

/// Represents a function or method call expression (e.g., `callee(arg1, kw=arg2)`).
class CallExpr extends Expr {
  /// The expression being called (typically a [VariableExpr] or [IndexGetExpr]).
  final Expr callee;
  /// The token for the closing parenthesis `)`. Used for location information.
  final Token paren;
  /// The list of arguments passed to the function, structured as [Argument] subtypes.
  final List<Argument> arguments;
  CallExpr(this.callee, this.paren, this.arguments);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitCallExpr(this);
}

/// Represents an indexing or subscription expression used to get a value (e.g., `object[index]`).
class IndexGetExpr extends Expr {
  /// The expression representing the object being indexed (e.g., list, dictionary, string).
  final Expr object;
  /// The token for the opening bracket `[`. Used for location information.
  final Token bracket;
  /// The expression providing the index or key.
  final Expr index;
  IndexGetExpr(this.object, this.bracket, this.index);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitIndexGetExpr(this);
}

/// Represents an item assignment expression using indexing (e.g., `object[index] = value`).
class IndexSetExpr extends Expr {
  /// The expression representing the object whose item is being set (e.g., list, dictionary).
  final Expr object;
  /// The expression providing the index or key.
  final Expr index;
  /// The expression providing the value to be assigned.
  final Expr value;
  /// The token for the opening bracket `[`. Used for location information.
  final Token bracket;
  IndexSetExpr(this.object, this.index, this.value, this.bracket);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitIndexSetExpr(this);
}

/// Represents a dot expression to get an attribute from an object (e.g., `object.attribute`).
class AttributeGetExpr extends Expr {
  final Expr object; // The object whose attribute is accessed
  final Token name;  // The identifier token for the attribute name
  AttributeGetExpr(this.object, this.name);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitAttributeGetExpr(this);
}

/// Represents an item assignment expression using dot notation (e.g., `object.attribute = value`).
class AttributeSetExpr extends Expr {
  final Expr object; // The object whose attribute is set
  final Token name;  // The identifier token for the attribute name
  final Expr value;  // The expression for the value to assign
  AttributeSetExpr(this.object, this.name, this.value);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitAttributeSetExpr(this);
}

/// Represents the `super()` expression to refer to the superclass
class SuperExpr extends Expr {
  final Token keyword; // The 'super' token
  final Token method;  // The method name identifier after 'super.'
  SuperExpr(this.keyword, this.method);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitSuperExpr(this);
}

/// Represents a lambda expression (e.g., `lambda x: x**2`)
class LambdaExpr extends Expr {
  final Token keyword; // The 'lambda' token
  final List<Parameter> params; // Parameters (same structure as functions)
  final Expr body; // The single expression body
  LambdaExpr(this.keyword, this.params, this.body);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitLambdaExpr(this);
}

/// Represents a unary operation (e.g., `-operand`, `not operand`, `+operand`, `~operand`).
class UnaryExpr extends Expr {
  /// The token representing the unary operator (e.g., `+`, `-`, `not`, `~`).
  final Token operator;
  /// The expression the operator applies to.
  final Expr operand;
  UnaryExpr(this.operator, this.operand);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitUnaryExpr(this);
}

/// Represents an expression enclosed in parentheses (e.g., `(expression)`).
/// Used to override operator precedence.
class GroupingExpr extends Expr {
  /// The expression contained within the parentheses.
  final Expr expression;
  GroupingExpr(this.expression);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitGroupingExpr(this);
}

/// Represents a literal value (e.g., number, string, boolean, None).
class LiteralExpr extends Expr {
  /// The actual literal value (e.g., `123`, `"abc"`, `true`, `false`, `null`).
  final Object? value;
  LiteralExpr(this.value);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitLiteralExpr(this);
}

/// Represents a list literal expression (e.g., `[elem1, elem2, ...]`).
class ListLiteralExpr extends Expr {
  /// The token for the opening bracket `[`. Used for location information.
  final Token bracket;
  /// The list of expressions representing the elements of the list.
  final List<Expr> elements;
  ListLiteralExpr(this.bracket, this.elements);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitListLiteralExpr(this);
}

/// Represents a dictionary literal expression (e.g., `{key1: value1, key2: value2, ...}`).
class DictLiteralExpr extends Expr {
  /// The token for the opening brace `{`. Used for location information.
  final Token brace;
  /// The list of expressions representing the keys.
  final List<Expr> keys;
  /// The list of expressions representing the values, corresponding to [keys].
  final List<Expr> values;
  DictLiteralExpr(this.brace, this.keys, this.values);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitDictLiteralExpr(this);
}

/// Represents a logical AND or OR expression, supporting short-circuit evaluation.
class LogicalExpr extends Expr {
  /// The expression on the left side of the logical operator.
  final Expr left;
  /// The token representing the logical operator (`and` or `or`).
  final Token operator;
  /// The expression on the right side of the logical operator.
  final Expr right;
  LogicalExpr(this.left, this.operator, this.right);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitLogicalExpr(this);
}

/// Represents a variable access expression.
class VariableExpr extends Expr {
  /// The token representing the identifier (variable name).
  final Token name;
  VariableExpr(this.name);
  @override
  Future<R> accept<R>(ExprVisitor<R> visitor) => visitor.visitVariableExpr(this);
}

// --- Statements ---

/// Base class for all statement nodes in the Abstract Syntax Tree (AST).
///
/// Statements represent actions or control flow constructs (e.g., assignment,
/// function definition, loops, conditionals). They typically do not produce values directly.
/// All statement nodes must implement the `accept` method for the Visitor pattern.
abstract class Stmt {
  /// Accepts a [StmtVisitor] and calls the appropriate visit method based on
  /// the concrete type of this statement node.
  /// Returns the result produced by the visitor's method (often `void`).
  Future<R> accept<R>(StmtVisitor<R> visitor);
}

/// Defines the interface for visiting different types of [Stmt] nodes.
///
/// This pattern allows operations (like interpretation, printing, analysis)
/// to be performed on the AST without modifying the node classes themselves.
abstract class StmtVisitor<R> {
  /// Visits a [BlockStmt] node (sequence of statements).
  Future<R> visitBlockStmt(BlockStmt stmt);
  /// Visits an [ExpressionStmt] node (an expression used as a statement).
  Future<R> visitExpressionStmt(ExpressionStmt stmt);
  /// Visits a [FunctionStmt] node (`def` statement).
  Future<R> visitFunctionStmt(FunctionStmt stmt);
  /// Visits a [ClassStmt] node (`class` statement).
  Future<R> visitClassStmt(ClassStmt stmt); // <<
  /// Visits an [IfStmt] node (`if`/`elif`/`else` statement).
  Future<R> visitIfStmt(IfStmt stmt);
  /// Visits a [ReturnStmt] node (`return` statement).
  Future<R> visitReturnStmt(ReturnStmt stmt);
  /// Visits a [WhileStmt] node (`while` loop).
  Future<R> visitWhileStmt(WhileStmt stmt);
  /// Visits a [ForStmt] node (`for` loop).
  Future<R> visitForStmt(ForStmt stmt);
  /// Visits a [PassStmt] node (`pass` statement).
  Future<R> visitPassStmt(PassStmt stmt);
  /// Visits a [BreakStmt] node (`break` statement).
  Future<R> visitBreakStmt(BreakStmt stmt);
  /// Visits a [ContinueStmt] node (`continue` statement).
  Future<R> visitContinueStmt(ContinueStmt stmt);
}

/// Represents a block (sequence) of statements.
/// Often used as the body of control flow structures or functions.
class BlockStmt extends Stmt {
  /// The list of statements contained within this block.
  final List<Stmt> statements;
  BlockStmt(this.statements);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitBlockStmt(this);
}

/// Represents a class
class ClassStmt extends Stmt {
  final Token name;
  final VariableExpr? superclass; // Optional superclass variable expression
  final List<FunctionStmt> methods; // Class body contains method definitions
  ClassStmt(this.name, this.superclass, this.methods);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitClassStmt(this);
}

/// Represents a statement that consists solely of an expression.
/// The expression's value is typically discarded (e.g., a function call used for side effects).
class ExpressionStmt extends Stmt {
  /// The expression being executed as a statement.
  final Expr expression;
  ExpressionStmt(this.expression);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitExpressionStmt(this);
}

/// Base class for different kinds of parameters in a function definition.
/// Each parameter has a name.
abstract class Parameter {
  /// The token representing the parameter's identifier (name).
  final Token name;
  Parameter(this.name);
}

/// Represents a standard required positional or keyword parameter.
class RequiredParameter extends Parameter {
  RequiredParameter(super.name);
}

/// Represents an optional parameter with a default value (e.g., `param=default`).
class OptionalParameter extends Parameter {
  /// The expression defining the default value for this parameter.
  final Expr defaultValue;
  OptionalParameter(super.name, this.defaultValue);
}

/// Represents the `*args` parameter, collecting excess positional arguments into a list.
class StarArgsParameter extends Parameter {
  /// [name] holds the token for the identifier following the `*` (e.g., `args`).
  StarArgsParameter(super.name);
}

/// Represents the `**kwargs` parameter, collecting excess keyword arguments into a dictionary.
class StarStarKwargsParameter extends Parameter {
  /// [name] holds the token for the identifier following the `**` (e.g., `kwargs`).
  StarStarKwargsParameter(super.name);
}

/// Represents a function definition (`def name(params): body`).
class FunctionStmt extends Stmt {
  /// The token representing the function's identifier (name).
  final Token name;
  /// The list of parameters defined for the function, structured as [Parameter] subtypes.
  final List<Parameter> params;
  /// The list of statements forming the function's body.
  final List<Stmt> body;
  FunctionStmt(this.name, this.params, this.body);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitFunctionStmt(this);
}

/// Represents a `pass` statement, which performs no operation.
class PassStmt extends Stmt {
  /// The `pass` keyword token. Used for location information.
  final Token token;
  PassStmt(this.token);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitPassStmt(this);
}

/// Represents an `if` statement, potentially including `elif` and `else` clauses.
class IfStmt extends Stmt {
  /// The condition expression for the main `if` clause.
  final Expr condition;
  /// The statement (typically a [BlockStmt]) executed if [condition] is true.
  final Stmt thenBranch;
  /// The list of `elif` branches associated with this `if`.
  final List<ElifBranch> elifBranches;
  /// The optional statement (typically a [BlockStmt]) executed if all preceding
  /// `if` and `elif` conditions are false. Can be null.
  final Stmt? elseBranch;
  IfStmt(this.condition, this.thenBranch, this.elifBranches, this.elseBranch);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitIfStmt(this);
}

/// Helper structure representing a single `elif` branch within an [IfStmt].
class ElifBranch {
  /// The condition expression for this `elif` clause.
  final Expr condition;
  /// The statement (typically a [BlockStmt]) executed if this [condition] is true
  /// and preceding `if`/`elif` conditions were false.
  final Stmt thenBranch;
  ElifBranch(this.condition, this.thenBranch);
}

/// Represents a `return` statement, optionally returning a value.
class ReturnStmt extends Stmt {
  /// The `return` keyword token. Used for location information.
  final Token keyword;
  /// The optional expression whose value is returned. Can be null for `return` without a value.
  final Expr? value;
  ReturnStmt(this.keyword, this.value);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitReturnStmt(this);
}

/// Represents a `while` loop statement (`while condition: body`).
class WhileStmt extends Stmt {
  /// The condition expression, evaluated before each iteration.
  final Expr condition;
  /// The statement (typically a [BlockStmt]) executed as the loop body.
  final Stmt body;
  WhileStmt(this.condition, this.body);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) {
    /*print("visit WhileStmt");*/
    return visitor.visitWhileStmt(this);
  }
}

/// Represents a `for` loop statement (`for variable in iterable: body`).
class ForStmt extends Stmt {
  /// The token representing the loop variable that takes on values from the iterable.
  final Token variable;
  /// The expression that evaluates to the iterable object (e.g., list, string, range result).
  final Expr iterable;
  /// The statement (typically a [BlockStmt]) executed as the loop body for each item.
  final Stmt body;
  ForStmt(this.variable, this.iterable, this.body);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitForStmt(this);
}

/// Represents a `break` statement, used to exit the nearest enclosing loop prematurely.
class BreakStmt extends Stmt {
  /// The `break` keyword token. Used for location information.
  final Token token;
  BreakStmt(this.token);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitBreakStmt(this);
}

/// Represents a `continue` statement, used to skip to the next iteration of the nearest enclosing loop.
class ContinueStmt extends Stmt {
  /// The `continue` keyword token. Used for location information.
  final Token token;
  ContinueStmt(this.token);
  @override
  Future<R> accept<R>(StmtVisitor<R> visitor) => visitor.visitContinueStmt(this);
}

/// Utility class implementing the [ExprVisitor] and [StmtVisitor] interfaces
/// to produce a Lisp-like string representation of the AST for debugging purposes.
class AstPrinter implements ExprVisitor<String>, StmtVisitor<String> {
  /// Prints an [Expr] node to its string representation.
  Future<String> printExpr(Expr expr) async {
    return await expr.accept(this);
  }

  /// Prints a [Stmt] node to its string representation.
  Future<String> printStmt(Stmt stmt) async {
    return await stmt.accept(this);
  }

  @override
  @override
  Future<String> visitAssignExpr(AssignExpr expr) async {
    return await parenthesize("assign ${expr.name.lexeme}", [expr.value]);
  }
  @override
  Future<String> visitAugAssignExpr(AugAssignExpr expr) async => await parenthesize(
    "aug_assign ${expr.operator.lexeme}",
    [expr.target, expr.value],
  );
  @override
  Future<String> visitBinaryExpr(BinaryExpr expr) async =>
    await parenthesize(expr.operator.lexeme, [expr.left, expr.right]);

  @override
  Future<String> visitCallExpr(CallExpr expr) async {
    List<String> argStrings = [];
    for (var arg in expr.arguments) {
      if (arg is PositionalArgument) {
        argStrings.add(await printExpr(arg.value));
      } else if (arg is KeywordArgument) {
        argStrings.add("${arg.name.lexeme}=${await printExpr(arg.value)}");
      }
    }
    return await parenthesize("call ${await printExpr(expr.callee)}", argStrings);
  }
  @override
  Future<String> visitIndexGetExpr(IndexGetExpr expr) async =>
    await parenthesize("get ${await printExpr(expr.object)}", [expr.index]);
  @override
  Future<String> visitIndexSetExpr(IndexSetExpr expr) async => await parenthesize(
    "set ${await printExpr(expr.object)}[${await printExpr(expr.index)}]", [expr.value]);
  @override
  Future<String> visitAttributeGetExpr(AttributeGetExpr expr) async =>
      "(get_attr ${await printExpr(expr.object)} . ${expr.name.lexeme})";
  @override
  Future<String> visitAttributeSetExpr(AttributeSetExpr expr) async => await parenthesize(
    "set_attr ${await printExpr(expr.object)} . ${expr.name.lexeme}", [expr.value]);
  @override
  Future<String> visitSuperExpr(SuperExpr expr) async => "(super . ${expr.method.lexeme})";
  @override
  Future<String> visitClassStmt(ClassStmt stmt) async {
    var base = stmt.superclass != null ? " < ${await printExpr(stmt.superclass!)}" : "";
    List<Future<String>> methodFutures = stmt.methods.map((m) => printStmt(m)).toList();
    List<String> methodStrings = await Future.wait(methodFutures);
    var methodLines = methodStrings.join('\n    ');
    var indentedMethods = methodLines.isNotEmpty ? "    $methodLines" : "";
    return "class ${stmt.name.lexeme}$base:\n$indentedMethods\n";
  }
  @override
  Future<String> visitGroupingExpr(GroupingExpr expr) async =>
    await parenthesize("group", [expr.expression]);
  @override
  Future<String> visitLiteralExpr(LiteralExpr expr) async => _stringifyLiteral(expr.value);
  @override
  Future<String> visitListLiteralExpr(ListLiteralExpr expr) async =>
    await parenthesize("list", expr.elements);
  @override
  Future<String> visitDictLiteralExpr(DictLiteralExpr expr) async {
    List<String> items = [];
    for (int i = 0; i < expr.keys.length; i++) {
      items.add("${await printExpr(expr.keys[i])}:${await printExpr(expr.values[i])}");
    }
    return "(dict ${items.join(', ')})";
  }

  @override
  Future<String> visitLogicalExpr(LogicalExpr expr) async =>
    await parenthesize(expr.operator.lexeme, [expr.left, expr.right]);
  @override
  Future<String> visitVariableExpr(VariableExpr expr) async => expr.name.lexeme;

  @override
  Future<String> visitBlockStmt(BlockStmt stmt) async {
    List<String> stmtStrings = await Future.wait(stmt.statements.map((s) => printStmt(s)).toList());
    var lines = stmtStrings.join('\n  ');
    // Indent the block content for readability
    return "{\n  $lines\n}";
  }

  @override
  Future<String> visitPassStmt(PassStmt stmt) async => "(pass)";

  @override
  Future<String> visitBreakStmt(BreakStmt stmt) async => "(break)";

  @override
  Future<String> visitContinueStmt(ContinueStmt stmt) async => "(continue)";

  @override
  Future<String> visitExpressionStmt(ExpressionStmt stmt) async =>
    await parenthesize("expr_stmt", [stmt.expression]);

  @override
  Future<String> visitFunctionStmt(FunctionStmt stmt) async {
    List<String> paramStrings = [];
    for (var param in stmt.params) {
      if (param is RequiredParameter) {
        paramStrings.add(param.name.lexeme);
      } else if (param is OptionalParameter) {
        paramStrings.add(
          "${param.name.lexeme}=${await printExpr(param.defaultValue)}",
        );
      } else if (param is StarArgsParameter) {
        paramStrings.add("*${param.name.lexeme}");
      } else if (param is StarStarKwargsParameter) {
        paramStrings.add("**${param.name.lexeme}");
      }
    }
    
    // Indent body statements for readability
    var body = (await Future.wait(stmt.body.map((s) => printStmt(s)).toList())).join('\n    ');
    // Ensure initial indentation for body if not empty
    var indentedBody = body.isNotEmpty ? "    $body" : "";
    return "def ${stmt.name.lexeme}(${paramStrings.join(', ')}):\n$indentedBody\n";
  }

  @override
  Future<String> visitLambdaExpr(LambdaExpr expr) async {
    List<String> paramStrings = [];
    // Reuse parameter printing logic if possible, or simplify:
    for (var param in expr.params) {
      if (param is RequiredParameter) {
        paramStrings.add(param.name.lexeme);
      } else if (param is OptionalParameter) {
        paramStrings.add("${param.name.lexeme}=${await printExpr(param.defaultValue)}");
      } else if (param is StarArgsParameter) {
        paramStrings.add("*${param.name.lexeme}");
      } else if (param is StarStarKwargsParameter) {
        paramStrings.add("**${param.name.lexeme}");
      }
    }
    return await parenthesize("lambda (${paramStrings.join(', ')})", [expr.body]);
  }

  @override
  Future<String> visitIfStmt(IfStmt stmt) async {
    var conditionStr = await printExpr(stmt.condition);
    var thenBranchStr = await printStmt(stmt.thenBranch); // await nötig
    var result = "(if $conditionStr\n  (then $thenBranchStr)";
    for (var elif in stmt.elifBranches) {
      var elifCondStr = await printExpr(elif.condition);
      var elifThenStr = await printStmt(elif.thenBranch); // await nötig
      result += "\n  (elif $elifCondStr\n    (then $elifThenStr))";
    }
    if (stmt.elseBranch != null) {
      var elseBranchStr = await printStmt(stmt.elseBranch!); // await nötig
      result += "\n  (else $elseBranchStr)";
    }
    result += "\n)";
    return result;
  }

  // Removed visitPrintStmt
  @override
  Future<String> visitReturnStmt(ReturnStmt stmt) async =>
    await parenthesize("return", stmt.value == null ? [] : [stmt.value!]);
  @override
  Future<String> visitWhileStmt(WhileStmt stmt) async {
    return await parenthesize("while ${await printExpr(stmt.condition)}", [stmt.body]);
  }
  @override
  Future<String> visitForStmt(ForStmt stmt) async {
     return await parenthesize("for ${stmt.variable.lexeme} in ${await printExpr(stmt.iterable)}", [stmt.body]);
  }

  @override
  Future<String> visitUnaryExpr(UnaryExpr expr) async {
    return await parenthesize(expr.operator.lexeme, [expr.operand]);
  }

  /// Helper method to create parenthesized string representations for nodes.
  Future<String> parenthesize(String name, List<dynamic> parts) async {
    // Use dynamic for mixed Expr/Stmt/String
    var builder = StringBuffer();
    builder.write("($name");
    for (var part in parts) {
      builder.write(" ");
      if (part is Expr) {
        builder.write(await part.accept(this));
      } else if (part is Stmt) {
        // For statements within expressions (not common, but possible?), indent them
        String stmtStr = await part.accept(this);
        builder.write(
          stmtStr.replaceAll('\n', '\n  '),
        ); // Indent nested statements
      } else if (part is String) {
        builder.write(
          part,
        ); // Already formatted string (e.g., from keyword arg)
      } else {
        builder.write(_stringifyLiteral(part)); // Fallback for literals etc.
      }
    }
    builder.write(")");
    return builder.toString();
  }

  /// Helper method to consistently format literal values in the output string.
  String _stringifyLiteral(Object? value) {
    if (value == null) return "None";
    if (value is String) return "'${value.replaceAll("'", "\\'")}'"; // Show quotes for strings
    if (value is bool) return value ? "True" : "False";
    // Add other types if needed
    return value.toString();
  }
}