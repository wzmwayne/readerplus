// @script kind=source name="本地测试书源（假数据）"
// 说明：kind=source ⇒ 只出现在「书源」页；任务由 task.task 区分：search / download
// 契约：搜索一次带回全部字段（含封面），没有独立的“取详情”任务。
var task = JSON.parse(tmp.read.utf8('task'));
var params = task.params || {};

var books = [
  {
    id: '1',
    title: '夜航船（测试书）',
    author: '张岱（测试）',
    intro: '本地假数据',
    description: '本地假数据，用于流程测试：搜索即含详情，点击直接展示。',
    cover: '',
  },
  {
    id: '2',
    title: '山中客（测试书）',
    author: '佚名',
    intro: '本地假数据',
    description: '第二条假数据，用于验证分组与封面占位。',
    cover: '',
  },
  {
    id: '3',
    title: '旧信笺（测试书）',
    author: '测试作者',
    intro: '无封面示例',
    description: '无封面示例：界面应显示占位封面而不是空白。',
    cover: '',
  },
];

var mode = task.task || params.task || 'search';

if (mode === 'search') {
  var query = params.query || '';
  if (query === 'fail') {
    throw '测试用的搜索失败（关键词 fail）';
  }
  var items = [];
  for (var i = 0; i < books.length; i++) {
    var book = books[i];
    if (query === '' || book.title.indexOf(query) >= 0) {
      items.push(book);
    }
  }
  log('命中 ' + items.length + ' 条（每条都带详情与封面字段）');
  result({ items: items });
} else {
  result({
    id: params.id || '1',
    chapters: [{ title: '第一章', body: '假数据正文。' }],
  });
}