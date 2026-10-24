/// 阅读进度的编码规则（纯函数，便于单测）。
///
/// Book.lastOffset 在不同阅读模式下语义不同：
///   - 翻页模式：章内**字符偏移**（>= 0）
///   - 滚动模式：章内**段落序号**（编码为负数，见 [encodeScrollPosition]）
///
/// 用符号区分是因为字符偏移可能是几千，若被滚动模式误当成段落号，
/// 会被夹到章末，表现为"重进书跳到章尾"。
library;

/// 滚动模式：把段落序号编码进 lastOffset。
int encodeScrollPosition(int paragraphIndex) => -(paragraphIndex + 1);

/// 滚动模式：从 lastOffset 解出段落序号；非负数说明不是滚动模式写的。
int? decodeScrollPosition(int raw) => raw < 0 ? -raw - 1 : null;
