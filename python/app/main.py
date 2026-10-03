"""阅读（readerplus）脚本运行时入口。

宿主层（Dart）负责：创建沙盒目录、把输入放进 input/、写 params.json、
把用户脚本放到沙盒根目录的 user_script.py，然后带 SANDBOX_ROOT 环境变量
运行本文件。

本文件的职责（与方案一致）：
  1. 读 SANDBOX_ROOT，切换工作目录到沙盒根；
  2. 把沙盒根加入 sys.path；
  3. 把 stdout/stderr 同时写入 output/log.txt（宿主边跑边读，用于前台显示日志）；
  4. 执行 user_script.py；
  5. 把结果写入 output/manifest.json（沙盒根目录不做输出）。
"""

import ast
import json
import os
import sys
import traceback

MANIFEST_OK = "ok"
MANIFEST_ERROR = "error"


class _Tee:
    """同时写到原 stdout/stderr 与日志文件的输出流。"""

    def __init__(self, original, log_file):
        self._original = original
        self._log = log_file

    def write(self, data):
        self._original.write(data)
        self._log.write(data)
        self._log.flush()
        return len(data)

    def flush(self):
        self._original.flush()
        self._log.flush()


def _load_params(sandbox_root):
    path = os.path.join(sandbox_root, "params.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _app_dir():
    """入口脚本所在目录。

    注意：以 `.pyc` 方式运行时（移动端就是这样）Python 不会定义 `__file__`，
    因此这里按 sys.argv[0] → sys.path[0] → 当前目录依次回退。
    """
    candidates = []
    if sys.argv and sys.argv[0]:
        candidates.append(sys.argv[0])
    if sys.path and sys.path[0]:
        candidates.append(sys.path[0])
    candidates.append(os.getcwd())
    for candidate in candidates:
        try:
            directory = os.path.dirname(os.path.abspath(candidate))
            if directory and os.path.isdir(directory):
                return directory
        except Exception:  # noqa: BLE001 - 任何异常都退回下一个候选
            continue
    return os.getcwd()


def _install_audit_hook(sandbox_root):
    """可选审计钩子：阻止脚本读写沙盒外的路径（网络不受影响）。"""
    root = os.path.realpath(sandbox_root)
    # 可信的运行时目录：解释器自身、应用目录（内置库所在处）、启动时的 sys.path 项
    trusted = {
        os.path.realpath(entry)
        for entry in sys.path
        if entry and os.path.isabs(entry) and os.path.isdir(entry)
    }
    trusted.add(os.path.realpath(_app_dir()))
    trusted.add(os.path.realpath(os.getcwd()))

    def _resolve(path):
        try:
            return os.path.realpath(path)
        except Exception:  # noqa: BLE001 - 路径解析失败时按越界处理
            return None

    def _inside(path):
        if not isinstance(path, (str, bytes, os.PathLike)):
            return True
        if isinstance(path, bytes):
            path = path.decode("utf-8", "ignore")
        resolved = _resolve(path)
        if resolved is None:
            return True
        # 允许解释器自身的库路径（否则 Python 无法导入标准库）
        for prefix in (sys.prefix, sys.base_prefix):
            if prefix and resolved.startswith(os.path.realpath(prefix)):
                return True
        # 允许内置库与运行时目录（插件需要 import readerplus_epub / requests 等）
        for prefix in trusted:
            if resolved == prefix or resolved.startswith(prefix + os.sep):
                return True
        return resolved == root or resolved.startswith(root + os.sep)

    def _hook(event, args):
        if event == "open":
            path = args[0]
            if not _inside(path):
                raise PermissionError(f"脚本不允许访问沙盒外的路径：{path}")
        elif event in ("os.remove", "os.rename", "os.rmdir", "os.mkdir"):
            for value in args[:2]:
                if not _inside(value):
                    raise PermissionError(f"脚本不允许修改沙盒外的路径：{value}")

    sys.addaudithook(_hook)


def _read_declaration(source):
    """从脚本源码里静态取出 SCRIPT / PLUGIN 声明（只接受字面量，不执行代码）。"""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id in ("SCRIPT", "PLUGIN"):
                try:
                    return ast.literal_eval(node.value)
                except (ValueError, SyntaxError):
                    return None
    return None


def _write_manifest(sandbox_root, payload):
    """结果统一写在 output/ 下：脚本与宿主都不再往沙盒根目录写输出。"""
    output_dir = os.path.join(sandbox_root, "output")
    os.makedirs(output_dir, exist_ok=True)
    path = os.path.join(output_dir, "manifest.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)


def _resolve_sandbox_root():
    """取本次运行的沙盒目录。

    优先环境变量；个别平台不会把环境变量传给 Python 进程，此时退回到
    宿主写在当前目录（或其 data/ 子目录）里的任务指针文件。
    """
    root = os.environ.pop("SANDBOX_ROOT", "")
    if root:
        return root
    for candidate in ("readerplus_job.txt", os.path.join("data", "readerplus_job.txt")):
        try:
            with open(candidate, encoding="utf-8") as handle:
                value = handle.read().strip()
            if value:
                print(f"[host] 任务指针：{candidate}")
                return value
        except OSError:
            continue
    return ""


def main():
    sandbox_root = _resolve_sandbox_root()
    if not sandbox_root:
        print("缺少运行目录（既没有环境变量也没有任务指针文件）", file=sys.stderr)
        return 2

    os.makedirs(sandbox_root, exist_ok=True)
    os.chdir(sandbox_root)

    # 结果与日志都在 output/ 下：沙盒根目录不再作为输出位置

    os.makedirs("output", exist_ok=True)

    log_file = open(os.path.join("output", "log.txt"), "a", encoding="utf-8", buffering=1)
    sys.stdout = _Tee(sys.stdout, log_file)
    sys.stderr = _Tee(sys.stderr, log_file)

    params = _load_params(sandbox_root)
    print(f"[host] 任务：{params.get('task', 'unknown')}")

    # 审计开关仅由宿主通过环境变量传入，且在安装后立刻从环境中清除：
    # 脚本无法通过参数或环境变量得知是否开启，避免恶意脚本据此隐藏行为。
    audit_flag = os.environ.pop("READERPLUS_SANDBOX_AUDIT", "")
    if audit_flag == "1":
        try:
            _install_audit_hook(sandbox_root)
        except Exception as error:  # noqa: BLE001 - 审计不可用时仍要让脚本跑完
            print(f"[host] 审计钩子安装失败（继续运行）：{error}", file=sys.stderr)

    if sandbox_root not in sys.path:
        sys.path.insert(0, sandbox_root)

    script_path = os.path.join(sandbox_root, "user_script.py")
    if not os.path.exists(script_path):
        _write_manifest(sandbox_root, {"status": MANIFEST_ERROR, "traceback": "缺少 user_script.py"})
        return 1

    task = str(params.get("task", ""))
    try:
        with open(script_path, encoding="utf-8") as handle:
            source = handle.read()

        if task == "describe":
            # 静态解析脚本内的 SCRIPT 声明：不执行任何用户代码
            declaration = _read_declaration(source)
            if declaration is None:
                raise ValueError("脚本缺少 SCRIPT 声明（见插件开发指南）")
            if not isinstance(declaration, dict):
                raise ValueError("SCRIPT 声明必须是字典")
            print(f"[host] 脚本声明：{json.dumps(declaration, ensure_ascii=False)}")
            _write_manifest(
                sandbox_root,
                {"status": MANIFEST_OK, "script": declaration},
            )
            return 0

        namespace = {"__name__": "__main__", "__file__": script_path}
        exec(compile(source, script_path, "exec"), namespace)
    except SystemExit as exit_error:  # 允许脚本用 sys.exit 提前结束
        if exit_error.code not in (None, 0):
            _write_manifest(
                sandbox_root,
                {"status": MANIFEST_ERROR, "traceback": f"脚本以退出码 {exit_error.code} 结束"},
            )
            return 1
    except BaseException:  # noqa: BLE001 - 任何异常都要落盘，宿主据此报错
        detail = traceback.format_exc()
        print(detail, file=sys.stderr)
        _write_manifest(sandbox_root, {"status": MANIFEST_ERROR, "traceback": detail})
        return 1

    outputs = []
    output_dir = os.path.join(sandbox_root, "output")
    if os.path.isdir(output_dir):
        outputs = sorted(os.listdir(output_dir))
    print(f"[host] 输出文件：{outputs}")
    _write_manifest(sandbox_root, {"status": MANIFEST_OK, "outputs": outputs})
    return 0


if __name__ == "__main__":
    sys.exit(main())
