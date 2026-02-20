# Flutter Android 版 NFO 生成器

这个目录提供 Flutter 方案的核心代码：

- `lib/main.dart`：抓取 madouqu、解析详情、生成 NFO、保存本地
- `pubspec.yaml`：依赖
- `android/app/src/main/AndroidManifest.xml`：已加网络权限

## 1) 初始化工程（首次）

本环境没有安装 Flutter，所以我无法直接构建。你本机安装 Flutter 后，在此目录执行：

```bash
cd /Users/zxt/Documents/New\ project/flutter_madou_nfo
flutter create .
```

然后把本目录中的这三个文件保留为当前版本（`flutter create` 若覆盖，请再替换回来）：

- `pubspec.yaml`
- `lib/main.dart`
- `android/app/src/main/AndroidManifest.xml`

## 2) 运行调试

```bash
flutter pub get
flutter run
```

## 3) 打包 APK

```bash
flutter build apk --release
```

产物路径：

`build/app/outputs/flutter-apk/app-release.apk`

## 4) 应用功能

- 输入视频名/番号（如 `MD-0382`）
- 点击“生成 NFO”
- 自动写入：
  - app 专属外部目录：`.../Android/data/<包名>/files/nfo_output/`
  - `.nfo` 文件（默认按番号命名）
  - `poster.jpg`（可关闭）

## 5) 后续可扩展

- 加“手动选择搜索结果”列表
- 批量导入文件名并批量生成
- 支持自定义输出目录（SAF 文档树）
