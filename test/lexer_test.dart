import 'package:simplepy/src/lexer.dart';
import 'package:test/test.dart';

void main() {
  group('Lexer Basics', () {
    test('should tokenize basic operators', () {
      final source = '+ - * / = == != < <= > >= % ** //';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final types = tokens.map((t) => t.type).toList();

      expect(types, equals([
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
      ]));
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

    test('should tokenize keywords and identifiers', () {
      final source = 'if my_var else def';
      final lexer = Lexer(source);
      final tokens = lexer.scanTokens();
      final types = tokens.map((t) => t.type).toList();

      expect(types, equals([
        TokenType.IF,
        TokenType.IDENTIFIER,
        TokenType.ELSE,
        TokenType.DEF,
        TokenType.EOF,
      ]));
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
      expect(types, containsAllInOrder([
        // var = 1
        TokenType.IDENTIFIER, TokenType.EQUAL, TokenType.NUMBER, TokenType.NEWLINE,
        // if var > 0:
        TokenType.IF, TokenType.IDENTIFIER, TokenType.GREATER, TokenType.NUMBER, TokenType.COLON, TokenType.NEWLINE,
        // Indent Block 1
        TokenType.INDENT,
        TokenType.IDENTIFIER, TokenType.LEFT_PAREN, TokenType.IDENTIFIER, TokenType.RIGHT_PAREN, TokenType.NEWLINE, // print(var)
        TokenType.IDENTIFIER, TokenType.EQUAL, TokenType.NUMBER, TokenType.NEWLINE, // other = 2
        // Dedent Block 1, Start Else
        TokenType.DEDENT, TokenType.ELSE, TokenType.COLON, TokenType.NEWLINE,
        // Indent Block 2
        TokenType.INDENT,
        TokenType.IDENTIFIER, TokenType.LEFT_PAREN, TokenType.STRING, TokenType.RIGHT_PAREN, TokenType.NEWLINE, // print(...)
        // Dedent Block 2, Start Final Print
        TokenType.DEDENT,
        TokenType.IDENTIFIER, TokenType.LEFT_PAREN, TokenType.STRING, TokenType.RIGHT_PAREN, // print("done")
        TokenType.EOF,
      ]));
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
       expect(types, containsAllInOrder([
        TokenType.IDENTIFIER, TokenType.EQUAL, TokenType.NUMBER, TokenType.NEWLINE,
        TokenType.IDENTIFIER, TokenType.LEFT_PAREN, TokenType.IDENTIFIER, TokenType.RIGHT_PAREN,
        TokenType.EOF,
      ]));
    });

    test('should throw LexerError for unterminated string', () {
      final source = 'name = "Bob';
      final lexer = Lexer(source);
      expect(() => lexer.scanTokens(), throwsA(isA<LexerError>()));
    });
  });
}