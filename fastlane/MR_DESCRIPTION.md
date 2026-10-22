<!--For updates or other types of MRs replace the text below-->

## Abstract for new app inclusion

### Please introduce the functions and usage of your app in summary, and also attach some screenshots.

**ReaderPlus** (`wzmwayne.reader`) is a local-first reader for TXT (UTF-8 / GBK)
and EPUB 2 / 3 on **Android and Linux desktop**, sharing one adaptive Flutter UI.

What it does:

* **Shelf** – import local TXT or EPUB files, grid or list layout, reading
  progress and per-chapter read markers.
* **Reader** – themes, typography presets, header/footer with reading progress,
  tap/scroll page-turn modes, landscape two-column layout, per-chapter TOC with
  read/unread marking.
* **Read aloud, fully offline** – nothing is synthesised in the cloud. **No voice
  models are bundled**: the user imports a model package (`zip` / `tar.bz2`) that
  is validated and unpacked into the app's private directory. Synthesis runs in a
  long-lived background isolate with three-sentence lookahead, and the engine is
  released after 60 s idle so it does not hold ~65 MB resident.
* **Book-source scripts (optional, off by default)** – user-imported `.ht`
  scripts / `.json` rules run in a killable isolate with a sandboxed file API.
  The app ships **zero** sources, and the capability stays disabled until the
  user reads the disclaimer and passes a short understanding check.

Screenshots live in the upstream repo under
`fastlane/metadata/android/{en-US,zh-CN}/images/phoneScreenshots/`.

### Please elaborate why you wrote this app. Please highlight the unique functions it provides over other similar apps in F-Droid.

I wanted a reader that keeps the whole reading flow local: nothing about my
library, my progress or my reading voice ever leaves the device.

Compared with similar apps already in F-Droid:

* **Offline text-to-speech with user-supplied models.** Most F-Droid readers ship
  no TTS at all, and the ones that do depend on a network service. Here the engine
  (`sherpa_onnx`, Apache-2.0) runs on-device and the voice is a file the user
  brings — the app itself contains no audio assets and no non-free components.
* **Scriptable book sources behind an explicit consent gate.** The app is fully
  usable with zero scripts; the extension mechanism is closed until the user
  acknowledges the disclaimer and answers a short quiz about what scripts can do.
* **One code base for Android and Linux desktop** with a single adaptive layout.
* **No telemetry of any kind** — no analytics, crash reporting or ad SDKs; the log
  is a local file the user can open from the app.

## Checklist

### Policy

* [x] The app complies with the [inclusion criteria](https://f-droid.org/docs/Inclusion_Policy).
* [x] The original app author has been notified (and does not oppose the inclusion). If you are not the author, please paste the link of the reply from the author.
      <!-- I am the author (wzmwayne). -->
* [x] The upstream app source code repo contains the app metadata in a [Fastlane](https://gitlab.com/snippets/1895688) or [Triple-T](https://gitlab.com/snippets/1901490) folder structure. The summary and description must be included and images, icon, and changelog should also be provided for better user experience. The `en-US` locale must be included.
      <!-- fastlane/metadata/android/{en-US,zh-CN}/: title, short_description, full_description, changelogs/<versionCode>.txt, images/icon.png, images/phoneScreenshots/* -->

### Docs

* [x] Please read [the guide](https://gitlab.com/fdroid/fdroiddata/-/blob/master/CONTRIBUTING.md) first if this is your first contribution.
* [x] Please make sure your metadata follows the best practice in [our templates](https://gitlab.com/fdroid/fdroiddata/tree/master/templates).
* [x] Please read the [Build Metadata Reference](https://f-droid.org/docs/Build_Metadata_Reference/) and make sure your metadata is valid.
* [x] Please read the [Quick Start Guide](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/).

### Merge Request Setup

* [x] The title of this merge request should follow "New app: app name" format.
* [x] Please make sure your fdroiddata fork is public and your branch is not protected.
* [x] Please read [our Git guide](https://gitlab.com/fdroid/wiki/-/wikis/Tips-for-fdroiddata-contributors/Git-Usage) if you don't know how to rebase your branch. Don't rebase your branch if there is no conflict.
* [ ] All related [fdroiddata](https://gitlab.com/fdroid/fdroiddata/issues) and [RFP issues](https://gitlab.com/fdroid/rfp/issues) have been referenced in this merge request
      <!-- There is no RFP issue for this app; nothing to reference. -->
* [x] Please only submit one app in one MR.

### Metadata

* [x] Metadata must be put in `metadata/<applicationId>.yml`.
* [x] Metadata must be a valid YAML file.
* [x] Metadata must use LF as line ending.
* [x] Don't add summary/description/changelog/images or anything that should be provided in upstream repo. Please check the Changes tab to make sure there is no other unrelated files added in the MR.
* [x] Releases are tagged and auto update is enabled unless there is a special reason.
      <!-- Tags vX.Y.Z + AutoUpdateMode: Version / UpdateCheckMode: Tags -->
* [x] There is an issue tracker and contact info of the author so that we can report bugs and contact the author.
* [x] An AuthorName must be added. It doesn't need to be the real name.
* [ ] External repos are added as git submodules instead of srclibs. You can update git submodules without opening an MR in this repo and the submodule is covered by our scanner.
      <!-- The Flutter SDK is referenced as `srclibs: flutter@3.47.0`, following existing
           Flutter recipes in fdroiddata (e.g. chat.fluffy.fluffychat). No other external repos. -->
* [ ] Enable [Reproducible Builds](https://f-droid.org/docs/Reproducible_Builds). We'll use your signature for improved security/reliability, also allowing users to switch between different channels. Do note that if you don't enable reproducible build then the apk will be signed with our key so you can't enable it later. If you can't enable this, please add the reasons here.
      <!-- Not enabled yet. The APK embeds a Dart AOT snapshot and Flutter's engine,
           so reproducing it byte-for-byte needs a pinned toolchain digest and
           deterministic build paths; I have not verified that yet and would rather
           not claim it than have it silently fail. I understand the APK will then be
           signed with your key. I am happy to work on this as a follow-up if the
           recipe is accepted. -->
* [ ] Setup abi split if the APK is large and the splitted ones can be much smaller.
      <!-- A single APK carries arm64-v8a + armeabi-v7a (~90 MB) because the TTS engine
           brings ~26 MB of native libraries per ABI. The Gradle setup accepts
           `-Pabi=arm64|multi|all` to build one ABI per APK (arm64-only is ~49 MB);
           if preferred I can switch the recipe to emit per-ABI APKs. -->
* [x] Only the latest versions should be kept in the metadata before it's merged. If you update the metadata, please replace the old versions with the new ones.
* [x] Don't add any disabled versions in the metadata.
* [x] The `commit` field should be the full hash. Please don't use tag or branch in commit.

### Pipeline

* [ ] All pipelines should pass.
      <!-- Will be run once this MR is opened; I will fix anything it reports. -->
* [ ] All warnings and errors in the Reports tab should be fixed or explained.
      <!-- Same as above. -->
* [x] F-Droid CI runners are under GitLab's FOSS program, so there's no need for you to pay for any CI time. If Gitlab starts asking for phone numbers or credit cards don't submit anything, just leave a note in the MR so we know we need to trigger the CI.

## Additional notes for reviewers

* **Native libraries.** `sherpa_onnx` (Apache-2.0) ships its `.so` files through
  its per-ABI **pub packages** (`sherpa_onnx_android_arm64`, `_armeabi`, `_x86`,
  `_x86_64`), resolved by `flutter pub get` during the build. They are freely
  licensed but do not come from one of the trusted Maven repositories named in the
  inclusion policy. No binaries are committed to the repository
  (`git ls-files` contains no `.so`, `.aar` or `.jar`). If building from source is
  required, I can add a `prebuild` step that compiles sherpa-onnx against a
  prebuilt ONNX Runtime (a few minutes) or compiles ONNX Runtime from source as
  well (substantially longer).
* **NDK / CMake.** The `jni` package (pulled in transitively by the sherpa-onnx
  Android plugins) compiles a small native shim, hence `ndk:` and the
  `sdkmanager 'cmake;...'` prebuild step in the metadata.
* **Permissions.** Only `INTERNET`. Cleartext traffic is restricted to
  `127.0.0.1` / `localhost` (the on-device TTS loopback server).
* **Anti-features.** None expected. An earlier version used Microsoft Edge TTS
  (`NonFreeNet`); that code path was removed in 1.1.3 and read-aloud is now
  entirely on-device.
* **AI assistance.** Parts of the app and of this MR (implementation, metadata,
  screenshot redaction) were produced with an AI coding agent. The human
  maintainer reviews every change, is the sole copyright holder, and takes
  responsibility for the submission.

/label ~"New App"