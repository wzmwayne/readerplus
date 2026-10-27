import 'js_lexer.dart';

// ---------------- AST ----------------

abstract class JsNode {
  const JsNode();
}

class NumLit extends JsNode {
  const NumLit(this.value);
  final num value;
}

class StrLit extends JsNode {
  const StrLit(this.value);
  final String value;
}

class BoolLit extends JsNode {
  const BoolLit(this.value);
  final bool value;
}

class NullLit extends JsNode {
  const NullLit();
}

class UndefinedLit extends JsNode {
  const UndefinedLit();
}

class Ident extends JsNode {
  const Ident(this.name);
  final String name;
}

class ArrayLit extends JsNode {
  const ArrayLit(this.items);
  final List<JsNode> items;
}

class ObjectLit extends JsNode {
  const ObjectLit(this.entries);
  final List<MapEntry<String, JsNode>> entries;
}

class Member extends JsNode {
  const Member(this.target, this.name);
  final JsNode target;
  final String name;
}

class Index extends JsNode {
  const Index(this.target, this.index);
  final JsNode target;
  final JsNode index;
}

class Call extends JsNode {
  const Call(this.callee, this.args);
  final JsNode callee;
  final List<JsNode> args;
}

class NewExpr extends JsNode {
  const NewExpr(this.callee, this.args);
  final JsNode callee;
  final List<JsNode> args;
}

class Unary extends JsNode {
  const Unary(this.op, this.operand);
  final String op;
  final JsNode operand;
}

class Update extends JsNode {
  const Update(this.op, this.target, {required this.prefix});
  final String op;
  final JsNode target;
  final bool prefix;
}

class Binary extends JsNode {
  const Binary(this.op, this.left, this.right, {this.logical = false});
  final String op;
  final JsNode left;
  final JsNode right;
  final bool logical;
}

class Conditional extends JsNode {
  const Conditional(this.test, this.consequent, this.alternate);
  final JsNode test;
  final JsNode consequent;
  final JsNode alternate;
}

class Assign extends JsNode {
  const Assign(this.op, this.target, this.value);
  final String op;
  final JsNode target;
  final JsNode value;
}

class FuncExpr extends JsNode {
  const FuncExpr(this.params, this.body, {this.name});
  final List<String> params;
  final List<JsStmt> body;
  final String? name;
}

// ---------------- 语句 ----------------

abstract class JsStmt {
  const JsStmt();
}

class Block extends JsStmt {
  const Block(this.body);
  final List<JsStmt> body;
}

class VarDecl extends JsStmt {
  const VarDecl(this.name, this.init);
  final String name;
  final JsNode? init;
}

class FuncDecl extends JsStmt {
  const FuncDecl(this.name, this.params, this.body);
  final String name;
  final List<String> params;
  final List<JsStmt> body;
}

class ExprStmt extends JsStmt {
  const ExprStmt(this.expr);
  final JsNode expr;
}

class IfStmt extends JsStmt {
  const IfStmt(this.test, this.consequent, this.alternate);
  final JsNode test;
  final JsStmt consequent;
  final JsStmt? alternate;
}

class WhileStmt extends JsStmt {
  const WhileStmt(this.test, this.body);
  final JsNode test;
  final JsStmt body;
}

class DoWhileStmt extends JsStmt {
  const DoWhileStmt(this.body, this.test);
  final JsStmt body;
  final JsNode test;
}

class ForStmt extends JsStmt {
  const ForStmt(this.init, this.test, this.update, this.body);
  final JsStmt? init;
  final JsNode? test;
  final JsNode? update;
  final JsStmt body;
}

/// `for (x in obj)` / `for (x of iter)`：mode 为 'in' 或 'of'。
class ForInStmt extends JsStmt {
  const ForInStmt(this.name, this.mode, this.iterable, this.body);
  final String name;
  final String mode;
  final JsNode iterable;
  final JsStmt body;
}

class ReturnStmt extends JsStmt {
  const ReturnStmt(this.value);
  final JsNode? value;
}

class BreakStmt extends JsStmt {
  const BreakStmt();
}

class ContinueStmt extends JsStmt {
  const ContinueStmt();
}

class ThrowStmt extends JsStmt {
  const ThrowStmt(this.value);
  final JsNode value;
}

class TryStmt extends JsStmt {
  const TryStmt(this.body, this.catchName, this.catchBody, this.finallyBody);
  final JsStmt body;
  final String? catchName;
  final JsStmt? catchBody;
  final JsStmt? finallyBody;
}

class EmptyStmt extends JsStmt {
  const EmptyStmt();
}

// ---------------- 解析器 ----------------

class JsParser {
  JsParser(this._tokens);

  factory JsParser.parse(String source) => JsParser(Lexer(source).tokenize());

  final List<Token> _tokens;
  int _pos = 0;

  Token get _cur => _tokens[_pos];

  bool get _atEnd => _cur.kind == TokKind.eof;

  bool _isPunct(String text) => _cur.kind == TokKind.punct && _cur.text == text;

  bool _isKeyword(String text) => _cur.kind == TokKind.keyword && _cur.text == text;

  Token _next() => _tokens[_pos++];

  bool _matchPunct(String text) {
    if (_isPunct(text)) {
      _pos++;
      return true;
    }
    return false;
  }

  bool _matchKeyword(String text) {
    if (_isKeyword(text)) {
      _pos++;
      return true;
    }
    return false;
  }

  void _expectPunct(String text) {
    if (!_matchPunct(text)) {
      throw JsSyntaxError('期望 "$text"，实际是 "${_cur.text}"', _cur.line, _cur.column);
    }
  }

  void _skipSemicolon() {
    _matchPunct(';');
  }

  /// 入口：解析整个程序。
  List<JsStmt> parseProgram() {
    final out = <JsStmt>[];
    while (!_atEnd) {
      out.add(_statement());
    }
    return out;
  }

  JsStmt _statement() {
    final token = _cur;
    if (_isPunct('{')) return _block();
    if (_isPunct(';')) {
      _pos++;
      return const EmptyStmt();
    }
    if (token.kind == TokKind.keyword) {
      switch (token.text) {
        case 'var':
        case 'let':
        case 'const':
          return _varDecl();
        case 'function':
          return _funcDecl();
        case 'if':
          return _if();
        case 'while':
          return _while();
        case 'do':
          return _doWhile();
        case 'for':
          return _for();
        case 'return':
          _pos++;
          final value = _isPunct(';') || _isPunct('}') || _atEnd ? null : _expression();
          _skipSemicolon();
          return ReturnStmt(value);
        case 'break':
          _pos++;
          _skipSemicolon();
          return const BreakStmt();
        case 'continue':
          _pos++;
          _skipSemicolon();
          return const ContinueStmt();
        case 'throw':
          _pos++;
          final value = _expression();
          _skipSemicolon();
          return ThrowStmt(value);
        case 'try':
          return _try();
        default:
          break;
      }
    }
    final expr = _expression();
    _skipSemicolon();
    return ExprStmt(expr);
  }

  JsStmt _block() {
    _expectPunct('{');
    final body = <JsStmt>[];
    while (!_atEnd && !_isPunct('}')) {
      body.add(_statement());
    }
    _expectPunct('}');
    return Block(body);
  }

  JsStmt _varDecl() {
    _pos++; // var / let / const
    final nameToken = _next();
    if (nameToken.kind != TokKind.ident) {
      throw JsSyntaxError('变量名缺失', nameToken.line, nameToken.column);
    }
    JsNode? init;
    if (_matchPunct('=')) {
      init = _assignment();
    }
    _skipSemicolon();
    return VarDecl(nameToken.text, init);
  }

  JsStmt _funcDecl() {
    _pos++; // function
    final nameToken = _next();
    if (nameToken.kind != TokKind.ident) {
      throw JsSyntaxError('函数名缺失', nameToken.line, nameToken.column);
    }
    final params = _params();
    final body = _block() as Block;
    return FuncDecl(nameToken.text, params, body.body);
  }

  List<String> _params() {
    _expectPunct('(');
    final params = <String>[];
    while (!_atEnd && !_isPunct(')')) {
      final token = _next();
      if (token.kind != TokKind.ident) {
        throw JsSyntaxError('参数名非法', token.line, token.column);
      }
      params.add(token.text);
      if (!_matchPunct(',')) break;
    }
    _expectPunct(')');
    return params;
  }

  JsStmt _if() {
    _pos++;
    _expectPunct('(');
    final test = _expression();
    _expectPunct(')');
    final consequent = _statement();
    JsStmt? alternate;
    if (_matchKeyword('else')) {
      alternate = _statement();
    }
    return IfStmt(test, consequent, alternate);
  }

  JsStmt _while() {
    _pos++;
    _expectPunct('(');
    final test = _expression();
    _expectPunct(')');
    return WhileStmt(test, _statement());
  }

  JsStmt _doWhile() {
    _pos++;
    final body = _statement();
    if (!_matchKeyword('while')) {
      throw JsSyntaxError('do 缺少 while', _cur.line, _cur.column);
    }
    _expectPunct('(');
    final test = _expression();
    _expectPunct(')');
    _skipSemicolon();
    return DoWhileStmt(body, test);
  }

  JsStmt _for() {
    _pos++;
    _expectPunct('(');
    // for (x in y) / for (x of y)，允许前面带 var/let/const
    var base = _pos;
    if (_isKeyword('var') || _isKeyword('let') || _isKeyword('const')) base = _pos + 1;
    if (base + 1 < _tokens.length &&
        _tokens[base].kind == TokKind.ident &&
        _tokens[base + 1].kind == TokKind.keyword &&
        (_tokens[base + 1].text == 'in' || _tokens[base + 1].text == 'of')) {
      _pos = base;
      final name = _next().text;
      final mode = _next().text;
      final iterable = _expression();
      _expectPunct(')');
      return ForInStmt(name, mode, iterable, _statement());
    }
    JsStmt? init;
    if (!_isPunct(';')) {
      if (_isKeyword('var') || _isKeyword('let') || _isKeyword('const')) {
        final saved = _pos;
        init = _varDeclNoSemicolon();
        if (init == null) _pos = saved;
      } else {
        init = ExprStmt(_expression());
        _matchPunct(';');
      }
    } else {
      _expectPunct(';');
    }
    JsNode? test;
    if (!_isPunct(';')) test = _expression();
    _expectPunct(';');
    JsNode? update;
    if (!_isPunct(')')) update = _expression();
    _expectPunct(')');
    return ForStmt(init, test, update, _statement());
  }

  JsStmt? _varDeclNoSemicolon() {
    final saved = _pos;
    _pos++; // var/let/const
    if (_cur.kind != TokKind.ident) {
      _pos = saved;
      return null;
    }
    final name = _next().text;
    JsNode? init;
    if (_matchPunct('=')) init = _assignment();
    _matchPunct(';');
    return VarDecl(name, init);
  }

  JsStmt _try() {
    _pos++;
    final body = _block();
    String? catchName;
    JsStmt? catchBody;
    JsStmt? finallyBody;
    if (_matchKeyword('catch')) {
      if (_matchPunct('(')) {
        catchName = _next().text;
        _expectPunct(')');
      }
      catchBody = _block();
    }
    if (_matchKeyword('finally')) {
      finallyBody = _block();
    }
    return TryStmt(body, catchName, catchBody, finallyBody);
  }

  // ---------------- 表达式优先级 ----------------

  JsNode _expression() {
    var expr = _assignment();
    while (_matchPunct(',')) {
      expr = _assignment();
    }
    return expr;
  }

  JsNode _assignment() {
    final left = _conditional();
    for (final op in const ['=', '+=', '-=', '*=', '/=']) {
      if (_isPunct(op)) {
        _pos++;
        final right = _assignment();
        return Assign(op, left, right);
      }
    }
    return left;
  }

  JsNode _conditional() {
    final test = _logicalOr();
    if (_matchPunct('?')) {
      final consequent = _assignment();
      _expectPunct(':');
      final alternate = _assignment();
      return Conditional(test, consequent, alternate);
    }
    return test;
  }

  JsNode _logicalOr() {
    var left = _logicalAnd();
    while (_isPunct('||')) {
      _pos++;
      left = Binary('||', left, _logicalAnd(), logical: true);
    }
    return left;
  }

  JsNode _logicalAnd() {
    var left = _equality();
    while (_isPunct('&&')) {
      _pos++;
      left = Binary('&&', left, _equality(), logical: true);
    }
    return left;
  }

  JsNode _equality() {
    var left = _relational();
    while (_isPunct('==') || _isPunct('!=') || _isPunct('===') || _isPunct('!==')) {
      final op = _next().text;
      left = Binary(op, left, _relational());
    }
    return left;
  }

  JsNode _relational() {
    var left = _additive();
    while (_isPunct('<') || _isPunct('>') || _isPunct('<=') || _isPunct('>=')) {
      final op = _next().text;
      left = Binary(op, left, _additive());
    }
    return left;
  }

  JsNode _additive() {
    var left = _multiplicative();
    while (_isPunct('+') || _isPunct('-')) {
      final op = _next().text;
      left = Binary(op, left, _multiplicative());
    }
    return left;
  }

  JsNode _multiplicative() {
    var left = _unary();
    while (_isPunct('*') || _isPunct('/') || _isPunct('%')) {
      final op = _next().text;
      left = Binary(op, left, _unary());
    }
    return left;
  }

  JsNode _unary() {
    if (_isPunct('!') || _isPunct('-') || _isPunct('+')) {
      final op = _next().text;
      return Unary(op, _unary());
    }
    if (_matchKeyword('typeof')) {
      return Unary('typeof', _unary());
    }
    if (_matchKeyword('new')) {
      final callee = _postfix();
      final args = <JsNode>[];
      if (callee is Call) {
        return NewExpr(callee.callee, callee.args);
      }
      return NewExpr(callee, args);
    }
    if (_isPunct('++') || _isPunct('--')) {
      final op = _next().text;
      return Update(op, _unary(), prefix: true);
    }
    return _postfix();
  }

  JsNode _postfix() {
    var expr = _primary();
    while (true) {
      if (_matchPunct('.')) {
        final nameToken = _next();
        if (nameToken.kind != TokKind.ident && nameToken.kind != TokKind.keyword) {
          throw JsSyntaxError('成员名非法', nameToken.line, nameToken.column);
        }
        expr = Member(expr, nameToken.text);
      } else if (_matchPunct('[')) {
        final index = _expression();
        _expectPunct(']');
        expr = Index(expr, index);
      } else if (_matchPunct('(')) {
        final args = <JsNode>[];
        while (!_atEnd && !_isPunct(')')) {
          args.add(_assignment());
          if (!_matchPunct(',')) break;
        }
        _expectPunct(')');
        expr = Call(expr, args);
      } else if (_isPunct('++') || _isPunct('--')) {
        final op = _next().text;
        expr = Update(op, expr, prefix: false);
      } else {
        break;
      }
    }
    return expr;
  }

  JsNode _primary() {
    final token = _cur;
    if (token.kind == TokKind.number) {
      _pos++;
      return NumLit(token.numberValue ?? 0);
    }
    if (token.kind == TokKind.string) {
      _pos++;
      return StrLit(token.text);
    }
    if (token.kind == TokKind.keyword) {
      switch (token.text) {
        case 'true':
          _pos++;
          return const BoolLit(true);
        case 'false':
          _pos++;
          return const BoolLit(false);
        case 'null':
          _pos++;
          return const NullLit();
        case 'undefined':
          _pos++;
          return const UndefinedLit();
        case 'function':
          _pos++;
          String? name;
          if (_cur.kind == TokKind.ident) name = _next().text;
          final params = _params();
          final body = _block() as Block;
          return FuncExpr(params, body.body, name: name);
        case 'this':
          _pos++;
          return const Ident('this');
        default:
          throw JsSyntaxError('不支持的关键字：${token.text}', token.line, token.column);
      }
    }
    if (token.kind == TokKind.ident) {
      _pos++;
      return Ident(token.text);
    }
    if (_isPunct('(')) {
      _pos++;
      final expr = _expression();
      _expectPunct(')');
      return expr;
    }
    if (_isPunct('[')) {
      _pos++;
      final items = <JsNode>[];
      while (!_atEnd && !_isPunct(']')) {
        items.add(_assignment());
        if (!_matchPunct(',')) break;
      }
      _expectPunct(']');
      return ArrayLit(items);
    }
    if (_isPunct('{')) {
      _pos++;
      final entries = <MapEntry<String, JsNode>>[];
      while (!_atEnd && !_isPunct('}')) {
        final keyToken = _next();
        final key = keyToken.text;
        if (_matchPunct(':')) {
          entries.add(MapEntry(key, _assignment()));
        } else {
          entries.add(MapEntry(key, Ident(key)));
        }
        if (!_matchPunct(',')) break;
      }
      _expectPunct('}');
      return ObjectLit(entries);
    }
    throw JsSyntaxError('无法解析的表达式："${token.text}"', token.line, token.column);
  }
}