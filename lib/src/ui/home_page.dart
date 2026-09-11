/// 顶层外壳：左侧导航 + 内容区。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/catalog_controller.dart';
import '../state/library_controller.dart';
import 'pages/browse_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _destination = 0;

  @override
  void initState() {
    super.initState();
    // 首帧后开始加载目录，让窗口先以完整骨架出现，避免白屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CatalogController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final activeDownloads =
        context.select<LibraryController, int>((c) => c.activeTasks.length);

    const destinations = [
      NavigationRailDestination(
        icon: Icon(Icons.grid_view_outlined),
        selectedIcon: Icon(Icons.grid_view),
        label: Text('浏览'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.download_outlined),
        selectedIcon: Icon(Icons.download),
        label: Text('书架'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('设置'),
      ),
    ];

    final body = IndexedStack(
      index: _destination,
      children: const [BrowsePage(), LibraryPage(), SettingsPage()],
    );

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _destination,
          onDestinationSelected: (i) => setState(() => _destination = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: '浏览',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: '书架',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: '设置',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _destination,
            onDestinationSelected: (i) => setState(() => _destination = i),
            labelType:
                width >= 1180 ? NavigationRailLabelType.all : NavigationRailLabelType.selected,
            destinations: [
              destinations[0],
              NavigationRailDestination(
                icon: Badge.count(
                  count: activeDownloads,
                  isLabelVisible: activeDownloads > 0,
                  child: const Icon(Icons.download_outlined),
                ),
                selectedIcon: Badge.count(
                  count: activeDownloads,
                  isLabelVisible: activeDownloads > 0,
                  child: const Icon(Icons.download),
                ),
                label: const Text('书架'),
              ),
              destinations[2],
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
