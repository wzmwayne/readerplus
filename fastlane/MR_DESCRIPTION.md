# fdroiddata MR 描述（草稿）

> 用途：向 `gitlab.com/fdroid/fdroiddata` 提交 `metadata/wzmwayne.reader.yml` 时，
> 把下面 `---` 之间的内容作为 Merge Request 描述粘贴。

---

## New app: ReaderPlus (wzmwayne.reader)

ReaderPlus is a local-first reader for TXT and EPUB with fully offline
text-to-speech. One adaptive Flutter UI for Android and Linux desktop.

* **License**: GPL-3.0-or-later (`LICENSE` in the repo)
* **Source**: https://github.com/wzmwayne/readerplus (buildable; CI config included)
* **Flutter**: 3.47.0 (needs `srclibs: flutter@3.47.0`)
* **NDK / CMake**: the `jni` package compiles a small native shim, so the build
  needs NDK 28.2.13676358 and `cmake;3.22.1`.

### Permissions and network use

* Only `android.permission.INTERNET`.
* Used by (a) optional user-imported book-source scripts (off by default,
  behind a consent gate) and (b) the on-device TTS engine's loopback HTTP server.
* Cleartext traffic is restricted to `127.0.0.1` / `localhost` in
  `network_security_config.xml` — nothing else is allowed in the clear.

### No telemetry

No analytics, crash reporting, ads or tracking SDKs of any kind. The app log is
a local file only. Verified by searching the source tree for the usual SDK names.

### No bundled assets of third-party services

* **No voice models are bundled.** Read-aloud requires the user to import a model
  package (`zip` / `tar.bz2`) they obtained themselves; the app ships none.
* Example book-source scripts live outside the installed assets
  (`examples/plugins/`) and are not loaded automatically.

### About the native libraries

`sherpa_onnx` (Apache-2.0) ships its `.so` files through its per-ABI **pub
packages** (`sherpa_onnx_android_arm64`, `_armeabi`, `_x86`, `_x86_64`), which are
resolved by `flutter pub get` during the build. They are freely licensed
(Apache-2.0) but do not come from one of the trusted Maven repositories listed in
the inclusion policy. **If the reviewers prefer building from source**, I can add
a `prebuild` step that compiles sherpa-onnx against a prebuilt ONNX Runtime
(about 5 minutes), or compiles ONNX Runtime from source as well (1–3 hours).

No binary artifacts are committed to the repository (`git ls-files` contains no
`.so`, `.aar` or `.jar`).

### Anti-features

None expected. Earlier versions used Microsoft Edge TTS (which would have been
`NonFreeNet`); that code path was removed in 1.1.3, read-aloud is now fully
on-device.

### Screenshots

`fastlane/metadata/android/{en-US,zh-CN}/images/phoneScreenshots/` — the UI is
bilingual; screenshots currently show the Chinese UI.

### AI assistance disclosure

Parts of this application and its metadata were produced with AI assistance
(an AI coding agent was used for implementation, and for preparing this MR text
and the screenshots). All code is reviewed and released by the human maintainer,
who is the sole copyright holder and takes responsibility for the submission.

---

## 提交前待办（维护者自查，不进 MR）

- [ ] `pubspec.yaml` 升到 `1.1.4+N`，打 tag `v1.1.4`，把配方里的 `commit` 与
      `versionName` / `versionCode` 改成实际值（两者必须与 pubspec 一致，
      否则 F-Droid 会因版本码不匹配而失败）
- [ ] 确认 fdroiddata 里已有 `flutter@3.47.0` 这个 srclib；没有则需先提一个
      新增 srclib 的 MR
- [ ] 确认 `ndk: 28.2.13676358` 与 `cmake;3.22.1` 在该 Flutter/AGP 版本下可用
- [ ] `fastlane/metadata/android/en-US/images/phoneScreenshots/` 补英文界面截图
- [ ] 书架与阅读器截图：前者含受版权保护的封面/书名，后者需用 v1.1.4 重拍