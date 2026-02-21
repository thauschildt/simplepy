import 'package:simplepy/src/lexer.dart';
import 'package:test/test.dart';
import 'package:test/test.dart' as testpkg;

final _origExpect = testpkg.expect;
void expect(
  dynamic actual,
  dynamic expected, {
  dynamic matcher,
  dynamic reason,
}) {
  matcher ??= expected;
  if (matcher is int && actual is! int) {
    matcher = BigInt.from(matcher);
  }
  _origExpect(actual, matcher, reason: reason);
}

void main() {
  group('Lexer Basics', () {
    test('should tokenize basic operators', () {
      final source = '+ - * / = == != < <= > >= % ** //';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final types = tokens.map((t) => t.type).toList();

      expect(
        types,
        equals([
          TokenType.PLUS,
          TokenType.MINUS,
          TokenType.STAR,
          TokenType.SLASH,
          TokenType.EQUAL,
          TokenType.EQUAL_EQUAL,
          TokenType.BANG_EQUAL,
          TokenType.LESS,
          TokenType.LESS_EQUAL,
          TokenType.GREATER,
          TokenType.GREATER_EQUAL,
          TokenType.PERCENT,
          TokenType.STAR_STAR,
          TokenType.SLASH_SLASH,
          TokenType.EOF,
        ]),
      );
    });

    test('should tokenize literals', () {
      final source = '123 45.67 "hello" \'world\' True False None';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();

      expect(tokens[0].type, TokenType.NUMBER);
      expect(tokens[0].literal, 123);
      expect(tokens[1].type, TokenType.NUMBER);
      expect(tokens[1].literal, 45.67);
      expect(tokens[2].type, TokenType.STRING);
      expect(tokens[2].literal, 'hello');
      expect(tokens[3].type, TokenType.STRING);
      expect(tokens[3].literal, 'world');
      expect(tokens[4].type, TokenType.TRUE);
      expect(tokens[4].literal, null); // Keywords usually don't have literals
      expect(tokens[5].type, TokenType.FALSE);
      expect(tokens[6].type, TokenType.NONE);
      expect(tokens[7].type, TokenType.EOF);
    });

    test('should tokenize hexadecimal integers', () {
      final source = '0xFF 0x1a 0X0 0x123ABC';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();

      expect(tokens.length, 5); // 4 numbers + EOF
      expect(tokens[0].type, TokenType.NUMBER);
      expect(tokens[0].literal, 255);
      expect(tokens[0].lexeme, '0xFF');
      expect(tokens[1].type, TokenType.NUMBER);
      expect(tokens[1].literal, 26);
      expect(tokens[1].lexeme, '0x1a');
      expect(tokens[2].type, TokenType.NUMBER);
      expect(tokens[2].literal, 0);
      expect(tokens[2].lexeme, '0X0');
      expect(tokens[3].type, TokenType.NUMBER);
      expect(tokens[3].literal, 1194684); // 0x123ABC
      expect(tokens[3].lexeme, '0x123ABC');
      expect(tokens[4].type, TokenType.EOF);
    });

    test('should tokenize binary integers', () {
      final source = '0b101 0B1100 0b0';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();

      expect(tokens.length, 4); // 3 numbers + EOF
      expect(tokens[0].type, TokenType.NUMBER);
      expect(tokens[0].literal, 5);
      expect(tokens[1].type, TokenType.NUMBER);
      expect(tokens[1].literal, 12);
      expect(tokens[2].type, TokenType.NUMBER);
      expect(tokens[2].literal, 0);
      expect(tokens[3].type, TokenType.EOF);
    });

    test('should tokenize octal integers', () {
      final source = '0o123 0O777 0o0';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();

      expect(tokens.length, 4); // 3 numbers + EOF
      expect(tokens[0].type, TokenType.NUMBER);
      expect(tokens[0].literal, 83); // 1*64 + 2*8 + 3*1
      expect(tokens[1].type, TokenType.NUMBER);
      expect(tokens[1].literal, 511); // 7*64 + 7*8 + 7*1
      expect(tokens[2].type, TokenType.NUMBER);
      expect(tokens[2].literal, 0);
      expect(tokens[3].type, TokenType.EOF);
    });

    test('should handle mixed numbers and prefixes', () {
      final source = '123 0x40 0.5 .5 5. 0b10 99 0o7';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final literals =
          tokens
              .where((t) => t.type == TokenType.NUMBER)
              .map((t) => t.literal)
              .toList();
      var expected = [123, 64, 0.5, 0.5, 5.0, 2, 99, 7];
      for (var i = 0; i < literals.length; i++) {
        expect(literals[i], expected[i]);
      }
    });

    test('should throw LexerError for invalid prefixed numbers', () {
      expect(
        () => Lexer('0x').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Missing digits after'),
          ),
        ),
      );
      expect(
        () => Lexer('0b').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Missing digits after'),
          ),
        ),
      );
      expect(
        () => Lexer('0o').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Missing digits after'),
          ),
        ),
      );
      expect(
        () => Lexer('0xG').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Invalid hexadecimal literal'),
          ),
        ),
      );
      expect(
        () => Lexer('0b2').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Invalid binary literal'),
          ),
        ),
      );
      expect(
        () => Lexer('0o8').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Invalid octal literal'),
          ),
        ),
      );
    });

    test('should throw LexerError for invalid numbers', () {
      expect(
        () => Lexer('12..3').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Invalid decimal literal.'),
          ),
        ),
      );
      expect(
        () => Lexer('1.2.3').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Invalid decimal literal.'),
          ),
        ),
      );
      expect(
        () => Lexer('123.join()').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('Invalid decimal literal.'),
          ),
        ),
      );
    });

    test('should tokenize keywords and identifiers', () {
      final source = 'if my_var else def';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final types = tokens.map((t) => t.type).toList();

      expect(
        types,
        equals([
          TokenType.IF,
          TokenType.IDENTIFIER,
          TokenType.ELSE,
          TokenType.DEF,
          TokenType.EOF,
        ]),
      );
      expect(tokens[1].lexeme, 'my_var');
    });

    test('should handle basic indentation', () {
      final source = '''
var = 1
if var > 0:
  print(var)
  other = 2
else:
  print("zero or less")
print("done")
''';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final types = tokens.map((t) => t.type).toList();

      // Expect specific INDENT/DEDENT/NEWLINE sequence
      // Note: NEWLINEs are implicitly added *before* INDENT/DEDENT sometimes
      expect(
        types,
        containsAllInOrder([
          // var = 1
          TokenType.IDENTIFIER,
          TokenType.EQUAL,
          TokenType.NUMBER,
          TokenType.NEWLINE,
          // if var > 0:
          TokenType.IF,
          TokenType.IDENTIFIER,
          TokenType.GREATER,
          TokenType.NUMBER,
          TokenType.COLON,
          TokenType.NEWLINE,
          // Indent Block 1
          TokenType.INDENT,
          TokenType.IDENTIFIER,
          TokenType.LEFT_PAREN,
          TokenType.IDENTIFIER,
          TokenType.RIGHT_PAREN,
          TokenType.NEWLINE, // print(var)
          TokenType.IDENTIFIER,
          TokenType.EQUAL,
          TokenType.NUMBER,
          TokenType.NEWLINE, // other = 2
          // Dedent Block 1, Start Else
          TokenType.DEDENT, TokenType.ELSE, TokenType.COLON, TokenType.NEWLINE,
          // Indent Block 2
          TokenType.INDENT,
          TokenType.IDENTIFIER,
          TokenType.LEFT_PAREN,
          TokenType.STRING,
          TokenType.RIGHT_PAREN,
          TokenType.NEWLINE, // print(...)
          // Dedent Block 2, Start Final Print
          TokenType.DEDENT,
          TokenType.IDENTIFIER,
          TokenType.LEFT_PAREN,
          TokenType.STRING,
          TokenType.RIGHT_PAREN, // print("done")
          TokenType.EOF,
        ]),
      );
    });

    test('should ignore comments', () {
      final source = '''
# This is a full line comment
x = 1 # This is an end-of-line comment
print(x) # Another comment
# Another line comment
''';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final types = tokens.map((t) => t.type).toList();

      // Verify that comments are skipped and structure is preserved
      expect(
        types,
        containsAllInOrder([
          TokenType.IDENTIFIER,
          TokenType.EQUAL,
          TokenType.NUMBER,
          TokenType.NEWLINE,
          TokenType.IDENTIFIER,
          TokenType.LEFT_PAREN,
          TokenType.IDENTIFIER,
          TokenType.RIGHT_PAREN,
          TokenType.EOF,
        ]),
      );
    });

    test('should throw LexerError for unterminated string', () {
      final source = 'name = "Bob';
      final lexer = Lexer(source);
      expect(() => lexer.scanTokens(), throwsA(isA<LexerError>()));
    });

    test('should tokenize floats in scientific notation', () {
      final sources = {
        '1e5': 100000.0,
        '1.2e3': 1200.0,
        '0.5E-1': 0.05,
        '1E+10': 10000000000.0,
        '123.456e-2': 1.23456,
        '6.022E23': 6.022e23,
        '1e0': 1.0,
        '1e-0': 1.0,
      };

      for (var entry in sources.entries) {
        final source = entry.key;
        final expectedValue = entry.value;
        final lexer = Lexer(source);
        final tokens = lexer.scanTokens();
        expect(tokens.length, 2, reason: "Source: $source"); // Number + EOF
        expect(tokens[0].type, TokenType.NUMBER, reason: "Source: $source");
        expect(tokens[0].lexeme, source, reason: "Source: $source");
        // Use closeTo for floating point comparisons due to potential precision differences
        expect(
          tokens[0].literal,
          closeTo(expectedValue, 1e-9),
          reason: "Source: $source",
        );
      }
    });

    test('should handle numbers adjacent to scientific notation', () {
      final source = '1.2e3+5'; // 1200.0 + 5
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      expect(
        tokens.map((t) => t.type).toList(),
        equals([
          TokenType.NUMBER,
          TokenType.PLUS,
          TokenType.NUMBER,
          TokenType.EOF,
        ]),
      );
      expect(tokens[0].literal, 1200.0);
      expect(tokens[2].literal, 5);
    });

    test('should tokenize floats with exponent after dot', () {
      final sources = {
        '1.e5': 100000.0,
        '0.e1': 0.0,
        '123.E-2': 1.23,
        '.5e2': 50.0, // Dot first, then digits, then exponent
        '.1E-1': 0.01,
      };

      for (var entry in sources.entries) {
        final source = entry.key;
        final expectedValue = entry.value;
        final lexer = Lexer(source);
        final tokens = lexer.scanTokens();
        expect(tokens.length, 2, reason: "Source: $source"); // Number + EOF
        expect(tokens[0].type, TokenType.NUMBER, reason: "Source: $source");
        expect(tokens[0].lexeme, source, reason: "Source: $source");
        expect(
          tokens[0].literal,
          closeTo(expectedValue, 1e-9),
          reason: "Source: $source",
        );
      }
    });

    test('should distinguish DOT from start of float', () {
      final lexer1 = Lexer('.');
      final tokens1 = lexer1.scanTokens();
      expect(
        tokens1.map((t) => t.type).toList(),
        equals([TokenType.DOT, TokenType.EOF]),
      );

      final lexer2 = Lexer('.5');
      final tokens2 = lexer2.scanTokens();
      expect(
        tokens2.map((t) => t.type).toList(),
        equals([TokenType.NUMBER, TokenType.EOF]),
      );
      expect(tokens2[0].literal, 0.5);

      final lexer3 = Lexer('obj.attr');
      final tokens3 = lexer3.scanTokens();
      expect(
        tokens3.map((t) => t.type).toList(),
        equals([
          TokenType.IDENTIFIER,
          TokenType.DOT,
          TokenType.IDENTIFIER,
          TokenType.EOF,
        ]),
      );
    });

    test('should handle number ending with dot correctly', () {
      // Python tokenizer allows "1.". Let's see if our parser does.
      final lexer = Lexer('1.');
      final tokens = lexer.scanTokens();
      expect(
        tokens.map((t) => t.type).toList(),
        equals([TokenType.NUMBER, TokenType.EOF]),
      );
      expect(tokens[0].literal, 1.0);

      final lexer2 = Lexer('1. + 2');
      final tokens2 = lexer2.scanTokens();
      expect(
        tokens2.map((t) => t.type).toList(),
        equals([
          TokenType.NUMBER,
          TokenType.PLUS,
          TokenType.NUMBER,
          TokenType.EOF,
        ]),
      );
      expect(tokens2[0].literal, 1.0);
    });

    test('should throw LexerError for invalid dot/exponent combinations', () {
      expect(
        () => Lexer('1.e').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('exponent lacks digits'),
          ),
        ),
      );
      final tokensDot = Lexer('.').scanTokens();
      expect(
        tokensDot.map((t) => t.type).toList(),
        equals([TokenType.DOT, TokenType.EOF]),
      );
    });

    test('should throw LexerError for invalid scientific notation', () {
      // 'e' without digits
      expect(
        () => Lexer('1e').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('exponent lacks digits'),
          ),
        ),
      );
      // 'e' with sign but no digits
      expect(
        () => Lexer('1e+').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('exponent lacks digits'),
          ),
        ),
      );
      expect(
        () => Lexer('1.5e-').scanTokens(),
        throwsA(
          isA<LexerError>().having(
            (e) => e.message,
            'message',
            contains('exponent lacks digits'),
          ),
        ),
      );
      // Multiple 'e's (second e treated as identifier or error) - current behavior might vary
      // expect(() => Lexer('1e5e2').scanTokens(), throwsA(isA<LexerError>())); // Or parses as 1e5 then identifier 'e2'
      // Dot after 'e'
      expect(
        () => Lexer('1e.5').scanTokens(),
        throwsA(isA<LexerError>()),
      ); // Should fail after 'e' parsing digits
    });
  });
}
