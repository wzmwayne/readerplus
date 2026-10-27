/// 纯 Dart 的 JavaScript（ES5 子集）词法与语法分析。
///
/// 只解析、不求值；求值见 js_interpreter.dart。
/// 支持：var/let/const、if/else、while、do-while、for、for-in/of、
/// return/break/continue、throw、try/catch/finally、function 声明与表达式、
/// 三元、逻辑、算术、比较、赋值、成员/下标、调用、new、数组/对象字面量、
/// 字符串（单/双引号）、数字、true/false/null/undefined。
/// 不支持（明确报错）：class、import/export、async/await、yield、解构、展开、eval。
library;

class JsSyntaxError implements Exception {
  JsSyntaxError(this.message, this.line, this.column);
  final String message;
  final int line;
  final int column;
  @override
  String toString() => '语法错误（第 $line 行第 $column 列）：$message';
}

enum TokKind {
  number,
  string,
  ident,
  keyword,
  punct,
  eof,
}

class Token {
  const Token(this.kind, this.text, this.line, this.column, {this.numberValue});
  final TokKind kind;
  final String text;
  final int line;
  final int column;
  final num? numberValue;

  @override
  String toString() => '${kind.name}:$text';
}

const Set<String> _keywords = {
  'var', 'let', 'const', 'function', 'return', 'if', 'else', 'while', 'do',
  'for', 'in', 'of', 'break', 'continue', 'throw', 'try', 'catch', 'finally',
  'true', 'false', 'null', 'undefined', 'new', 'typeof', 'this', 'switch',
  'case', 'default', 'delete', 'void',
  // 保留但明确不支持（解析时给出清晰错误）
  'class', 'extends', 'import', 'export', 'async', 'await', 'yield', 'super',
};

class Lexer {
  Lexer(this.source);

  final String source;
  int _pos = 0;
  int _line = 1;
  int _col = 1;

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (true) {
      _skipSpaceAndComments();
      if (_pos >= source.length) {
        tokens.add(Token(TokKind.eof, '', _line, _col));
        return tokens;
      }
      final ch = source[_pos];
      if (_isDigit(ch)) {
        tokens.add(_number());
      } else if (ch == '"' || ch == "'") {
        tokens.add(_string(ch));
      } else if (_isIdentStart(ch)) {
        tokens.add(_ident());
      } else {
        tokens.add(_punct());
      }
    }
  }

  void _skipSpaceAndComments() {
    while (_pos < source.length) {
      final ch = source[_pos];
      if (ch == ' ' || ch == '\t' || ch == '\r') {
        _advance();
      } else if (ch == '\n') {
        _advance();
        _line++;
        _col = 1;
      } else if (ch == '/' && _pos + 1 < source.length && source[_pos + 1] == '/') {
        while (_pos < source.length && source[_pos] != '\n') {
          _advance();
        }
      } else if (ch == '/' && _pos + 1 < source.length && source[_pos + 1] == '*') {
        _advance();
        _advance();
        while (_pos + 1 < source.length &&
            !(source[_pos] == '*' && source[_pos + 1] == '/')) {
          if (source[_pos] == '\n') {
            _line++;
            _col = 1;
          }
          _advance();
        }
        _advance();
        _advance();
      } else {
        return;
      }
    }
  }

  void _advance() {
    _pos++;
    _col++;
  }

  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

  bool _isIdentStart(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F ||
        code == 0x24 ||
        code > 0x7F;
  }

  bool _isIdentPart(String ch) => _isIdentStart(ch) || _isDigit(ch);

  Token _number() {
    final start = _pos;
    final line = _line;
    final col = _col;
    while (_pos < source.length && (_isDigit(source[_pos]) || source[_pos] == '.')) {
      _advance();
    }
    final text = source.substring(start, _pos);
    return Token(TokKind.number, text, line, col, numberValue: num.parse(text));
  }

  Token _string(String quote) {
    final line = _line;
    final col = _col;
    _advance();
    final buffer = StringBuffer();
    while (_pos < source.length) {
      final ch = source[_pos];
      if (ch == quote) {
        _advance();
        return Token(TokKind.string, buffer.toString(), line, col);
      }
      if (ch == '\\' && _pos + 1 < source.length) {
        _advance();
        final esc = source[_pos];
        switch (esc) {
          case 'n':
            buffer.write('\n');
          case 't':
            buffer.write('\t');
          case 'r':
            buffer.write('\r');
          case '\\':
            buffer.write('\\');
          case "'":
            buffer.write("'");
          case '"':
            buffer.write('"');
          default:
            buffer.write(esc);
        }
        _advance();
        continue;
      }
      if (ch == '\n') break;
      buffer.write(ch);
      _advance();
    }
    throw JsSyntaxError('字符串未闭合', line, col);
  }

  Token _ident() {
    final start = _pos;
    final line = _line;
    final col = _col;
    while (_pos < source.length && _isIdentPart(source[_pos])) {
      _advance();
    }
    final text = source.substring(start, _pos);
    return Token(
      _keywords.contains(text) ? TokKind.keyword : TokKind.ident,
      text,
      line,
      col,
    );
  }

  static const List<String> _ops = [
    '===', '!==', '==', '!=', '<=', '>=', '&&', '||', '+=', '-=', '*=', '/=', '++', '--',
    '+', '-', '*', '/', '%', '=', '<', '>', '!', '?', ':', ';', ',', '.', '(', ')',
    '[', ']', '{', '}',
  ];

  Token _punct() {
    final line = _line;
    final col = _col;
    for (final op in _ops) {
      if (source.startsWith(op, _pos)) {
        for (var i = 0; i < op.length; i++) {
          _advance();
        }
        return Token(TokKind.punct, op, line, col);
      }
    }
    throw JsSyntaxError('无法识别的字符 ${source[_pos]}', line, col);
  }
}