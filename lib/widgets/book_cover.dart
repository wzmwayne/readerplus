import 'package:flutter/material.dart';

import '../models/book.dart';

/// 无封面时按书名生成的渐变封面，风格贴近原版的纯色字面封面。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 96,
    this.height = 128,
    this.borderRadius = 6,
  });

  final Book book;
  final double width;
  final double height;
  final double borderRadius;

  static const _palette = [
    [Color(0xFF795548), Color(0xFF5D4037)],
    [Color(0xFF03A9F4), Color(0xFF0277BD)],
    [Color(0xFF8BC34A), Color(0xFF558B2F)],
    [Color(0xFFE57373), Color(0xFFC62828)],
    [Color(0xFF9575CD), Color(0xFF512DA8)],
    [Color(0xFF4DB6AC), Color(0xFF00695C)],
    [Color(0xFFFFB74D), Color(0xFFEF6C00)],
    [Color(0xFF90A4AE), Color(0xFF455A64)],
  ];

  List<Color> get _colors {
    if (book.title.isEmpty) return _palette.first;
    final hash = book.title.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              book.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: width * 0.16,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (book.author.isNotEmpty)
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: width * 0.11),
            ),
        ],
      ),
    );
  }
}
