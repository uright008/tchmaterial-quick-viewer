/// Android FileProvider 路径声明与实际落盘位置的一致性。
///
/// 背景（真实踩过的坑）：Android 上「用系统程序打开」失败，但「分享」正常。
///
/// 原因是两条路径用的机制不同：
/// * 分享走 `share_plus`，它会**先把文件复制进自己的 cache**，再用自己的
///   provider —— 所以无论源文件在哪都能成功，**会掩盖配置错误**；
/// * 打开走我们自建的 FileProvider，直接用**原路径**生成 `content://`，
///   路径不在 `tch_file_paths.xml` 声明范围内就会抛
///   `IllegalArgumentException: Failed to find configured root`。
///
/// 当时 `getDownloadsDirectory()` 在 Android 上被我误以为返回 null（实际返回
/// `getExternalFilesDirs(DIRECTORY_DOWNLOADS)`，即
/// `Android/data/<pkg>/files/Download`），于是只声明了内部目录，两者对不上。
///
/// 这个用例把「Dart 侧写在哪」和「XML 侧声明了哪」绑起来：任何一边改了名字
/// 或删了分支，测试立刻失败。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从 Dart 源码里抠出真正的常量，避免测试自己硬编码一份。
String _extract(String source, RegExp pattern, String what) {
  final match = pattern.firstMatch(source);
  if (match == null) {
    fail('没能从 local_store.dart 里解析出$what，正则需要跟着改：$pattern');
  }
  return match.group(1)!;
}

void main() {
  late String filePathsXml;
  late String folderName;
  late String supportDir;

  setUpAll(() {
    final xml = File('android/app/src/main/res/xml/tch_file_paths.xml');
    expect(xml.existsSync(), isTrue,
        reason: '缺少 FileProvider 路径配置，Android 上「用系统程序打开」必然失败');
    filePathsXml = xml.readAsStringSync();

    final store = File('lib/src/data/local_store.dart').readAsStringSync();
    // static const String folderName = 'tchMaterial';
    folderName = _extract(
      store,
      RegExp(r"folderName\s*=\s*'([^']+)'"),
      '教材目录名 folderName',
    );
    // final root = Directory('${base.path}/tchmaterial_viewer');
    supportDir = _extract(
      store,
      RegExp(r"base\.path\}/([A-Za-z0-9_\-]+)'\)"),
      '应用支持子目录名',
    );
  });

  group('FileProvider 声明覆盖 CacheStore 的两种落盘分支', () {
    test('分支一：外部下载目录（Android 的 getDownloadsPath 实际落点）', () {
      // getDownloadsDirectory() → getExternalFilesDirs(DIRECTORY_DOWNLOADS)
      // → <externalFilesDir>/Download/tchMaterial
      expect(
        filePathsXml,
        contains('path="Download/$folderName/"'),
        reason: 'Android 上 getDownloadsPath() 返回 <externalFilesDir>/Download，'
            '教材放在其下的 $folderName 目录，必须用 <external-files-path> 声明；'
            '少了它就会「分享能用、打开失败」',
      );
      expect(filePathsXml, contains('<external-files-path'));
    });

    test('分支二：无外部存储时的内部回退目录', () {
      expect(
        filePathsXml,
        contains('path="$supportDir/"'),
        reason: '设备无外部存储时会回退到 <applicationSupport>/$supportDir，'
            '同样要声明，否则这类设备上打开同样会失败',
      );
      expect(filePathsXml, contains('<files-path'));
    });

    test('两种根都必须声明，缺一不可', () {
      // 只声明一个分支 → 另一类设备/分支上静默失败。
      expect(filePathsXml, contains('<external-files-path'));
      expect(filePathsXml, contains('<files-path'));
    });

    test('provider 的 authorities 与原生代码一致', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final kotlin = File(
        'android/app/src/main/kotlin/com/tchviewer/'
        'tchmaterial_quick_viewer/MainActivity.kt',
      ).readAsStringSync();

      expect(manifest, contains(r'${applicationId}.tchfileprovider'),
          reason: 'manifest 里 provider 的 authorities');
      expect(kotlin, contains(r'$packageName.tchfileprovider'),
          reason: '原生侧 getUriForFile 用的 authority 必须与 manifest 一致，'
              '否则会抛 IllegalArgumentException');
    });
  });
}
