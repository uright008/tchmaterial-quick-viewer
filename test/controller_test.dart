/// 控制器层的行为测试。
///
/// 补这块是有具体原因的：曾经有一次批量重构把 `_safeNotify()` 函数体里的
/// `notifyListeners()` 也替换成了 `_safeNotify()`，变成无限自我递归 —— 应用一
/// 启动就 Stack Overflow，而当时 96 个测试全绿。原因是**没有任何测试碰过控制器
/// 的 notify 路径**：widget 测试直接喂数据给纯 widget，绕开了 state 层。
///
/// 所以这里逐个方法验证「调用后通知确实发出去了」以及「dispose 后不再发」。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tchmaterial_quick_viewer/src/core/api_client.dart';
import 'package:tchmaterial_quick_viewer/src/data/catalog_repository.dart';
import 'package:tchmaterial_quick_viewer/src/data/local_store.dart';
import 'package:tchmaterial_quick_viewer/src/models/credentials.dart';
import 'package:tchmaterial_quick_viewer/src/state/catalog_controller.dart';
import 'package:tchmaterial_quick_viewer/src/state/library_controller.dart';
import 'package:tchmaterial_quick_viewer/src/state/settings_controller.dart';

/// 统计某个 ChangeNotifier 被通知的次数。
class Counter {
  int value = 0;
  void call() => value++;
}

CatalogRepository buildRepository() {
  final dir = Directory.systemTemp.createTempSync('tchviewer_test');
  final api = PlatformApi(
    credentials: () => Credentials.empty,
    client: MockClient(
      (request) async => http.Response('{"hierarchies":[],"urls":""}', 200),
    ),
  );
  return CatalogRepository(api: api, cache: CacheStore.inDirectory(dir));
}

void main() {
  group('CatalogController 通知路径', () {
    late CatalogController controller;
    late Counter counter;

    setUp(() {
      controller = CatalogController(buildRepository());
      counter = Counter();
      controller.addListener(counter.call);
    });

    test('select 会通知一次且不递归', () {
      controller.select(null);
      expect(counter.value, 1, reason: '通知次数异常通常意味着 _safeNotify 递归了');
    });

    test('setQuery 会通知，且相同值不重复通知', () {
      controller.setQuery('数学');
      expect(counter.value, 1);
      controller.setQuery('数学');
      expect(counter.value, 1, reason: '值没变不该重复通知');
      controller.setQuery('语文');
      expect(counter.value, 2);
    });

    test('setSortOrder 会通知，且相同值不重复通知', () {
      controller.setSortOrder(SortOrder.title);
      expect(counter.value, 1);
      controller.setSortOrder(SortOrder.title);
      expect(counter.value, 1);
    });

    test('dispose 之后不再通知', () {
      final c = CatalogController(buildRepository());
      final n = Counter();
      c.addListener(n.call);
      c.select(null);
      expect(n.value, 1);

      c.dispose();
      // 释放后再调用不应抛异常，也不应再通知。
      expect(() => c.select(null), returnsNormally);
      expect(n.value, 1);
    });
  });

  group('LibraryController 通知路径', () {
    test('dismiss 会通知一次且不递归', () {
      final controller = LibraryController(buildRepository());
      final counter = Counter();
      controller.addListener(counter.call);

      // 没有该任务时是空操作，不通知。
      controller.dismiss('nope');
      expect(counter.value, 0);

      controller.clearFinished();
      expect(counter.value, 1);
    });

    test('dispose 之后不再通知', () {
      final controller = LibraryController(buildRepository());
      final counter = Counter();
      controller.addListener(counter.call);

      controller.clearFinished();
      expect(counter.value, 1);

      controller.dispose();
      expect(() => controller.clearFinished(), returnsNormally);
      expect(counter.value, 1);
    });
  });

  group('SettingsController 通知路径', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('保存与清除凭据都会各通知一次', () async {
      final store = await SettingsStore.open();
      final controller = SettingsController(store);
      final counter = Counter();
      controller.addListener(counter.call);

      await controller.saveCredentials(
        '{"access_token":"AAAAAAAAAAAAAAAAAAAA","mac_key":"K","diff":3}',
      );
      expect(counter.value, 1);
      expect(controller.hasCredentials, isTrue);
      expect(controller.canSignRequests, isTrue);

      await controller.clearCredentials();
      expect(counter.value, 2);
      expect(controller.hasCredentials, isFalse);
    });

    test('主题与排序偏好改动会通知', () async {
      final controller = SettingsController(await SettingsStore.open());
      final counter = Counter();
      controller.addListener(counter.call);

      await controller.setThemeMode(ThemeMode.dark);
      expect(counter.value, 1);
      await controller.setSortOrder(SortOrder.title);
      expect(counter.value, 2);
      await controller.setAutoOpenNative(true);
      expect(counter.value, 3);
    });

    test('dispose 之后不再通知', () async {
      final controller = SettingsController(await SettingsStore.open());
      final counter = Counter();
      controller.addListener(counter.call);

      controller.dispose();
      expect(() => controller.setSortOrder(SortOrder.title), returnsNormally);
      expect(counter.value, 0);
    });
  });

  group('凭据持久化往返', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('保存后重新打开仍能读到', () async {
      final store = await SettingsStore.open();
      final controller = SettingsController(store);
      await controller.saveCredentials(
        '{"access_token":"TOKEN0123456789ABCDEF","mac_key":"MACKEY","diff":9}',
      );

      final reopened = SettingsController(await SettingsStore.open());
      expect(reopened.credentials.accessToken, 'TOKEN0123456789ABCDEF');
      expect(reopened.credentials.macKey, 'MACKEY');
      expect(reopened.credentials.diff, 9);
    });
  });
}
