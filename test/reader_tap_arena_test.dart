import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归测试：本仓库踩过的真实坑 ——
/// `SelectionArea`（内部是 SelectableRegion）自带 tap 识别器，且它比"外层"更深；
/// Flutter 手势竞技场在 sweep 时**首个成员胜出**，因此**外层 GestureDetector
/// 的 onTapUp 永远收不到点击**（表现为"点屏幕中部毫无反应，日志也没有"）。
///
/// 修法：把点击/双击识别器放到 SelectionArea **内层**。
void main() {
  testWidgets('外层 onTapUp 会被 SelectionArea 抢走（说明为什么必须放内层）', (tester) async {
    var outerFired = 0;
    var innerFired = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (_) => outerFired++,
            child: SelectionArea(
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (_) => innerFired++,
                  child: const SizedBox(
                    width: 200,
                    height: 200,
                    child: Text('正文内容'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('正文内容'));
    await tester.pumpAndSettle();

    expect(innerFired, 1, reason: '内层识别器应收到点击');
    expect(
      outerFired,
      0,
      reason: '外层被 SelectableRegion 抢先（这正是"点中部没反应且无日志"的机制）',
    );
  });

  testWidgets('双击识别器放内层也照样工作（单击仍会触发）', (tester) async {
    var singles = 0;
    var doubles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (_) => singles++,
                onDoubleTapDown: (_) => doubles++,
                child: const SizedBox(
                  width: 200,
                  height: 200,
                  child: Text('正文内容'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('正文内容'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(singles, 1, reason: '单击应在双击超时后触发一次');
    expect(doubles, 0);

    await tester.tap(find.text('正文内容'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('正文内容'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(doubles, 1, reason: '第二次按下应触发 onDoubleTapDown');
  });
}
