// @script kind=source name="古腾堡（公共领域示例）"
// 抓取 Project Gutenberg 的公开接口 Gutendex；不含任何受版权保护的内容。
var task = JSON.parse(tmp.read.utf8('task'));
var params = task.params || {};
var mode = task.task || params.task || 'search';

if (mode === 'search') {
  var q = params.query || '';
  var url = 'https://gutendex.com/books?search=' + encodeURIComponent(q);
  var resp = http.get(url);
  if (resp.status !== 200) {
    throw '古腾堡接口返回 ' + resp.status;
  }
  var data = JSON.parse(resp.text);
  var items = [];
  var list = data.results || [];
  for (var i = 0; i < list.length; i++) {
    var b = list[i];
    var author = (b.authors && b.authors.length > 0) ? b.authors[0].name : '佚名';
    items.push({
      id: String(b.id),
      title: b.title,
      author: author,
      intro: '',
      description: (b.subjects || []).join(' / '),
      cover: '',
    });
  }
  log('命中 ' + items.length + ' 条');
  result({ items: items });
} else {
  var id = params.id || '1';
  var resp2 = http.get('https://gutendex.com/books/' + id);
  if (resp2.status !== 200) {
    throw '取书本信息失败：' + resp2.status;
  }
  var book = JSON.parse(resp2.text);
  var formats = book.formats || {};
  var txtUrl = formats['text/plain; charset=utf-8'] || formats['text/plain; charset=us-ascii'] || '';
  if (txtUrl === '') {
    throw '该书没有纯文本版本';
  }
  var text = http.get(txtUrl);
  if (text.status !== 200) {
    throw '下载正文失败：' + text.status;
  }
  result({ id: String(id), chapters: [{ title: book.title, body: text.text }] });
}