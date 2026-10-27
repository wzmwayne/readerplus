// @script kind=clean name="TXT 清洗示例（转 EZBK）"
// 输入：任意文本文件；输出：EZBK 文本（# 标题 + 段落 + 单独一行 --- 分页）。
var task = JSON.parse(tmp.read.utf8('task'));
var name = (task.inputs && task.inputs.length > 0) ? task.inputs[0].name : 'input.txt';
var raw = tmp.read.raw('input/' + name);
var text = decode(raw, 'auto');

// 统一换行，去掉行尾空白与零宽字符
text = text.replace('\r\n', '\n');
text = text.replace('\r', '\n');

var lines = text.split('\n');
var out = ['# ' + name, ''];
for (var i = 0; i < lines.length; i++) {
  var line = lines[i].trim();
  if (line === '') continue;
  // 类似章节标题的行：短、且不含句号
  if (line.length <= 30 && line.indexOf('。') < 0 && line.indexOf('章') >= 0) {
    out.push('');
    out.push('# ' + line);
    out.push('');
  } else {
    out.push(line);
  }
}
result(out.join('\n'));