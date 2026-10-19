import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/script_quiz.dart';

/// 题库里不允许出现的绝对化措辞：命中一条就要改写那句话（保持"半对结构"）。
const _bannedWords = <String>[
  '绝对',
  '所有',
  '任何',
  '永远',
  '完全',
  '一定',
  '从不',
  '绝不',
  '无法',
  '只能',
  '唯一',
  '必然',
];

void main() {
  test('题库：20 条正确 + 50 条错误 = 70 条，且无绝对化措辞', () {
    expect(kScriptQuizCorrect.length, 20);
    expect(kScriptQuizWrong.length, 50);
    expect(kScriptQuizBank.length, 70);
    expect(kScriptQuizBank.where((e) => e.isCorrect).length, 20);
    expect(kScriptQuizBank.where((e) => !e.isCorrect).length, 50);

    // 原文互不重复（否则同一道题里会出现两条一模一样的选项）
    final texts = kScriptQuizBank.map((e) => e.text).toList();
    expect(texts.toSet().length, texts.length);

    for (final item in kScriptQuizBank) {
      for (final word in _bannedWords) {
        expect(
          item.text.contains(word),
          isFalse,
          reason: '出现禁用词「$word」：${item.text}',
        );
      }
    }
  });

  test('抽题：5 条互不重复，且正确项与错误项各至少 1 条', () {
    for (var seed = 0; seed < 200; seed++) {
      final question = drawScriptQuiz(Random(seed));
      expect(question.options.length, kScriptQuizOptionCount);
      expect(
        question.options.map((e) => e.text).toSet().length,
        kScriptQuizOptionCount,
        reason: 'seed=$seed 出现重复选项',
      );
      expect(question.options.where((e) => e.isCorrect), isNotEmpty);
      expect(question.options.where((e) => !e.isCorrect), isNotEmpty);
      // 1 条保底正确 + 3 条来自剩余 68 条，因此正确项最多 4 条
      expect(question.correctIndices.length, inInclusiveRange(1, 4));
    }
  });

  test('抽题不因正确项多于 1 而重抽（2~4 条正确项都允许）', () {
    var sawMoreThanOneCorrect = false;
    for (var seed = 0; seed < 200; seed++) {
      if (drawScriptQuiz(Random(seed)).correctIndices.length > 1) {
        sawMoreThanOneCorrect = true;
        break;
      }
    }
    expect(sawMoreThanOneCorrect, isTrue, reason: '从未抽到 2 条以上正确项 = 被意外重抽了');
  });

  test('判定：选中集合与正确集合恰好相同才通过（漏选 / 多选都不通过）', () {
    // 找一道含 2 条以上正确项的题，才能同时验证漏选与多选
    ScriptQuizQuestion? question;
    for (var seed = 0; seed < 200; seed++) {
      final candidate = drawScriptQuiz(Random(seed));
      if (candidate.correctIndices.length >= 2) {
        question = candidate;
        break;
      }
    }
    expect(question, isNotNull, reason: '没找到含多条正确项的题');

    final quiz = question!;
    final correct = quiz.correctIndices;
    final wrongIndices = <int>[
      for (var i = 0; i < quiz.options.length; i++)
        if (!quiz.options[i].isCorrect) i,
    ];

    // 恰好选中全部正确项 ⇒ 通过
    expect(quiz.isAnswerCorrect(correct), isTrue);

    // 漏选一条正确项 ⇒ 不通过
    expect(
      quiz.isAnswerCorrect(correct.difference({correct.first})),
      isFalse,
    );

    // 多勾一条错误项 ⇒ 不通过
    expect(quiz.isAnswerCorrect({...correct, wrongIndices.first}), isFalse);

    // 只勾错误项 / 空选 ⇒ 不通过
    expect(quiz.isAnswerCorrect({wrongIndices.first}), isFalse);
    expect(quiz.isAnswerCorrect(<int>{}), isFalse);
  });
}
