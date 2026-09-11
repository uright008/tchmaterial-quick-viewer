/// 设置页：登录凭据、外观、阅读偏好、缓存与关于。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/file_actions.dart';
import '../../models/credentials.dart';
import '../../state/catalog_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';

/// 凭据获取指引（与参考项目 tchMaterial-parser 的说明一致）。
const String kCredentialHelp = '''
如何获取登录凭据

1. 浏览器打开并登录 https://basic.smartedu.cn/
2. 按 F12 打开开发者工具，切到「网络 / Network」标签
3. 刷新页面，随便点一个请求，在「请求头 / Request Headers」里找到 Cookie
4. 复制**整条 Cookie**（或只复制其中 UC_TOKEN- 开头那一段的值）粘贴到下面

本应用需要 Cookie 里的 access_token 与 mac_key 才能为私有 CDN 的
教材文件生成合法签名。只贴 access_token 也能用，但部分教材会返回 400。
''';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Section(
            title: '登录凭据',
            icon: Icons.key_outlined,
            children: [
              _CredentialStatus(settings: settings),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _editCredentials(context, settings),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      settings.hasCredentials ? '更新凭据' : '粘贴 Cookie / Token',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _testConnection(context),
                    icon: const Icon(Icons.network_check, size: 18),
                    label: const Text('测试网络'),
                  ),
                  if (settings.hasCredentials)
                    TextButton.icon(
                      onPressed: settings.clearCredentials,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('清除凭据'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '外观',
            icon: Icons.palette_outlined,
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto, size: 18),
                    label: Text('跟随系统'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 18),
                    label: Text('浅色'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 18),
                    label: Text('深色'),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) =>
                    settings.setThemeMode(selection.first),
              ),
              const SizedBox(height: 18),
              const _SubLabel('默认排序'),
              const SizedBox(height: 8),
              SegmentedButton<SortOrder>(
                segments: [
                  for (final order in SortOrder.values)
                    ButtonSegment(
                      value: order,
                      icon: Icon(order.icon, size: 18),
                      label: Text(order.label),
                    ),
                ],
                selected: {settings.sortOrder},
                onSelectionChanged: (selection) {
                  settings.setSortOrder(selection.first);
                  context.read<CatalogController>().setSortOrder(
                    selection.first,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '阅读',
            icon: Icons.auto_stories_outlined,
            children: [
              if (supportsExternalFileOpen)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.autoOpenNative,
                  onChanged: settings.setAutoOpenNative,
                  title: const Text('用系统默认程序打开教材'),
                  subtitle: const Text(
                    '开启后点「在线阅读」会直接交给系统 PDF 阅读器，'
                    '而不是使用内置阅读器。',
                  ),
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_stories_outlined),
                  title: Text('使用内置阅读器'),
                  subtitle: Text(
                    '当前平台不支持把文件交给系统默认程序，将始终使用内置阅读器。',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '缓存',
            icon: Icons.storage_outlined,
            children: [
              _InfoRow(
                label: '已缓存教材',
                value:
                    '${library.offlineFiles.length} 个文件 · ${_formatBytes(library.cacheSizeBytes)}',
              ),
              _InfoRow(label: '保存位置', value: library.downloadFolderPath),
              const SizedBox(height: 4),
              Text(
                '教材直接存放在系统下载目录下的 tchMaterial 文件夹，'
                '可以用文件管理器找到，也能直接交给第三方 PDF 阅读器打开。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.read<CatalogController>().load(
                      forceRefresh: true,
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('重新拉取平台目录'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _clearCatalogCache(context, library),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('清除目录缓存'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '关于',
            icon: Icons.info_outline,
            children: [
              const Text(
                '教材查看器 —— 国家中小学智慧教育平台电子课本浏览器。\n\n'
                '数据与签名规则参考开源项目 happycola233/tchMaterial-parser。'
                '本应用只读取平台已公开的教材文件，不存储、不分发任何内容。',
              ),
              const SizedBox(height: 12),
              const _InfoRow(label: '平台', value: 'basic.smartedu.cn'),
              const _InfoRow(label: '电子教材总数', value: '约 3,574 本'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clearCatalogCache(
    BuildContext context,
    LibraryController library,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await library.clearCatalogCache();
    messenger.showSnackBar(
      const SnackBar(content: Text('目录缓存已清除，下次进入浏览页会重新拉取')),
    );
  }

  Future<void> _editCredentials(
    BuildContext context,
    SettingsController settings,
  ) async {
    final controller = TextEditingController();
    final error = ValueNotifier<String?>(null);
    // 对话框关闭后必须释放，否则每次打开设置都会泄漏一对控制器/监听器。
    bool? saved;
    try {
      saved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('粘贴登录凭据'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    kCredentialHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    maxLines: 6,
                    minLines: 4,
                    autofocus: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'sf=…; UC_TOKEN-…=eyJ…; 或 {"access_token":"…","mac_key":"…","diff":11}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String?>(
                    valueListenable: error,
                    builder: (context, value, _) => value == null
                        ? const SizedBox.shrink()
                        : Text(
                            value,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await settings.saveCredentials(controller.text);
                  if (context.mounted) Navigator.of(context).pop(true);
                } on CredentialsFormatException catch (e) {
                  error.value = e.message;
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
      error.dispose();
    }

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('凭据已保存')));
    }
  }

  Future<void> _testConnection(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<PlatformApi>();
    messenger.showSnackBar(const SnackBar(content: Text('正在测试连接…')));
    try {
      final json = await api.getJson(PlatformEndpoints.tagTree);
      final hierarchies = json is Map ? json['hierarchies'] : null;
      final count = hierarchies is List ? hierarchies.length : 0;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(count > 0 ? '连接正常，已取到平台分类树。' : '连接正常，但返回结构非预期。'),
        ),
      );
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('连接失败：$error')));
    }
  }
}

class _CredentialStatus extends StatelessWidget {
  const _CredentialStatus({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creds = settings.credentials;

    if (creds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Banner(
            icon: Icons.privacy_tip_outlined,
            color: theme.colorScheme.secondaryContainer,
            onColor: theme.colorScheme.onSecondaryContainer,
            title: '未配置凭据 · 当前是匿名访问',
            detail:
                '请求头里是固定的占位值，不含任何账号标识：\n'
                'Authorization: Bearer 0\n'
                'X-ND-AUTH: MAC id="0",nonce="0",mac="0"',
          ),
          const SizedBox(height: 12),
          Text(
            '匿名可用范围（对本平台真实抽样 160 本的实测结果）：\n'
            '· 分类树 / 教材列表：完全公开，不需要凭据\n'
            '· 教材详情与文件：约 81% 可以直接解析并下载\n'
            '· 其余约 19% 平台返回 403，多为「体育与健康教师用书」一类\n'
            '  教师用书。实测这类资源即使带上有效 Cookie 仍旧 403，\n'
            '  属于平台未开放直链，只能在 basic.smartedu.cn 网页端阅读。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    final expired = creds.isExpired;
    final partial = !creds.canSign;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Banner(
          icon: expired
              ? Icons.error_outline
              : (partial
                    ? Icons.warning_amber_outlined
                    : Icons.verified_outlined),
          color: expired || partial
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          onColor: expired || partial
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onPrimaryContainer,
          title: expired ? '凭据已过期' : (partial ? '凭据不完整（缺少 mac_key）' : '凭据有效'),
          detail: expired
              ? '请重新从浏览器复制 Cookie。'
              : (partial
                    ? '可以解析目录与详情，但部分私有教材文件会返回 400。'
                    : '已能生成真实的 X-ND-AUTH 签名，可下载约 81% 的教材；'
                          '若仍遇 403，那是平台对该资源未开放直链，与凭据无关。'),
        ),
        const SizedBox(height: 12),
        const _InfoRow(label: 'access_token', value: '已保存'),
        if (creds.macKey != null)
          const _InfoRow(label: 'mac_key', value: '已保存'),
        _InfoRow(label: '时钟差 diff', value: '${creds.diff} ms'),
        if (creds.userId != null)
          _InfoRow(label: '用户 ID', value: creds.userId!),
        if (creds.expiresAt != null)
          _InfoRow(label: '过期时间', value: _formatTime(creds.expiresAt!)),
      ],
    );
  }

  static String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final Color onColor;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: onColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(color: onColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
