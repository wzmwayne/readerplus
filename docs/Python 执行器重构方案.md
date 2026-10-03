# Python 执行器重构方案（进程隔离）

> 起因：现有 `serious_python` 是**进程内嵌 CPython**（`libdart_bridge.so` + FFI）。
> 解释器一旦 abort / 段错误，整个 App 进程一并消失，Dart 层零异常、零日志
> （本机实测：华为 HarmonyOS 4.2 设备上任何 Python 调用都在 20–100ms 内失败并闪退）。
> 结论：**要真正隔离，必须把执行器移出 App 进程**；这与会话期间发现的三处宿主缺陷
> （读结果过早、日志尾随关得过早、运行中删除沙盒/解释器 home）是相互独立的问题。

## 一、目标与硬约束

| 类别 | 内容 |
|---|---|
| 目标 | 脚本崩溃**不得**影响 App；真取消；真实时日志；结果可靠 |
| 交付约束（用户既定） | 不显示进度条；沙盒审计默认开启且脚本不可感知；日志单文件、永远追加、位置固定；不导出日志到下载目录 |
| 平台约束 | Android 10+ **禁止从应用数据目录 `execve`**（W^X）；可执行只允许来自 `nativeLibraryDir`（即 APK 内 `lib/<abi>/lib*.so`） |
| 观测约束 | 用户无电脑、无 adb ⇒ 一切诊断必须落在**应用内单文件日志**里 |

## 二、协议（与语言无关，保持不变）

现有的**文件契约是本次重构中最值钱的部分**，原样保留：

```
沙盒/
  params.json          宿主 → 脚本（含 task 与参数）
  input/**             宿主 → 脚本（输入文件）
  user_script.py       宿主 → 脚本（用户代码）
  output/result.json   脚本 → 宿主（search / detail 结构化结果）
  output/*.epub        脚本 → 宿主（产物）
  output/manifest.json 脚本 → 宿主（状态与产物清单；失败时含 traceback）
  output/log.txt       脚本 stdout/stderr（宿主边跑边读）
```

新增两条**进程级**信号（替代原先不可靠的"spawn 即返回"）：

1. **完成 = 子进程退出码**（0 成功）——不再靠轮询猜；
2. **实时日志 = 子进程 stdout/stderr 行流**——宿主逐行追加到唯一日志文件并推给界面。

## 三、架构：进程隔离（推荐方案）

### 3.1 Android：把执行器放进独立进程

- 用 `android:process=":plugin"` 起一个**独立进程**承载执行器（Flutter 侧用
  `FlutterEngineGroup` 在同一 App 内起第二个引擎；两个进程通过 `MethodChannel`
  仅交换「日志行 / 完成事件 / 取消指令」）。
- 该进程崩溃（abort、段错误、被 OOM 杀）⇒ **UI 进程存活**，界面显示
  “执行器已崩溃（信号 N）”，并可一键重启执行器、保留现场日志。
- 取消 = 结束该执行器进程（从内部自杀式退出，或由系统回收），**真取消**，不再有“假取消按钮”。

### 3.2 Linux 桌面：直接跑子进程（比 Android 更容易）

```dart
final process = await Process.start(
  pythonExecutable,            // 系统 python3 或随包分发者
  ['-I', appDir + '/main.py'], // -I：隔离模式，忽略环境与用户 site
  workingDirectory: jobDir,
  environment: {'SANDBOX_ROOT': jobDir, ...},
);
process.stdout.transform(utf8.decoder).transform(const LineSplitter())
  ..listen((line) => AppLog.info('plugin', line));
final exitCode = await process.exitCode;   // 真完成信号
process.kill(ProcessSignal.sigkill);       // 真取消
```

### 3.3 为什么不用「native launcher + jniLibs」做主线

可行（把 CPython 可执行文件或一个 C 启动器打成 `lib*.so` 放进 `jniLibs/`，再从
`nativeLibraryDir` exec，绕开数据目录禁 exec 的限制），但需要 NDK 构建与逐 ABI 打包，
成本高于 3.1，且会重新引入“发行包下载/解包”这一类脆弱环节。**保留为备选。**

## 四、关于「换语言」与「旧版本 Python / Python 2」

| 选项 | 评估 |
|---|---|
| **换类 JS（QuickJS）** | **能显著改善打包**（一个几百 KB 的 .so，dist/解包/.soref/PYTHONHOME 全部消失），且与上游 Legado 的书源脚本生态（JavaScript）对齐；**但不改善崩溃隔离**（仍是 FFI 进程内）。若切换，建议同时按第三节做进程隔离。 |
| **降级 Python 3.x** | 与本次故障无关。已核实最后一个可用构建与当前 `pubspec.lock` 中 `serious_python 5.0.0` / `serious_python_android 5.0.0` **逐字节相同**，锁版本等于现状，不是修复手段。 |
| **Python 2** | **不建议**：已 EOL 十余年、无安全更新、无 ABI 支持，且**同样处于进程内**（问题一点没解决），还要重写全部示例与文档。若目标是“能跑起来”，换 py2 与此无关；若目标是“小体积”，QuickJS 才是答案。 |

**结论：语言保持 Python（版本沿用发行包自带的 3.14.x），把力气花在进程隔离上。**

## 五、分阶段落地（每阶段都有可验证判据与回滚点）

### P0 现场保护（半天，独立于重构，可先做）
- 删除所有“在脚本可能仍在运行时删除沙盒 / 删除 `<support>/flet`”的代码路径；
- 结果读取改为「等启动信号（日志文件出现）→ 再等结果」，超时与未启动两种情况都调用取消；
- 判据：导入内置脚本后不再出现“运行中目录被删”的日志；`describe` 有明确成败结论。

### P1 Linux 进程隔离（1–2 天）
- 新增 `ProcessRuntime implements PluginRuntime`：`Process.start` + 行流日志 + `exitCode` 判定 + `kill` 取消；
- `PluginRunner` 增加运行时选择开关（默认走新实现，旧实现保留一格回退）；
- 判据：故意让脚本 `os.abort()` ⇒ App 存活、日志记录“子进程被信号 6 终止”；点取消 ⇒ `ps` 层面确认进程消失；
- 回滚：开关切回旧实现。

### P2 Android 独立进程（2–3 天）
- 第二个 `FlutterEngine`（`:plugin` 进程）+ `MethodChannel` 三件事（日志行、完成、取消）；
- 需要访问运行时的代码全部搬进该引擎入口，UI 只经 IPC 交互；
- 判据：① 脚本触发 abort 时 UI 不退出而显示“执行器已崩溃”；② 执行器被系统杀死后能自动重启；③ 日志仍写入同一个文件、只追加。

### P3 收敛与清理（1 天）
- 删除 `serious_python` 依赖与 `SeriousPythonRuntime`；删掉 `runtime_output.txt`、双位置 manifest fallback、心跳机制等临时产物；
- CI 移除 `flet-dist` 缓存与 dist 下载步骤（若仍用发行包，则改为「解包到 assets + 校验 sha256」）；
- 文档同步：`docs/插件开发指南.md` 中“可取消”“manifest 位置”等描述与新实现对齐。

## 六、风险与待验证假设

1. **`:plugin` 进程内的 Flutter 引擎能否稳定驱动现有 FFI 桥**（P2 的关键假设；若不行，退回 3.3 的 launcher 方案）。
2. **Android 上 exec 限制的实际边界**（是否需要 `nativeLibraryDir`；仅在必要时才引入 NDK）。
3. **IPC 日志吞吐**（脚本可能高频 print）⇒ 批量发送 + 单文件追加，避免每行一次 IPC。
4. 现有 `serious_python` 在 P3 之前仍可能崩 ⇒ P0/P1 期间界面须明确提示“执行器可能崩溃并重启”。
