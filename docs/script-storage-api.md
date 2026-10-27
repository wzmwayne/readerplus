# 脚本存储 API 规范（三级 · 点分命名）

> 适用：ReaderPlus 脚本引擎｜版本：v2｜替代：v1 的 12 个扁平函数

## 0. 设计：用点分命名收敛入口

三级存储各自是一个**命名空间对象**，方法用点号访问：

```js
tmp.read.raw(k)      tmp.read.utf8(k)
tmp.write.raw(k, b)  tmp.write.utf8(k, s)
tmp.remove(k)        tmp.keys()        tmp.clear()
```

于是入口从「12 个全局函数」收敛为 **3 个对象 × 7 个方法**，
且三级存储的用法**完全同构** —— 只需记住一套方法名：

| 对象 | 后端 | 生命周期 | 配额（每脚本） |
|---|---|---|---|
| `mem` | 内存 Map | 本次运行，结束释放 | 50 MB |
| `tmp` | 磁盘 `tmp/<scriptId>/` | 本次运行，结束清除 | 100 MB |
| `perm` | 磁盘 `perm/<scriptId>/` | 永久，用户可查看/编辑/清除 | 50 MB |

## 1. 方法表（每个命名空间同一套，共 7 个）

| 方法 | 入参 | 返回 | 说明 |
|---|---|---|---|
| `read.raw(k)` | 键 | 字节数组 \| `null` | 原始字节 |
| `read.utf8(k)` | 键 | 字符串 \| `null` | 按 UTF-8 解码 |
| `write.raw(k, bytes)` | 键、字节 | 写入字节数 | 只接受字节；传字符串报错 |
| `write.utf8(k, text)` | 键、字符串 | 写入字节数 | 只接受字符串；传字节报错 |
| `remove(k)` | 键 | `true` / `false` | 是否存在并删除 |
| `keys()` | — | 字符串数组 | 键列表（保留键不返回） |
| `clear()` | — | `true` | 清空本层 |

约定：

1. 键恒为 UTF-8 文本；值恒按**字节**存储，`utf8` 只是编解码封装；
2. `read.utf8` 遇到非法 UTF-8 → 用 `U+FFFD` 替换（不抛错）；
3. 写入 `tmp` / `perm` 立即落盘（`写 .tmp → rename` 原子替换）；
4. 超配额抛错（见 §4），不静默截断。

## 2. 任务信息：脚本从 `tmp` 主动读

宿主不再注入 `param()`；每次运行开始时写入保留键：

```js
var task = JSON.parse(tmp.read.utf8('task'));
// task.kind     'source' | 'clean' | 'tool'
// task.task     'search' | 'download' | 'import' …
// task.params   { 键: 字符串 }
// task.inputs   [{ name, size }]

var bin = tmp.read.raw('input/' + task.inputs[0].name);   // 输入二进制
```

保留键（脚本写入即报错）：`task`、`input/*`。

## 3. 三个典型用法

```js
// ① 跨运行状态（cookie、游标）：perm
var cursor = perm.read.utf8('cursor') || '1';
perm.write.utf8('cursor', String(Number(cursor) + 1));

// ② 本次运行的大块中间数据：tmp（退出即清）
tmp.write.raw('page-2.html', resp.bytes);
var html = tmp.read.utf8('page-2.html');

// ③ 高频小缓存：mem（最快，不落盘）
if (!mem.read.utf8('toc')) mem.write.utf8('toc', JSON.stringify(toc));
```

## 4. 配额与错误

| 场景 | 行为 |
|---|---|
| `mem` 累计 > 50 MB | `mem.write: 超出配额（50 MB）` |
| `tmp` 累计 > 100 MB | `tmp.write: 超出配额（100 MB）` |
| `perm` 累计 > 50 MB | `perm.write: 超出配额（50 MB）` |
| 键为空 / > 256 字符 | 抛错 |
| 写保留键 | 抛错 |
| `read` 不存在的键 | 返回 `null`（不抛错） |

内存配额为**计量式**约束（Dart 无法硬限 isolate 堆）。

## 5. 生命周期与清理

| 时机 | `mem` | `tmp` | `perm` |
|---|---|---|---|
| 正常结束 | 释放 | 删除目录 | 保留 |
| 异常 / 超时被杀 | 释放 | 可能残留 | 保留 |
| 应用启动 | 空 | **清扫残留** | 保留 |
| 用户手动 | — | — | 查看 / 编辑 / 清除 |

## 6. 永久存储的查看与编辑（UI）

1. 列表：键、字节数、更新时间；
2. 打开某个键：
   - **先尝试 UTF-8 解码** → 成功则纯文本显示并**可编辑保存**（保存走 `perm.write.utf8`）；
   - **解码失败 → 显示 `(raw)`**，只提供只读十六进制预览（避免误改二进制）；
3. 支持单键删除与整脚本清空。

## 7. 落盘格式

```
<appSupport>/reader/scripts/
  perm/<scriptId>/index.json      # { "键": {"file":"a1b2","size":123,"updatedAt":"…"} }
  perm/<scriptId>/a1b2            # 值的原始字节（文件名 = sha1(键) 前 16 位）
  tmp/<scriptId>/…                # 结构同上，运行结束删除
```

- 文件名用 `sha1(键)`，不复用键名 → 天然规避路径穿越与非法字符；
- 索引与值文件均 `写 .tmp → rename`；
- 同一脚本的写入串行化（索引为单文件）。

## 8. 与 v1（12 扁平函数）的对应

| v1 | v2 |
|---|---|
| `memPutRaw(k,b)` | `mem.write.raw(k,b)` |
| `memPutUtf8(k,s)` | `mem.write.utf8(k,s)` |
| `memGetRaw(k)` | `mem.read.raw(k)` |
| `memGetUtf8(k)` | `mem.read.utf8(k)` |
| （无） | `mem.remove / keys / clear` |
| `param(name)` | `JSON.parse(tmp.read.utf8('task')).params[name]` |

`tmp` / `perm` 同理。