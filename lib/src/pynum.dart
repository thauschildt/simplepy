import 'dart:math' as math;

/// Python-like number: can be either integer (BigInt) or float (double).
///
/// Provides Python-style numeric behavior, including arithmetic, comparison,
/// bitwise operations (for integers), modulo, and power operations.
/// This class aims to emulate Python's `int` and `float` behavior in Dart.
final class PyNum implements Comparable<PyNum> {
  final BigInt? _intValue;
  final double? _doubleValue;

  // --- Properties ---
  /// check if number is integer
  bool get isInt => _intValue != null;

  /// check if number is double (python float)
  bool get isDouble => _doubleValue != null;

  /// Returns true if the number equals zero.
  /// Works for both integers and floats.
  bool get isZero =>
      (isInt && _intValue == BigInt.zero) || (isDouble && _doubleValue == 0.0);

  /// Returns the `BigInt` value if this is an integer, otherwise null.
  BigInt? get intValue => _intValue;

  /// Returns the `double` value if this is a float, otherwise null.
  double? get doubleValue => _doubleValue;

  /// Returns the numeric value as `double`, even if this number is an integer.
  double toDouble() => isDouble ? doubleValue! : intValue!.toDouble();

  // --- Internal constructors ---
  PyNum._int(this._intValue) : _doubleValue = null;
  PyNum._double(this._doubleValue) : _intValue = null;

  // --- Factories ---
  /// Creates a `PyNum` from a Dart `int`.
  factory PyNum.int(int v) => PyNum._int(BigInt.from(v));

  /// Creates a `PyNum` from a Dart `BigInt`.
  factory PyNum.bigInt(BigInt v) => PyNum._int(v);

  /// Creates a `PyNum` from a Dart `double`.
  factory PyNum.double(double v) => PyNum._double(v);

  /// Creates a `PyNum` from a Dart `num` (either `int` or `double`).
  /// Throws `ArgumentError` for unsupported types.
  factory PyNum(num v) {
    if (v is int) return PyNum.int(v);
    if (v is double) return PyNum.double(v);
    throw ArgumentError('Unsupported type: ${v.runtimeType}');
  }

  // --- Arithmetic operators ---

  /// Adds two [PyNum]s, returning a `PyNum`.
  /// Preserves integer type if both operands are integers.
  PyNum operator +(PyNum other) {
    if (isInt && other.isInt) {
      return PyNum.bigInt(_intValue! + other._intValue!);
    }
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return PyNum.double(a + b);
  }

  /// Subtracts two [PyNum]s, returning a `PyNum`.
  PyNum operator -(PyNum other) {
    if (isInt && other.isInt) {
      return PyNum.bigInt(_intValue! - other._intValue!);
    }
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return PyNum.double(a - b);
  }

  /// Multiplies two [PyNum]s, returning a `PyNum`.
  PyNum operator *(PyNum other) {
    if (isInt && other.isInt) {
      return PyNum.bigInt(_intValue! * other._intValue!);
    }
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return PyNum.double(a * b);
  }

  /// Divides two [PyNum]s, returning a float (`double`) result.
  /// Throws `UnsupportedError` on division by zero.
  PyNum operator /(PyNum other) {
    if (other.isZero) throw UnsupportedError('Division by zero');
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return PyNum.double(a / b);
  }

  /// Performs integer division, similar to Python `//`.
  /// Returns `BigInt` if both operands are integers, otherwise returns float.
  PyNum operator ~/(PyNum other) {
    if (other.isZero) throw UnsupportedError('Division by zero');
    if (isInt && other.isInt) {
      return PyNum.bigInt(_intValue! ~/ other._intValue!);
    }
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return PyNum.double((a / b).floorToDouble());
  }

  /// Unary negation.
  PyNum operator -() =>
      isInt ? PyNum.bigInt(-_intValue!) : PyNum.double(-_doubleValue!);

  // --- Bitwise operators (ints only) ---

  /// Bitwise AND. Only valid for integers.
  PyNum operator &(PyNum other) {
    _checkInt(other);
    return PyNum.bigInt(_intValue! & other._intValue!);
  }

  /// Bitwise OR. Only valid for integers.
  PyNum operator |(PyNum other) {
    _checkInt(other);
    return PyNum.bigInt(_intValue! | other._intValue!);
  }

  /// Bitwise XOR. Only valid for integers.
  PyNum operator ^(PyNum other) {
    _checkInt(other);
    return PyNum.bigInt(_intValue! ^ other._intValue!);
  }

  /// Bitwise NOT. Only valid for integers.
  PyNum operator ~() {
    if (!isInt) throw UnsupportedError('Bitwise NOT only works on integers');
    return PyNum.bigInt(~_intValue!);
  }

  /// Bitwise left shift. Only valid for integers.
  PyNum operator <<(PyNum other) {
    _checkInt(other);
    return PyNum.bigInt(_intValue! << other._intValue!.toInt());
  }

  /// Bitwise right shift. Only valid for integers.
  PyNum operator >>(PyNum other) {
    _checkInt(other);
    return PyNum.bigInt(_intValue! >> other._intValue!.toInt());
  }

  // --- Comparison operators ---
  /// Returns true if this [PyNum] is less than [other].
  /// Works for integers and floats. Automatically converts integers to double
  /// if one of the operands is a float, emulating Python comparison behavior.
  bool operator <(PyNum other) {
    if (isInt && other.isInt) return _intValue! < other._intValue!;
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return a < b;
  }

  /// Returns true if this [PyNum] is less than or equal to [other].
  /// Works for integers and floats. Automatically converts integers to double
  /// if one of the operands is a float, emulating Python comparison behavior.
  bool operator <=(PyNum other) {
    if (isInt && other.isInt) return _intValue! <= other._intValue!;
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return a <= b;
  }

  /// Returns true if this [PyNum] is greater than [other].
  /// Works for integers and floats. Automatically converts integers to double
  /// if one of the operands is a float, emulating Python comparison behavior.
  bool operator >(PyNum other) {
    if (isInt && other.isInt) return _intValue! > other._intValue!;
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return a > b;
  }

  /// Returns true if this [PyNum] is greater than or equal to [other].
  /// Works for integers and floats. Automatically converts integers to double
  /// if one of the operands
  bool operator >=(PyNum other) {
    if (isInt && other.isInt) return _intValue! >= other._intValue!;
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return a >= b;
  }

  @override
  /// Returns true if this [PyNum] is equal to [other].
  bool operator ==(Object other) => other is PyNum && valueEquals(other);

  /// Compares numeric values for equality.
  /// Handles Python-style integer/float comparisons.
  bool valueEquals(PyNum other) {
    if (isInt && other.isInt) return _intValue == other._intValue;
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return a == b;
  }

  @override
  int get hashCode {
    if (isInt) return _intValue.hashCode;
    return _doubleValue.hashCode;
  }

  /// Returns absolute value.
  PyNum abs() =>
      isInt
          ? PyNum.bigInt(_intValue!.abs())
          : PyNum.double(_doubleValue!.abs());

  /// Raises this number to the power of [exponent].
  /// Preserves integer type if both base and exponent are integers.
  PyNum pow(PyNum exponent) {
    if (isInt && exponent.isInt) {
      return PyNum.bigInt(_intValue!.pow(exponent._intValue!.toInt()));
    }
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b =
        exponent.isInt
            ? exponent._intValue!.toDouble()
            : exponent._doubleValue!;
    return PyNum.double(math.pow(a, b).toDouble());
  }

  /// Computes the modulo of this number by [other], emulating Python's `%` behavior.
  /// - Returns an integer `PyNum` if both operands are integers; otherwise returns a double `PyNum`.
  /// - For integers, the result always has the same sign as the divisor, like in Python:
  /// - Throws [UnsupportedError] if [other] is zero (division by zero).
  PyNum mod(PyNum other) {
    if (other.isZero) throw UnsupportedError('Modulo by zero');
    if (isInt && other.isInt) {
      var mod = _intValue! % other._intValue!;
      if (mod.sign < 0) mod += other._intValue.abs(); // Python modulo behavior
      return PyNum.bigInt(mod);
    }
    final a = isInt ? _intValue!.toDouble() : _doubleValue!;
    final b = other.isInt ? other._intValue!.toDouble() : other._doubleValue!;
    return PyNum.double(a % b);
  }

  @override
  int compareTo(PyNum other) => this < other ? -1 : (this > other ? 1 : 0);

  @override
  String toString() => isInt ? _intValue.toString() : _doubleValue.toString();

  // --- Internal helpers ---
  void _checkInt(PyNum other) {
    if (!isInt || !other.isInt) {
      throw UnsupportedError('Bitwise operators only supported for integers');
    }
  }
}
