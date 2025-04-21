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
   accept<R>(ExprVisitor<R> visitor);
}

/// Defines the interface for visiting different types of [Expr] nodes.
///
/// This pattern allows operations (like interpretation, printing, analysis)
/// to be performed on the AST without modifying the node classes themselves.
abstract class ExprVisitor<R> {
  /// Visits an [AssignExpr] node (e.g., `name = value`).
  R visitAssignExpr(AssignExpr expr);
  /// Visits an [AugAssignExpr] node (e.g., `target += value`).
  R visitAugAssignExpr(AugAssignExpr expr);
  /// Visits a [BinaryExpr] node (e.g., `left + right`).
  R visitBinaryExpr(BinaryExpr expr);
  /// Visits a [CallExpr] node (e.g., `func(arg1, kwarg=arg2)`).
  R visitCallExpr(CallExpr expr);
  /// Visits a [IndexGetExpr] node (e.g., `object[index]`).
  R visitIndexGetExpr(IndexGetExpr expr);
  /// Visits a [IndexSetExpr] node (e.g., `object[index] = value`).
  R visitIndexSetExpr(IndexSetExpr expr);
  /// Visits a [AttributeGetExpr] node (e.g., `obj.attr`).
  R visitAttributeGetExpr(AttributeGetExpr expr);
  /// Visits a [AttributeSetExpr] node (e.g., `obj.attr = value`).
  R visitAttributeSetExpr(AttributeSetExpr expr);
  /// Visits a [GroupingExpr] node (e.g., `(expression)`).
  R visitGroupingExpr(GroupingExpr expr);
  /// Visits a [LiteralExpr] node (e.g., `123`, `"hello"`, `True`, `None`).
  R visitLiteralExpr(LiteralExpr expr);
  /// Visits a [ListLiteralExpr] node (e.g., `[elem1, elem2]`).
  R visitListLiteralExpr(ListLiteralExpr expr);
  /// Visits a [DictLiteralExpr] node (e.g., `{key1: val1, key2: val2}`).
  R visitDictLiteralExpr(DictLiteralExpr expr);
  /// Visits a [LogicalExpr] node (e.g., `left and right`, `left or right`).
  R visitLogicalExpr(LogicalExpr expr);
  /// Visits a [UnaryExpr] node (e.g., `-operand`, `not operand`).
  R visitUnaryExpr(UnaryExpr expr);
  /// Visits a [VariableExpr] node (e.g., `my_variable`).
  R visitVariableExpr(VariableExpr expr);
  /// Visits a [SuperExpr] node (e.g., in `super().__init__()`).
  R visitSuperExpr(SuperExpr expr);
  /// Visits a [LambdaExpr] node (e.g., `lambda x: x**2`).
  R visitLambdaExpr(LambdaExpr expr);
  /// Visits a [TupleLiteralExpr] node (e.g., `(1,'a')`).
  R visitTupleLiteralExpr(TupleLiteralExpr expr);
  /// Visits a [SetLiteralExpr] node (e.g., `{1,'a'}`).
  R visitSetLiteralExpr(SetLiteralExpr expr);
}

/// Represents an assignment expression (e.g., `name = value`).
class AssignExpr extends Expr {
  /// The token representing the variable name being assigned to.
  final Token name;
  /// The expression producing the value to be assigned.
  final Expr value;
  AssignExpr(this.name, this.value);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitAssignExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitAugAssignExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitBinaryExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitCallExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitIndexGetExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitIndexSetExpr(this);
}

/// Represents a dot expression to get an attribute from an object (e.g., `object.attribute`).
class AttributeGetExpr extends Expr {
  final Expr object; // The object whose attribute is accessed
  final Token name;  // The identifier token for the attribute name
  AttributeGetExpr(this.object, this.name);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitAttributeGetExpr(this);
}

/// Represents an item assignment expression using dot notation (e.g., `object.attribute = value`).
class AttributeSetExpr extends Expr {
  final Expr object; // The object whose attribute is set
  final Token name;  // The identifier token for the attribute name
  final Expr value;  // The expression for the value to assign
  AttributeSetExpr(this.object, this.name, this.value);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitAttributeSetExpr(this);
}

/// Represents the `super()` expression to refer to the superclass
class SuperExpr extends Expr {
  final Token keyword; // The 'super' token
  final Token method;  // The method name identifier after 'super.'
  SuperExpr(this.keyword, this.method);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitSuperExpr(this);
}

/// Represents a lambda expression (e.g., `lambda x: x**2`)
class LambdaExpr extends Expr {
  final Token keyword; // The 'lambda' token
  final List<Parameter> params; // Parameters (same structure as functions)
  final Expr body; // The single expression body
  LambdaExpr(this.keyword, this.params, this.body);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitLambdaExpr(this);
}

/// Represents a unary operation (e.g., `-operand`, `not operand`, `+operand`, `~operand`).
class UnaryExpr extends Expr {
  /// The token representing the unary operator (e.g., `+`, `-`, `not`, `~`).
  final Token operator;
  /// The expression the operator applies to.
  final Expr operand;
  UnaryExpr(this.operator, this.operand);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitUnaryExpr(this);
}

/// Represents an expression enclosed in parentheses (e.g., `(expression)`).
/// Used to override operator precedence.
class GroupingExpr extends Expr {
  /// The expression contained within the parentheses.
  final Expr expression;
  GroupingExpr(this.expression);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitGroupingExpr(this);
}

/// Represents a literal value (e.g., number, string, boolean, None).
class LiteralExpr extends Expr {
  /// The actual literal value (e.g., `123`, `"abc"`, `true`, `false`, `null`).
  final Object? value;
  LiteralExpr(this.value);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitLiteralExpr(this);
}

/// Represents a tuple literal expression (e.g., `(1, 'a', True)`).
class TupleLiteralExpr extends Expr {
  /// The token for the opening parenthesis `(`. Used for location information.
  final Token paren;
  /// The list of expressions representing the elements of the tuple.
  final List<Expr> elements;
  TupleLiteralExpr(this.paren, this.elements);

  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitTupleLiteralExpr(this);
}

/// Represents a set literal expression (e.g., `{1, 'a', True}`).
class SetLiteralExpr extends Expr {
   /// The token for the opening brace `{`. Used for location information.
  final Token brace;
  /// The list of expressions representing the elements of the set.
  final List<Expr> elements;
  SetLiteralExpr(this.brace, this.elements);

  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitSetLiteralExpr(this);
}

/// Represents a list literal expression (e.g., `[elem1, elem2, ...]`).
class ListLiteralExpr extends Expr {
  /// The token for the opening bracket `[`. Used for location information.
  final Token bracket;
  /// The list of expressions representing the elements of the list.
  final List<Expr> elements;
  ListLiteralExpr(this.bracket, this.elements);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitListLiteralExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitDictLiteralExpr(this);
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
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitLogicalExpr(this);
}

/// Represents a variable access expression.
class VariableExpr extends Expr {
  /// The token representing the identifier (variable name).
  final Token name;
  VariableExpr(this.name);
  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitVariableExpr(this);
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
  R accept<R>(StmtVisitor<R> visitor);
}

/// Defines the interface for visiting different types of [Stmt] nodes.
///
/// This pattern allows operations (like interpretation, printing, analysis)
/// to be performed on the AST without modifying the node classes themselves.
abstract class StmtVisitor<R> {
  /// Visits a [BlockStmt] node (sequence of statements).
  R visitBlockStmt(BlockStmt stmt);
  /// Visits an [ExpressionStmt] node (an expression used as a statement).
  R visitExpressionStmt(ExpressionStmt stmt);
  /// Visits a [FunctionStmt] node (`def` statement).
  R visitFunctionStmt(FunctionStmt stmt);
  /// Visits a [ClassStmt] node (`class` statement).
  R visitClassStmt(ClassStmt stmt); // <<
  /// Visits an [IfStmt] node (`if`/`elif`/`else` statement).
  R visitIfStmt(IfStmt stmt);
  /// Visits a [ReturnStmt] node (`return` statement).
  R visitReturnStmt(ReturnStmt stmt);
  /// Visits a [WhileStmt] node (`while` loop).
  R visitWhileStmt(WhileStmt stmt);
  /// Visits a [ForStmt] node (`for` loop).
  R visitForStmt(ForStmt stmt);
  /// Visits a [PassStmt] node (`pass` statement).
  R visitPassStmt(PassStmt stmt);
  /// Visits a [BreakStmt] node (`break` statement).
  R visitBreakStmt(BreakStmt stmt);
  /// Visits a [ContinueStmt] node (`continue` statement).
  R visitContinueStmt(ContinueStmt stmt);
}

/// Represents a block (sequence) of statements.
/// Often used as the body of control flow structures or functions.
class BlockStmt extends Stmt {
  /// The list of statements contained within this block.
  final List<Stmt> statements;
  BlockStmt(this.statements);
  @override
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitBlockStmt(this);
}

/// Represents a class
class ClassStmt extends Stmt {
  final Token name;
  final VariableExpr? superclass; // Optional superclass variable expression
  final List<FunctionStmt> methods; // Class body contains method definitions
  ClassStmt(this.name, this.superclass, this.methods);
  @override
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitClassStmt(this);
}

/// Represents a statement that consists solely of an expression.
/// The expression's value is typically discarded (e.g., a function call used for side effects).
class ExpressionStmt extends Stmt {
  /// The expression being executed as a statement.
  final Expr expression;
  ExpressionStmt(this.expression);
  @override
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitExpressionStmt(this);
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
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitFunctionStmt(this);
}

/// Represents a `pass` statement, which performs no operation.
class PassStmt extends Stmt {
  /// The `pass` keyword token. Used for location information.
  final Token token;
  PassStmt(this.token);
  @override
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitPassStmt(this);
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
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitIfStmt(this);
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
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitReturnStmt(this);
}

/// Represents a `while` loop statement (`while condition: body`).
class WhileStmt extends Stmt {
  /// The condition expression, evaluated before each iteration.
  final Expr condition;
  /// The statement (typically a [BlockStmt]) executed as the loop body.
  final Stmt body;
  WhileStmt(this.condition, this.body);
  @override
  R accept<R>(StmtVisitor<R> visitor) {
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
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitForStmt(this);
}

/// Represents a `break` statement, used to exit the nearest enclosing loop prematurely.
class BreakStmt extends Stmt {
  /// The `break` keyword token. Used for location information.
  final Token token;
  BreakStmt(this.token);
  @override
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitBreakStmt(this);
}

/// Represents a `continue` statement, used to skip to the next iteration of the nearest enclosing loop.
class ContinueStmt extends Stmt {
  /// The `continue` keyword token. Used for location information.
  final Token token;
  ContinueStmt(this.token);
  @override
  R accept<R>(StmtVisitor<R> visitor) => visitor.visitContinueStmt(this);
}

/// Utility class implementing the [ExprVisitor] and [StmtVisitor] interfaces
/// to produce a Lisp-like string representation of the AST for debugging purposes.
class AstPrinter implements ExprVisitor<String>, StmtVisitor<String> {
  /// Prints an [Expr] node to its string representation.
  String printExpr(Expr expr) {
    return expr.accept(this);
  }

  /// Prints a [Stmt] node to its string representation.
  String printStmt(Stmt stmt) {
    return stmt.accept(this);
  }

  @override
  String visitAssignExpr(AssignExpr expr) =>
      parenthesize("assign ${expr.name.lexeme}", [expr.value]);

  @override
  String visitAugAssignExpr(AugAssignExpr expr) => parenthesize(
    "aug_assign ${expr.operator.lexeme}",
    [expr.target, expr.value],
  );
  @override
  String visitBinaryExpr(BinaryExpr expr) =>
      parenthesize(expr.operator.lexeme, [expr.left, expr.right]);

  @override
  String visitCallExpr(CallExpr expr) {
    List<String> argStrings = [];
    for (var arg in expr.arguments) {
      if (arg is PositionalArgument) {
        argStrings.add(printExpr(arg.value));
      } else if (arg is KeywordArgument) {
        argStrings.add("${arg.name.lexeme}=${printExpr(arg.value)}");
      }
    }
    return parenthesize("call ${printExpr(expr.callee)}", argStrings);
  }
  @override
  String visitIndexGetExpr(IndexGetExpr expr) =>
      parenthesize("get ${printExpr(expr.object)}", [expr.index]);
  @override
  String visitIndexSetExpr(IndexSetExpr expr) => parenthesize(
    "set ${printExpr(expr.object)}[${printExpr(expr.index)}]", [expr.value]);
  @override
  String visitAttributeGetExpr(AttributeGetExpr expr) =>
      "(get_attr ${printExpr(expr.object)} . ${expr.name.lexeme})";
  @override
  String visitAttributeSetExpr(AttributeSetExpr expr) => parenthesize(
    "set_attr ${printExpr(expr.object)} . ${expr.name.lexeme}", [expr.value]);
  @override
  String visitSuperExpr(SuperExpr expr) => "(super . ${expr.method.lexeme})";
  @override
  String visitClassStmt(ClassStmt stmt) {
    var base = stmt.superclass != null ? " < ${printExpr(stmt.superclass!)}" : "";
    var methodLines = stmt.methods.map((m) => printStmt(m)).join('\n    ');
    var indentedMethods = methodLines.isNotEmpty ? "    $methodLines" : "";
    return "class ${stmt.name.lexeme}$base:\n$indentedMethods\n";
  }
  @override
  String visitGroupingExpr(GroupingExpr expr) =>
      parenthesize("group", [expr.expression]);
  @override
  String visitLiteralExpr(LiteralExpr expr) => _stringifyLiteral(expr.value);
  @override
  String visitListLiteralExpr(ListLiteralExpr expr) =>
      parenthesize("list", expr.elements);
  @override
  String visitDictLiteralExpr(DictLiteralExpr expr) {
    List<String> items = [];
    for (int i = 0; i < expr.keys.length; i++) {
      items.add("${printExpr(expr.keys[i])}:${printExpr(expr.values[i])}");
    }
    return "(dict ${items.join(', ')})";
  }

  @override
  String visitLogicalExpr(LogicalExpr expr) =>
      parenthesize(expr.operator.lexeme, [expr.left, expr.right]);
  @override
  String visitVariableExpr(VariableExpr expr) => expr.name.lexeme;

  @override
  String visitBlockStmt(BlockStmt stmt) {
    var lines = stmt.statements.map((s) => printStmt(s)).join('\n  ');
    // Indent the block content for readability
    return "{\n  $lines\n}";
  }

  @override
  String visitPassStmt(PassStmt stmt) => "(pass)";

  @override
  String visitBreakStmt(BreakStmt stmt) => "(break)";

  @override
  String visitContinueStmt(ContinueStmt stmt) => "(continue)";

  @override
  String visitExpressionStmt(ExpressionStmt stmt) =>
      parenthesize("expr_stmt", [stmt.expression]);

  @override
  String visitFunctionStmt(FunctionStmt stmt) {
    List<String> paramStrings = [];
    for (var param in stmt.params) {
      if (param is RequiredParameter) {
        paramStrings.add(param.name.lexeme);
      } else if (param is OptionalParameter) {
        paramStrings.add(
          "${param.name.lexeme}=${printExpr(param.defaultValue)}",
        );
      } else if (param is StarArgsParameter) {
        paramStrings.add("*${param.name.lexeme}");
      } else if (param is StarStarKwargsParameter) {
        paramStrings.add("**${param.name.lexeme}");
      }
    }
    // Indent body statements for readability
    var body = stmt.body.map((s) => printStmt(s)).join('\n    ');
    // Ensure initial indentation for body if not empty
    var indentedBody = body.isNotEmpty ? "    $body" : "";
    return "def ${stmt.name.lexeme}(${paramStrings.join(', ')}):\n$indentedBody\n";
  }

  @override
  String visitLambdaExpr(LambdaExpr expr) {
    List<String> paramStrings = [];
    // Reuse parameter printing logic if possible, or simplify:
    for (var param in expr.params) {
      if (param is RequiredParameter) {
        paramStrings.add(param.name.lexeme);
      } else if (param is OptionalParameter) {
        paramStrings.add("${param.name.lexeme}=${printExpr(param.defaultValue)}");
      } else if (param is StarArgsParameter) {
        paramStrings.add("*${param.name.lexeme}");
      } else if (param is StarStarKwargsParameter) {
        paramStrings.add("**${param.name.lexeme}");
      }
    }
    return parenthesize("lambda (${paramStrings.join(', ')})", [expr.body]);
  }

  @override
  String visitIfStmt(IfStmt stmt) {
    var result =
        "(if ${printExpr(stmt.condition)}\n  (then ${printStmt(stmt.thenBranch)})";
    for (var elif in stmt.elifBranches) {
      result +=
          "\n  (elif ${printExpr(elif.condition)}\n    (then ${printStmt(elif.thenBranch)}))";
    }
    if (stmt.elseBranch != null) {
      result += "\n  (else ${printStmt(stmt.elseBranch!)})";
    }
    result += "\n)"; // Close the main 'if' parenthesis
    return result;
  }

  // Removed visitPrintStmt
  @override
  String visitReturnStmt(ReturnStmt stmt) =>
      parenthesize("return", stmt.value == null ? [] : [stmt.value!]);
  @override
  String visitWhileStmt(WhileStmt stmt) =>
      parenthesize("while ${printExpr(stmt.condition)}", [stmt.body]);
  @override
  String visitForStmt(ForStmt stmt) => parenthesize(
    "for ${stmt.variable.lexeme} in ${printExpr(stmt.iterable)}",
    [stmt.body],
  );

  @override
  String visitUnaryExpr(UnaryExpr expr) {
    return parenthesize(expr.operator.lexeme, [expr.operand]);
  }

  @override
  String visitTupleLiteralExpr(TupleLiteralExpr expr) {
    return parenthesize("tuple", expr.elements);
  }

  @override
  String visitSetLiteralExpr(SetLiteralExpr expr) {
    return parenthesize("set", expr.elements);
  }

  /// Helper method to create parenthesized string representations for nodes.
  String parenthesize(String name, List<dynamic> parts) {
    // Use dynamic for mixed Expr/Stmt/String
    var builder = StringBuffer();
    builder.write("($name");
    for (var part in parts)   {
      builder.write(" ");
      if (part is Expr) {
        builder.write(part.accept(this));
      } else if (part is Stmt) {
        // For statements within expressions (not common, but possible?), indent them
        String stmtStr = part.accept(this);
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