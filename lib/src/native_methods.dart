import 'interpreter.dart';

// --- Top-Level Helper Functions (mit Interpreter-Parameter) ---

/// Generic argument count and keyword checker for built-ins.
void checkNumArgs(
  String funcName,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs, {
  int required = 0,
  int maxOptional = 0,
  bool allowKeywords = false,
}) {
  if (!allowKeywords && keywordArgs.isNotEmpty) {
    // Use the static helper from Interpreter
    throw RuntimeError(
      Interpreter.builtInToken(funcName),
      "TypeError: $funcName() takes no keyword arguments",
    );
  }
  int totalAllowed = required + maxOptional;
  int actual = positionalArgs.length;

  if (maxOptional == -1) {
    // Indicates variable args like min/max
    if (actual < required) {
      throw RuntimeError(
        Interpreter.builtInToken(funcName),
        "TypeError: $funcName() expected at least $required arguments, got $actual",
      );
    }
  } else {
    // Fixed number of optional args
    if (actual < required) {
      String takes = "at least $required";
      if (maxOptional == 0) takes = "exactly $required";
      throw RuntimeError(
        Interpreter.builtInToken(funcName),
        "TypeError: $funcName() takes $takes positional arguments ($actual given)",
      );
    }
    if (actual > totalAllowed) {
      String takes = "exactly $required";
      if (maxOptional > 0 && required > 0) {
        takes = "from $required to $totalAllowed";
      } else if (maxOptional > 0) {
        takes = "at most $totalAllowed";
      }
      throw RuntimeError(
        Interpreter.builtInToken(funcName),
        "TypeError: $funcName() takes $takes positional arguments ($actual given)",
      );
    }
  }
}

/// Specific checker for functions that take NO keywords.
void checkNoKeywords(String funcName, Map<String, Object?> keywordArgs) {
  if (keywordArgs.isNotEmpty) {
    throw RuntimeError(
      Interpreter.builtInToken(funcName),
      "TypeError: $funcName() takes no keyword arguments",
    );
  }
}

/// Helper to ensure an argument is an integer for built-ins.
int expectInt(Object? arg, String contextDesc) {
  if (arg is int) return arg;
  if (arg is double && arg == arg.truncateToDouble()) return arg.toInt();
  // Use Interpreter.getTypeString if needed for better error message (requires passing interpreter)
  // Or keep the simpler message:
  throw "'$contextDesc' argument must be an integer (got ${arg?.runtimeType ?? 'None'}).";
}

// --- Top-Level Method Implementation Maps ---

final Map<String, PyCallableNativeImpl> listMethodImpls = {
  'append': listAppend,
  'insert': listInsert,
  'remove': listRemove,
  'clear': listClear,
  'pop': listPop,
  'copy': listCopy,
  'count': listCount,
  'index': listIndex,
  'reverse': listReverse,
  'sort': listSort,
};

final Map<String, PyCallableNativeImpl> dictMethodImpls = {
  'keys': dictKeys,
  'values': dictValues,
  'items': dictItems,
  'get': dictGet,
  'pop': dictPop,
  'clear': dictClear,
  'copy': dictCopy,
  'update': dictUpdate,
};

final Map<String, PyCallableNativeImpl> stringMethodImpls = {
  'find': strFind,
  'count': strCount,
  'replace': strReplace,
  'split': strSplit,
  'join': strJoin,
  'upper': strUpper,
  'lower': strLower,
  'startswith': strStartsWith,
  'endswith': strEndsWith,
  'strip': strStrip,
  'lstrip': strLstrip,
  'rstrip': strRstrip,
};

final Map<String, PyCallableNativeImpl> tupleMethodImpls = {
  'count': _tupleCount,
  'index': _tupleIndex,
};

final Map<String, PyCallableNativeImpl> setMethodImpls = {
  'add': _setAdd,
  'remove': _setRemove, // Removes element, raises KeyError if not found
  'discard': _setDiscard, // Removes element, does nothing if not found
  'pop':
      _setPop, // Removes and returns arbitrary element, raises KeyError if empty
  'clear': _setClear,
  'copy': _setCopy,
  'union': _setUnion, // or | operator (implement?)
  'intersection': _setIntersection, // or & operator (implement?)
  'difference': _setDifference, // or - operator (implement?)
  // 'symmetric_difference': _setSymmetricDifference, // or ^ operator (implement?)
  'isdisjoint': _setIsdisjoint,
  'issubset': _setIsSubset, // or <= operator (implement?)
  'issuperset': _setIsSuperset, // or >= operator (implement?)
  'update': _setUpdate, // or |= operator (implement?)
  // 'intersection_update': _setIntersectionUpdate, // or &= operator (implement?)
  // 'difference_update': _setDifferenceUpdate,     // or -= operator (implement?)
  // 'symmetric_difference_update': _setSymmetricDifferenceUpdate, // or ^= operator (implement?)
};

// --- List Methods ---

/// Implementation for `list.clear()`
Object? listClear(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('clear', positionalArgs, keywordArgs, required: 0); // No args
  checkNoKeywords('clear', keywordArgs);
  (receiver as PyList).list.clear();
  return null; // clear returns None
}

// --- Native Method Implementations ---

/// Implementation for `list.append(item)`
Object? listAppend(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('append', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('append', keywordArgs);
  (receiver as PyList).list.add(positionalArgs[0]);
  return null; // append returns None
}

/// Implementation for `list.insert(index, item)`
Object? listInsert(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('insert', positionalArgs, keywordArgs, required: 2);
  checkNoKeywords('insert', keywordArgs);
  int index;
  try {
    index = expectInt(positionalArgs[0], 'insert() index');
  } catch (e) {
    throw RuntimeError(Interpreter.builtInToken('insert'), "TypeError: $e");
  }
  final item = positionalArgs[1];
  List list = (receiver as PyList).list;

  // Adjust index like Python insert (clamps to bounds)
  if (index < 0) index += list.length;
  if (index < 0) index = 0;
  if (index > list.length) index = list.length;

  list.insert(index, item);
  return null; // insert returns None
}

/// Implementation for `list.remove(value)`
Object? listRemove(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('remove', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('remove', keywordArgs);
  final valueToRemove = positionalArgs[0];
  List list = (receiver as PyList).list;
  int indexToRemove = -1;

  // Find the first occurrence using the interpreter's isEqual
  for (int i = 0; i < list.length; i++) {
    if (interpreter.isEqual(list[i], valueToRemove)) {
      indexToRemove = i;
      break;
    }
  }
  if (indexToRemove == -1) {
    throw RuntimeError(
      Interpreter.builtInToken('remove'),
      "ValueError: list.remove(x): ${interpreter.repr(valueToRemove)} not in list",
    );
  }

  list.removeAt(indexToRemove);
  return null; // remove returns None
}

/// Implementation for `list.pop([index])`
Object? listPop(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'pop',
    positionalArgs,
    keywordArgs,
    required: 0,
    maxOptional: 1,
  ); // 0 or 1 arg
  checkNoKeywords('pop', keywordArgs);
  List list = (receiver as PyList).list;
  if (list.isEmpty) {
    throw RuntimeError(
      Interpreter.builtInToken('pop'),
      "IndexError: pop from empty list",
    );
  }
  int index = -1; // Default: last element
  if (positionalArgs.isNotEmpty) {
    try {
      index = expectInt(positionalArgs[0], 'pop() index');
    } catch (e) {
      throw RuntimeError(Interpreter.builtInToken('pop'), "TypeError: $e");
    }
  }
  // Handle negative indices relative to the *current* length
  if (index < 0) index += list.length;
  // Check bounds *after* potentially converting negative index
  if (index < 0 || index >= list.length) {
    throw RuntimeError(
      Interpreter.builtInToken('pop'),
      "IndexError: pop index out of range",
    );
  }
  return list.removeAt(index); // removeAt returns the removed item
}

/// Implementation for `list.copy()`
Object? listCopy(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('copy', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('copy', keywordArgs);
  return PyList(List.from((receiver as PyList).list)); // Return shallow copy
}

/// Implementation for `list.count(value)`
Object? listCount(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('count', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('count', keywordArgs);
  final valueToCount = positionalArgs[0];
  List list = (receiver as PyList).list;
  int count = 0;
  for (final item in list) {
    if (interpreter.isEqual(item, valueToCount)) {
      count++;
    }
  }
  return count;
}

/// Implementation for `list.index(value[, start[, stop]])`
Object? listIndex(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'index',
    positionalArgs,
    keywordArgs,
    required: 1,
    maxOptional: 2,
  );
  checkNoKeywords('index', keywordArgs);
  List list = (receiver as PyList).list;
  final valueToFind = positionalArgs[0];
  int start = 0;
  int stop = list.length; // Default stop is length (exclusive)
  try {
    if (positionalArgs.length > 1) {
      start = expectInt(positionalArgs[1], 'index() start');
    }
    if (positionalArgs.length > 2) {
      stop = expectInt(positionalArgs[2], 'index() stop');
    }
  } catch (e) {
    throw RuntimeError(Interpreter.builtInToken('index'), "TypeError: $e");
  }
  // Handle Python slice indexing for start/stop
  if (start < 0) start += list.length;
  if (start < 0) start = 0; // Clamp to beginning
  if (start > list.length) start = list.length; // Clamp to end
  if (stop < 0) stop += list.length;
  if (stop < 0) stop = 0;
  if (stop > list.length) stop = list.length;
  // Search within the calculated range [start, stop)
  for (int i = start; i < stop; i++) {
    if (interpreter.isEqual(list[i], valueToFind)) {
      return i; // Return the first index found
    }
  }
  // Value not found in the specified range
  throw RuntimeError(
    Interpreter.builtInToken('index'),
    "ValueError: ${interpreter.repr(valueToFind)} is not in list",
  );
}

/// Implementation for `list.reverse()` (in-place)
Object? listReverse(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('reverse', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('reverse', keywordArgs);
  List list = (receiver as PyList).list;
  // Simple in-place reverse
  int i = 0;
  int j = list.length - 1;
  while (i < j) {
    var temp = list[i];
    list[i] = list[j];
    list[j] = temp;
    i++;
    j--;
  }
  return null; // reverse returns None
}

/// Sorts the list in place.
/// Optional arguments:
/// - `key`: A function of one argument that extracts a comparison key.
/// - `reverse`: If true, sorts in descending order.
Object? listSort(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  if (receiver is! PyList) {
    throw RuntimeError(
      Interpreter.builtInToken('sort'),
      "TypeError: 'sort' requires a list, not ${Interpreter.getTypeString(receiver)}",
    );
  }
  List<dynamic> list = receiver.list;

  // Parse optional arguments (key, reverse)
  Object? keyFunc;
  bool reverse = false;

  // Positional args (only key possible, reverse only by keyword)
  if (positionalArgs.isNotEmpty) {
    throw RuntimeError(
      Interpreter.builtInToken('sort'),
      "TypeError: sort() takes at most 1 positional argument but ${positionalArgs.length} were given",
    );
  }

  // Keyword args (key, reverse)
  if (keywordArgs.containsKey('key')) {
    keyFunc = keywordArgs['key'];
  }
  if (keywordArgs.containsKey('reverse')) {
    reverse = keywordArgs['reverse'] as bool;
  }

  // Validate arguments
  if (keyFunc != null && keyFunc is! PyFunction) {
    throw RuntimeError(
      Interpreter.builtInToken('sort'),
      "TypeError: 'key' must be a function or None",
    );
  }

  // sort
  if (keyFunc == null) {
    // dfault sorting without key function
    list.sort((a, b) => reverse ? b.compareTo(a) : a.compareTo(b));
  } else {
    // sort using key function
    list.sort((a, b) {
      dynamic keyA = (keyFunc as PyFunction).call(interpreter, [a], {});
      dynamic keyB = keyFunc.call(interpreter, [b], {});
      return reverse ? keyB.compareTo(keyA) : keyA.compareTo(keyB);
    });
  }
  return null; // sort() returns None in python
}

// --- Dictionary Methods ---

/// Implementation for `dict.keys()`
Object? dictKeys(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('keys', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('keys', keywordArgs);
  // NOTE: Python returns a view. We return a list copy for simplicity.
  return PyList((receiver as Map).keys.toList());
}

/// Implementation for `dict.values()`
Object? dictValues(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('values', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('values', keywordArgs);
  // NOTE: Python returns a view. We return a list copy.
  return PyList((receiver as Map).values.toList());
}

/// Implementation for `dict.items()`
Object? dictItems(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('items', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('items', keywordArgs);
  Map map = receiver as Map;
  // NOTE: Python returns a view of (key, value) tuples. We return a list of [key, value] lists.
  List<PyList> itemsList = [];
  map.forEach((key, value) {
    itemsList.add(PyList([key, value]));
  });
  return PyList(itemsList);
}

/// Implementation for `dict.get(key[, default])`
Object? dictGet(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('get', positionalArgs, keywordArgs, required: 1, maxOptional: 1);
  checkNoKeywords('get', keywordArgs);
  Map map = receiver as Map;
  final key = positionalArgs[0];
  Object? defaultValue;
  if (positionalArgs.length > 1) {
    defaultValue = positionalArgs[1];
  }
  if (!Interpreter.isHashable(key)) {
    // Python's dict.get doesn't check hashability, it just won't find unhashable keys.
    // Let's mimic that. containKey handles it.
    return defaultValue;
  }
  return map.containsKey(key) ? map[key] : defaultValue;
}

/// Implementation for `dict.pop(key[, default])`
Object? dictPop(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('pop', positionalArgs, keywordArgs, required: 1, maxOptional: 1);
  checkNoKeywords('pop', keywordArgs);
  Map map = receiver as Map;
  final key = positionalArgs[0];
  bool hasDefault = positionalArgs.length > 1;
  Object? defaultValue = hasDefault ? positionalArgs[1] : null;
  if (!Interpreter.isHashable(key)) {
    // Python raises TypeError here if key is unhashable
    throw RuntimeError(
      Interpreter.builtInToken('pop'),
      "TypeError: unhashable type: '${Interpreter.getTypeString(key)}'",
    );
  }
  if (map.containsKey(key)) {
    return map.remove(key); // remove returns the value associated with the key
  } else {
    if (hasDefault) {
      return defaultValue;
    } else {
      throw RuntimeError(
        Interpreter.builtInToken('pop'),
        "KeyError: ${interpreter.repr(key)}",
      );
    }
  }
}

/// Implementation for `dict.clear()`
Object? dictClear(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('clear', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('clear', keywordArgs);
  (receiver as Map).clear();
  return null; // clear returns None
}

/// Implementation for `dict.copy()`
Object? dictCopy(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('copy', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('copy', keywordArgs);
  return Map.from(receiver as Map); // Return shallow copy
}

/// Implementation for `dict.update([other])` (simplified)
Object? dictUpdate(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'update',
    positionalArgs,
    keywordArgs,
    allowKeywords: true,
    required: 0,
    maxOptional: 1,
  ); // 0 or 1 positional arg

  Map targetMap = receiver as Map;

  if (positionalArgs.isNotEmpty) {
    final other = positionalArgs[0];
    if (other is Map) {
      // Update from another map
      other.forEach((key, value) {
        if (!Interpreter.isHashable(key)) {
          throw RuntimeError(
            Interpreter.builtInToken('update'),
            "TypeError: unhashable type: '${Interpreter.getTypeString(key)}'",
          );
        }
        targetMap[key] = value;
      });
    } else if (other is PyList) {
      // Update from an iterable of key-value pairs (represented as lists)
      for (var item in other.list) {
        List? pair;
        if (item is String) pair = item as List;
        if (item is PyList) pair = item.list;
        if ((pair is List || pair is String) && pair!.length == 2) {
          final key = pair[0];
          final value = pair[1];
          if (!Interpreter.isHashable(key)) {
            throw RuntimeError(
              Interpreter.builtInToken('update'),
              "TypeError: unhashable type: '${Interpreter.getTypeString(key)}'",
            );
          }
          targetMap[key] = value;
        } else if (pair is List || pair is String) {
          throw RuntimeError(
            Interpreter.builtInToken('dict'),
            "ValueError: dictionary update sequence element #${other.list.indexOf(item)} has length ${pair!.length}; 2 is required",
          );
        } else {
          throw RuntimeError(
            Interpreter.builtInToken('dict'),
            "ValueError: cannot convert dictionary update sequence element #${other.list.indexOf(item)} to a sequence",
          );
        }
      }
    } else {
      // Type not supported for update
      throw RuntimeError(
        Interpreter.builtInToken('update'),
        "TypeError: '${Interpreter.getTypeString(other)}' object is not iterable",
      );
    }
  }
  keywordArgs.forEach((key, value) {
    // Keys from keyword args are always strings and thus hashable in our context
    targetMap[key] = value;
  });
  return null; // update returns None
}

// --- String Methods ---

/// Implementation for `str.find(sub[, start[, end]])`
Object? strFind(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'find',
    positionalArgs,
    keywordArgs,
    required: 1,
    maxOptional: 2,
  );
  checkNoKeywords('find', keywordArgs);
  String str = receiver as String;
  Object? subObj = positionalArgs[0];

  if (subObj is! String) {
    throw RuntimeError(
      Interpreter.builtInToken('find'),
      "TypeError: must be str, not ${Interpreter.getTypeString(subObj)}",
    );
  }
  String sub = subObj;

  int start = 0;
  int end = str.length;

  try {
    if (positionalArgs.length > 1) {
      start = expectInt(positionalArgs[1], 'find() start');
    }
    if (positionalArgs.length > 2) {
      end = expectInt(positionalArgs[2], 'find() end');
    }
  } catch (e) {
    throw RuntimeError(Interpreter.builtInToken('find'), "TypeError: $e");
  }

  // Handle Python slice indexing for start/end
  if (start < 0) start += str.length;
  if (start < 0) start = 0;
  if (start > str.length) start = str.length;

  if (end < 0) end += str.length;
  if (end < 0) end = 0;
  if (end > str.length) end = str.length;

  // Ensure start <= end for Dart's indexOf
  if (start > end) return -1; // Substring is empty or invalid range

  // Dart's indexOf takes start index. We need to respect end boundary.
  int result = str.indexOf(sub, start);

  if (result == -1 || result + sub.length > end) {
    // Not found or found but starts outside the [start, end) slice
    return -1;
  }
  return result;
}

/// Implementation for `str.count(sub[, start[, end]])`
Object? strCount(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'count',
    positionalArgs,
    keywordArgs,
    required: 1,
    maxOptional: 2,
  );
  checkNoKeywords('count', keywordArgs);
  String str = receiver as String;
  Object? subObj = positionalArgs[0];
  if (subObj is! String) {
    throw RuntimeError(
      Interpreter.builtInToken('count'),
      "TypeError: must be str, not ${Interpreter.getTypeString(subObj)}",
    );
  }
  String sub = subObj;

  int start = 0;
  int end = str.length;

  try {
    if (positionalArgs.length > 1) {
      start = expectInt(positionalArgs[1], 'count() start');
    }
    if (positionalArgs.length > 2) {
      end = expectInt(positionalArgs[2], 'count() end');
    }
  } catch (e) {
    throw RuntimeError(Interpreter.builtInToken('count'), "TypeError: $e");
  }

  // Handle Python slice indexing
  if (start < 0) start += str.length;
  if (start < 0) start = 0;
  if (start > str.length) start = str.length;

  if (end < 0) end += str.length;
  if (end < 0) end = 0;
  if (end > str.length) end = str.length;

  if (subObj == "") return end - start + 1;
  if (start >= end) return 0; // Empty slice

  int count = 0;
  int currentPos = start;
  while (currentPos < end) {
    int foundIndex = str.indexOf(sub, currentPos);
    if (foundIndex == -1 || foundIndex + sub.length > end) {
      break; // Not found anymore within the slice
    }
    count++;
    // Move position past the found substring
    currentPos = foundIndex + (sub.isEmpty ? 1 : sub.length);
    if (sub.isEmpty && currentPos > end) {
      break; // Avoid infinite loop for empty sub at end
    }
  }
  return count;
}

/// Implementation for `str.replace(old, new[, count])`
Object? strReplace(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'replace',
    positionalArgs,
    keywordArgs,
    required: 2,
    maxOptional: 1,
  );
  checkNoKeywords('replace', keywordArgs);
  String str = receiver as String;

  Object? oldObj = positionalArgs[0];
  Object? newObj = positionalArgs[1];
  if (oldObj is! String || newObj is! String) {
    throw RuntimeError(
      Interpreter.builtInToken('replace'),
      "TypeError: replace() argument must be str, not ${Interpreter.getTypeString(oldObj is! String ? oldObj : newObj)}",
    );
  }
  String oldSub = oldObj;
  String newSub = newObj;

  int count = -1; // Default: replace all
  if (positionalArgs.length > 2) {
    try {
      count = expectInt(positionalArgs[2], 'replace() count');
    } catch (e) {
      throw RuntimeError(Interpreter.builtInToken('replace'), "TypeError: $e");
    }
  }

  if (count == 0) return str; // No replacements needed
  if (count < 0) {
    return str.replaceAll(oldSub, newSub); // Replace all
  } else {
    // Replace up to 'count' times
    String result = str;
    int replacementsDone = 0;
    int currentPos = 0;
    while (replacementsDone < count) {
      int index = result.indexOf(oldSub, currentPos);
      if (index == -1) break; // No more occurrences
      result =
          result.substring(0, index) +
          newSub +
          result.substring(index + oldSub.length);
      replacementsDone++;
      // Move position past the newly inserted substring
      currentPos = index + newSub.length;
    }
    return result;
  }
}

/// Implementation for `str.split([sep[, maxsplit]])` (simplified whitespace handling)
Object? strSplit(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'split',
    positionalArgs,
    keywordArgs,
    required: 0,
    maxOptional: 2,
  );
  checkNoKeywords('split', keywordArgs);
  String str = receiver as String;

  Object? sep; // Python default is None -> split by whitespace
  int maxsplit = -1; // Python default -> no limit

  if (positionalArgs.isNotEmpty) {
    sep = positionalArgs[0];
    if (sep != null && sep is! String) {
      throw RuntimeError(
        Interpreter.builtInToken('split'),
        "TypeError: must be str or None, not ${Interpreter.getTypeString(sep)}",
      );
    }
  }
  if (positionalArgs.length > 1) {
    try {
      maxsplit = expectInt(positionalArgs[1], 'split() maxsplit');
    } catch (e) {
      throw RuntimeError(Interpreter.builtInToken('split'), "TypeError: $e");
    }
  }
  if (sep == null) {
    // Default whitespace splitting (simplified: use Dart's split with regex)
    var parts = str.trim().split(RegExp(r'\s+'));
    // Dart's split on regex can result in an initial empty string if the string starts with the separator
    if (parts.isNotEmpty && parts.first.isEmpty && str.trim().isNotEmpty) {
      parts.removeAt(0);
    }
    if (parts.length == 1 && parts[0].isEmpty && str.trim().isEmpty) {
      return <String>[]; // Split empty string is empty list
    }

    if (maxsplit < 0) {
      return parts;
    } else {
      if (parts.length <= maxsplit) return parts;
      // Combine the rest after maxsplit splits
      List<String> result = parts.sublist(0, maxsplit);
      // This part needs careful index finding to rejoin correctly based on original separators...
      // Let's simplify: just take the first maxsplit+1 elements and combine the last one from the original split index
      int splitPointIndex = 0;
      int splitsFound = 0;
      RegExp separatorRegex = RegExp(r'\s+');
      Iterable<Match> matches = separatorRegex.allMatches(str.trim());
      for (Match match in matches) {
        splitsFound++;
        if (splitsFound == maxsplit) {
          splitPointIndex =
              match.end; // End of the last separator used for splitting
          break;
        }
      }
      if (splitsFound >= maxsplit) {
        result.add(str.trim().substring(splitPointIndex));
      }
      // If fewer splits than maxsplit occurred, the original 'parts' list is already correct.

      return result;
    }
  } else {
    // Specific separator string
    String separator = sep as String;
    if (separator.isEmpty) {
      throw RuntimeError(
        Interpreter.builtInToken('split'),
        "ValueError: empty separator",
      );
    }
    // Dart's split handles maxsplit differently (limit on *returned parts*)
    // Python's maxsplit is limit on *splits performed*
    List<String> result = [];
    int currentPos = 0;
    int splitsDone = 0;
    while (true) {
      if (maxsplit >= 0 && splitsDone >= maxsplit) {
        // Max splits reached, add the rest of the string
        result.add(str.substring(currentPos));
        break;
      }
      int index = str.indexOf(separator, currentPos);
      if (index == -1) {
        // No more separators, add the rest
        result.add(str.substring(currentPos));
        break;
      } else {
        // Add the part before the separator
        result.add(str.substring(currentPos, index));
        splitsDone++;
        currentPos = index + separator.length;
      }
    }
    return result;
  }
}

/// Implementation for `str.join(iterable)`
Object? strJoin(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('join', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('join', keywordArgs);
  String separator = receiver as String;
  Object? iterableObj = positionalArgs[0];

  if (iterableObj is PyList) {
    // Check all elements are strings
    List<String> stringList = [];
    for (int i = 0; i < iterableObj.length; i++) {
      if (iterableObj.list[i] is String) {
        stringList.add(iterableObj.list[i] as String);
      } else {
        throw RuntimeError(
          Interpreter.builtInToken('join'),
          "TypeError: sequence item $i: expected str instance, ${Interpreter.getTypeString(iterableObj.list[i])} found",
        );
      }
    }
    return stringList.join(separator);
  } else if (iterableObj is String) {
    // Python allows joining a string (treats as iterable of chars)
    return iterableObj.split('').join(separator);
  }
  // TODO: Handle other iterable types if added

  throw RuntimeError(
    Interpreter.builtInToken('join'),
    "TypeError: can only join an iterable of strings (found ${Interpreter.getTypeString(iterableObj)})",
  );
}

/// Implementation for `str.upper()`
Object? strUpper(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('upper', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('upper', keywordArgs);
  return (receiver as String).toUpperCase();
}

/// Implementation for `str.lower()`
Object? strLower(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('lower', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('lower', keywordArgs);
  return (receiver as String).toLowerCase();
}

/// Implementation for `str.startswith(prefix[, start[, end]])`
Object? strStartsWith(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'startswith',
    positionalArgs,
    keywordArgs,
    required: 1,
    maxOptional: 2,
  );
  checkNoKeywords('startswith', keywordArgs);
  String str = receiver as String;
  Object? prefixObj =
      positionalArgs[0]; // single prefix string or tuple of strings

  List<String> prefixes;
  if (prefixObj is String) {
    prefixes = [prefixObj];
  } else if (prefixObj is PyTuple) {
    prefixes = [];
    for (var item in prefixObj.tuple) {
      if (item is! String) {
        throw RuntimeError(
          Interpreter.builtInToken('startswith'),
          "TypeError: startswith first arg must be str or a tuple of str, not ${Interpreter.getTypeString(item)}",
        );
      }
      prefixes.add(item);
    }
  } else {
    throw RuntimeError(
      Interpreter.builtInToken('startswith'),
      "TypeError: startswith first arg must be str or a tuple of str, not ${Interpreter.getTypeString(prefixObj)}",
    );
  }

  int start = 0;
  int end = str.length;

  try {
    if (positionalArgs.length > 1) {
      start = expectInt(positionalArgs[1], 'startswith() start');
    }
    if (positionalArgs.length > 2) {
      end = expectInt(positionalArgs[2], 'startswith() end');
    }
  } catch (e) {
    throw RuntimeError(Interpreter.builtInToken('startswith'), "TypeError: $e");
  }

  // Handle Python slice indexing
  if (start < 0) start += str.length;
  if (start < 0) start = 0;
  if (start > str.length) start = str.length;

  if (end < 0) end += str.length;
  if (end < 0) end = 0;
  if (end > str.length) end = str.length;

  for (String prefix in prefixes) {
    if (start + prefix.length <= end && str.startsWith(prefix, start)) {
      return true;
    }
  }

  return false;
}

/// Implementation for `str.endswith(suffix[, start[, end]])`
Object? strEndsWith(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'endswith',
    positionalArgs,
    keywordArgs,
    required: 1,
    maxOptional: 2,
  );
  checkNoKeywords('endswith', keywordArgs);
  String str = receiver as String;
  Object? suffixObj = positionalArgs[0];

  List<String> suffixes;
  if (suffixObj is String) {
    suffixes = [suffixObj];
  } else if (suffixObj is PyTuple) {
    suffixes = [];
    for (var item in suffixObj.tuple) {
      if (item is! String) {
        throw RuntimeError(
          Interpreter.builtInToken('endswith'),
          "TypeError: endswith first arg must be str or a tuple of str, not ${Interpreter.getTypeString(item)}",
        );
      }
      suffixes.add(item);
    }
  } else {
    throw RuntimeError(
      Interpreter.builtInToken('endswith'),
      "TypeError: endswith first arg must be str or a tuple of str, not ${Interpreter.getTypeString(suffixObj)}",
    );
  }

  int start = 0;
  int end = str.length;

  try {
    if (positionalArgs.length > 1) {
      start = expectInt(positionalArgs[1], 'endswith() start');
    }
    if (positionalArgs.length > 2) {
      end = expectInt(positionalArgs[2], 'endswith() end');
    }
  } catch (e) {
    throw RuntimeError(Interpreter.builtInToken('endswith'), "TypeError: $e");
  }

  // Handle Python slice indexing
  if (start < 0) start += str.length;
  if (start < 0) start = 0;
  if (start > str.length) start = str.length;

  if (end < 0) end += str.length;
  if (end < 0) end = 0;
  if (end > str.length) end = str.length;

  // Dart's endsWith doesn't take start/end, so we work on the relevant substring
  if (start > end) return false; // Empty slice
  String relevantSubstring = str.substring(start, end);

  for (String suffix in suffixes) {
    if (start + suffix.length <= end && relevantSubstring.endsWith(suffix)) {
      return true;
    }
  }
  return false;
}

/// Implementation for `str.strip([chars])`
Object? strStrip(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'strip',
    positionalArgs,
    keywordArgs,
    required: 0,
    maxOptional: 1,
  );
  checkNoKeywords('strip', keywordArgs);
  String str = receiver as String;
  Object? charsObj = positionalArgs.isNotEmpty ? positionalArgs[0] : null;

  if (charsObj == null) {
    return str.trim(); // Default: trim whitespace
  } else if (charsObj is String) {
    String chars = charsObj;
    if (chars.isEmpty) return str; // Stripping empty set does nothing

    int start = 0;
    while (start < str.length && chars.contains(str[start])) {
      start++;
    }
    int end = str.length - 1;
    while (end >= start && chars.contains(str[end])) {
      end--;
    }
    return str.substring(start, end + 1);
  } else {
    throw RuntimeError(
      Interpreter.builtInToken('strip'),
      "TypeError: must be str or None, not ${Interpreter.getTypeString(charsObj)}",
    );
  }
}

/// Implementation for `str.lstrip([chars])`
Object? strLstrip(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'lstrip',
    positionalArgs,
    keywordArgs,
    required: 0,
    maxOptional: 1,
  );
  checkNoKeywords('lstrip', keywordArgs);
  String str = receiver as String;
  Object? charsObj = positionalArgs.isNotEmpty ? positionalArgs[0] : null;

  if (charsObj == null) {
    return str.trimLeft(); // Default: trim leading whitespace
  } else if (charsObj is String) {
    String chars = charsObj;
    if (chars.isEmpty) return str;
    int start = 0;
    while (start < str.length && chars.contains(str[start])) {
      start++;
    }
    return str.substring(start);
  } else {
    throw RuntimeError(
      Interpreter.builtInToken('lstrip'),
      "TypeError: must be str or None, not ${Interpreter.getTypeString(charsObj)}",
    );
  }
}

/// Implementation for `str.rstrip([chars])`
Object? strRstrip(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'rstrip',
    positionalArgs,
    keywordArgs,
    required: 0,
    maxOptional: 1,
  );
  checkNoKeywords('rstrip', keywordArgs);
  String str = receiver as String;
  Object? charsObj = positionalArgs.isNotEmpty ? positionalArgs[0] : null;

  if (charsObj == null) {
    return str.trimRight(); // Default: trim trailing whitespace
  } else if (charsObj is String) {
    String chars = charsObj;
    if (chars.isEmpty) return str;
    int end = str.length - 1;
    while (end >= 0 && chars.contains(str[end])) {
      end--;
    }
    return str.substring(0, end + 1);
  } else {
    throw RuntimeError(
      Interpreter.builtInToken('rstrip'),
      "TypeError: must be str or None, not ${Interpreter.getTypeString(charsObj)}",
    );
  }
}

// Tuple Methods (operate on List<Object?>)
Object? _tupleCount(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('count', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('count', keywordArgs);
  final valueToCount = positionalArgs[0];
  List tuple = (receiver as PyTuple).tuple;
  int count = 0;
  for (final item in tuple) {
    if (interpreter.isEqual(item, valueToCount)) {
      count++;
    }
  }
  return count;
}

Object? _tupleIndex(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs(
    'index',
    positionalArgs,
    keywordArgs,
    required: 1,
    maxOptional: 2,
  );
  checkNoKeywords('index', keywordArgs);
  List tuple = (receiver as PyTuple).tuple;
  // Logic is identical to _listIndex, maybe reuse?
  final valueToFind = positionalArgs[0];
  int start = 0;
  int stop = tuple.length;
  // ... (parse start/stop, handle slice indices, loop and check with isEqual) ...
  try {
    if (positionalArgs.length > 1 && positionalArgs[1] is! int) {
      throw "TypeError: slice indices must be integers";
    }
    if (positionalArgs.length > 2 && positionalArgs[2] is! int) {
      throw "TypeError: slice indices must be integers";
    }
    if (positionalArgs.length > 1) {
      start = expectInt(positionalArgs[1], 'index() start');
    }
    if (positionalArgs.length > 2) {
      stop = expectInt(positionalArgs[2], 'index() stop');
    }
  } catch (e) {
    /* ... TypeError ... */
    throw RuntimeError(Interpreter.builtInToken('index'), "TypeError: $e");
  }

  // Handle Python slice indexing for start/stop
  if (start < 0) start += tuple.length;
  if (start < 0) start = 0;
  if (start > tuple.length) start = tuple.length;
  if (stop < 0) stop += tuple.length;
  if (stop < 0) stop = 0;
  if (stop > tuple.length) stop = tuple.length;

  for (int i = start; i < stop; i++) {
    if (interpreter.isEqual(tuple[i], valueToFind)) return i;
  }
  throw RuntimeError(
    Interpreter.builtInToken('index'),
    "ValueError: tuple.index(x): x not in tuple",
  );
}

// Set Methods (operate on Set<Object?>)
Object? _setAdd(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('add', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('add', keywordArgs);
  Set set = receiver as Set;
  final element = positionalArgs[0];
  if (!Interpreter.isHashable(element)) {
    throw RuntimeError(
      Interpreter.builtInToken('add'),
      "TypeError: unhashable type: '${Interpreter.getTypeString(element)}'",
    );
  }
  // --- Python bool/int equivalence check ---
  bool skipAdd = false;
  if (element == true) {
    if (set.contains(1)) skipAdd = true;
  } else if (element == 1) {
    if (set.contains(true)) skipAdd = true;
  } else if (element == false) {
    if (set.contains(0)) skipAdd = true;
  } else if (element == 0) {
    if (set.contains(false)) skipAdd = true;
  }
  if (!skipAdd) {
    set.add(element);
  }
  return null; // add returns None
}

Object? _setRemove(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('remove', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('remove', keywordArgs);
  Set set = receiver as Set;
  final element = positionalArgs[0];
  if (!Interpreter.isHashable(element)) {
    throw RuntimeError(
      Interpreter.builtInToken('remove'),
      "TypeError: unhashable type: '${Interpreter.getTypeString(element)}'",
    );
  }
  bool removed = set.remove(element);
  if (!removed) {
    throw RuntimeError(
      Interpreter.builtInToken('remove'),
      "KeyError: ${interpreter.repr(element)}",
    );
  }
  return null; // remove returns None
}

Object? _setDiscard(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('discard', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('discard', keywordArgs);
  Set set = receiver as Set;
  final element = positionalArgs[0];
  if (!Interpreter.isHashable(element)) {
    // discard ignores unhashable types silently in Python
    return null;
    // Or throw: throw RuntimeError(Interpreter.builtInToken('discard'), "TypeError: unhashable type: '${Interpreter.getTypeString(element)}'");
  }
  set.remove(element); // Dart's remove returns bool, but discard ignores it
  return null; // discard returns None
}

Object? _setPop(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('pop', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('pop', keywordArgs);
  Set set = receiver as Set;
  if (set.isEmpty) {
    throw RuntimeError(
      Interpreter.builtInToken('pop'),
      "KeyError: 'pop from an empty set'",
    );
  }
  // Get an arbitrary element, remove it, return it
  var element =
      set.first; // Dart Set iteration order isn't guaranteed like Python
  set.remove(element);
  return element;
}

Object? _setClear(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('clear', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('clear', keywordArgs);
  (receiver as Set).clear();
  return null;
}

Object? _setCopy(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('copy', positionalArgs, keywordArgs, required: 0);
  checkNoKeywords('copy', keywordArgs);
  return Set.from(receiver as Set); // Shallow copy
}

// Helper to get another set from args for binary operations
Set<Object?> _getOtherSet(
  Interpreter interpreter,
  String methodName,
  List<Object?> args,
) {
  if (args.isEmpty) {
    throw RuntimeError(
      Interpreter.builtInToken(methodName),
      "TypeError: $methodName() missing 1 required argument: 'other'",
    );
  }
  Object? otherArg = args[0];
  if (otherArg is Set) {
    return otherArg;
  }
  // Python allows any iterable here, converts it to a set first
  if (otherArg is Map) {
    otherArg = otherArg.keys;
  } else if (otherArg is String) {
    otherArg = otherArg.split('');
  } else if (otherArg is PyList) {
    otherArg = otherArg.list;
  } else if (otherArg is PyTuple) {
    otherArg = otherArg.tuple;
  }
  if (otherArg is Iterable) {
    Set<Object?> otherSet = {};
    for (var item in otherArg) {
      if (!Interpreter.isHashable(item)) {
        throw RuntimeError(
          Interpreter.builtInToken(methodName),
          "TypeError: unhashable type: '${Interpreter.getTypeString(item)}'",
        );
      }
      otherSet.add(item);
    }
    return otherSet;
  }
  throw RuntimeError(
    Interpreter.builtInToken(methodName),
    "TypeError: '${Interpreter.getTypeString(otherArg)}' object is not iterable",
  );
}

Object? _setUnion(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  // Python's union can take multiple iterables, simplify to one 'other'
  checkNumArgs('union', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('union', keywordArgs);
  Set self = receiver as Set;
  Set other = _getOtherSet(interpreter, 'union', positionalArgs);
  return self.union(other); // Returns a new set
}

Object? _setIntersection(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('intersection', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('intersection', keywordArgs);
  Set self = receiver as Set;
  Set other = _getOtherSet(interpreter, 'intersection', positionalArgs);
  return self.intersection(other); // Returns a new set
}

Object? _setDifference(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('difference', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('difference', keywordArgs);
  Set self = receiver as Set;
  Set other = _getOtherSet(interpreter, 'difference', positionalArgs);
  return self.difference(other); // Returns a new set
}

Object? _setIsdisjoint(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('isdisjoint', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('isdisjoint', keywordArgs);
  Set self = receiver as Set;
  Set other = _getOtherSet(interpreter, 'isdisjoint', positionalArgs);
  return self.intersection(other).isEmpty;
}

Object? _setIsSubset(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('issubset', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('issubset', keywordArgs);
  Set self = receiver as Set;
  Set other = _getOtherSet(interpreter, 'issubset', positionalArgs);
  if (self.length > other.length) return false;
  return other.containsAll(self);
}

Object? _setIsSuperset(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  checkNumArgs('issuperset', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('issuperset', keywordArgs);
  Set self = receiver as Set;
  Set other = _getOtherSet(interpreter, 'issuperset', positionalArgs);
  if (self.length < other.length) return false;
  return self.containsAll(other);
}

Object? _setUpdate(
  Interpreter interpreter,
  Object receiver,
  List<Object?> positionalArgs,
  Map<String, Object?> keywordArgs,
) {
  // Python's update takes multiple iterables. Simplify to one.
  checkNumArgs('update', positionalArgs, keywordArgs, required: 1);
  checkNoKeywords('update', keywordArgs);
  Set self = receiver as Set;
  // Convert argument to a set (handles any iterable)
  Set other = _getOtherSet(interpreter, 'update', positionalArgs);
  self.addAll(other); // Modifies in-place
  return null; // update returns None
}
