/// 覆盖模式（cover）的位移计算。
///
/// 与滑动模式的区别：
///   - 覆盖：当前页保持不动，下一页从右侧盖上来；回翻时上一页留在原位，
///     当前页向右移出，把上一页露出来（只有一页在动）
///   - 滑动：相邻两页一起平移（整屏像传送带）
///
/// 抽成纯函数便于单测，避免两种模式再次出现「看起来一样」的回归。
library;

/// 上一页位移（始终在原位，作为被覆盖的底页）。
double coverPrevOffset(double drag) => 0;

/// 当前页位移：向右拖动（回翻）时跟着手指右移；向左拖动时不动（被下一页面覆盖）。
double coverCurrentOffset(double drag) => drag > 0 ? drag : 0;

/// 下一页位移：从右侧 [width] 处向左进入，拖动到 -width 时正好贴合。
double coverNextOffset(double drag, double width) => width + drag;
