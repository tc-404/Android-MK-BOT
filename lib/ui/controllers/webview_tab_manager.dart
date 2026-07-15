import 'package:get/get.dart';

import 'app_web_controller.dart';

/// 一个 WebUI 标签页 (通用, 无特定业务语义)。
class WebViewTab {
  final String id;
  /// 站点标识: scheme://host:port, 用于同端口复用标签。
  String origin;
  String title;
  String url;
  final AppWebController controller;

  WebViewTab({
    required this.id,
    required this.origin,
    required this.title,
    required this.url,
    required this.controller,
  });
}

/// 通用 WebUI 标签页管理器: 与终端标签页对等。
/// 默认无任何标签; 由动作 (host.webview_open) 按需创建。
/// 同 origin (scheme+host+port) 复用已有标签, 不强制 reload。
class WebViewTabManager {
  final RxList<WebViewTab> tabs = <WebViewTab>[].obs;
  final RxInt activeIndex = 0.obs;

  /// 正在编辑 URL 的标签索引; null = 未处于编辑态。
  final RxnInt editingIndex = RxnInt();
  bool _editingIsNew = false;

  void Function(String tabId)? onTabClosed;

  /// 打开 URL: 同 origin 已有标签则切过去并保持当前页面; 完全相同 URL 亦如此。
  void openUrl(String url, String title) {
    final norm = normalizeUrl(url.trim()) ?? url.trim();
    if (norm.isEmpty) return;

    final origin = originKey(norm);

    final byOrigin = tabs.indexWhere((t) => t.origin == origin);
    if (byOrigin >= 0) {
      activeIndex.value = byOrigin;
      if (title.isNotEmpty) tabs[byOrigin].title = title;
      return;
    }

    final tabId = 'webui_${DateTime.now().millisecondsSinceEpoch}';
    final tab = WebViewTab(
      id: tabId,
      origin: origin,
      title: title.isEmpty ? displayTitle(norm) : title,
      url: norm,
      controller: AppWeb.create(norm, onInWebViewUrl: (u) {
        final i = tabs.indexWhere((t) => t.id == tabId);
        if (i >= 0) tabs[i].url = u;
      }),
    );
    tabs.add(tab);
    activeIndex.value = tabs.length - 1;
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs.removeAt(index);
    tab.controller.clearCache();
    tab.controller.dispose();
    onTabClosed?.call(tab.id);
    if (tabs.isEmpty) {
      activeIndex.value = 0;
    } else if (activeIndex.value >= tabs.length) {
      activeIndex.value = tabs.length - 1;
    }
  }

  void refresh(int index) {
    if (index < 0 || index >= tabs.length) return;
    tabs[index].controller.reload();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= tabs.length) return;
    if (newIndex < 0 || newIndex >= tabs.length) return;
    if (oldIndex == newIndex) return;
    final active = (activeIndex.value >= 0 && activeIndex.value < tabs.length)
        ? tabs[activeIndex.value]
        : null;
    final moved = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, moved);
    if (active != null) activeIndex.value = tabs.indexOf(active);
  }

  void beginEditNew() {
    final tab = WebViewTab(
      id: 'webui_${DateTime.now().millisecondsSinceEpoch}',
      origin: '',
      title: '',
      url: '',
      controller: AppWeb.create('about:blank'),
    );
    tabs.add(tab);
    activeIndex.value = tabs.length - 1;
    _editingIsNew = true;
    editingIndex.value = tabs.length - 1;
  }

  void beginEdit(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeIndex.value = index;
    _editingIsNew = false;
    editingIndex.value = index;
  }

  void commitEdit(String text) {
    final i = editingIndex.value;
    if (i == null || i < 0 || i >= tabs.length) {
      editingIndex.value = null;
      return;
    }
    final url = normalizeUrl(text);
    if (url == null) {
      if (_editingIsNew) _removeAt(i);
    } else {
      final origin = originKey(url);
      final existing = tabs.indexWhere((t) => t.origin == origin && t.id != tabs[i].id);
      if (existing >= 0) {
        _removeAt(i);
        activeIndex.value = existing;
        tabs[existing].url = url;
        if (tabs[existing].title.isEmpty) {
          tabs[existing].title = displayTitle(url);
        }
      } else {
        final t = tabs[i];
        t.url = url;
        t.origin = origin;
        t.title = displayTitle(url);
        t.controller.loadUrl(url);
        tabs.refresh();
      }
    }
    editingIndex.value = null;
    _editingIsNew = false;
  }

  void cancelEdit() {
    final i = editingIndex.value;
    if (i != null && _editingIsNew && i >= 0 && i < tabs.length) _removeAt(i);
    editingIndex.value = null;
    _editingIsNew = false;
  }

  void _removeAt(int index) {
    final tab = tabs.removeAt(index);
    tab.controller.dispose();
    if (tabs.isEmpty) {
      activeIndex.value = 0;
    } else if (activeIndex.value >= tabs.length) {
      activeIndex.value = tabs.length - 1;
    }
  }

  static String originKey(String url) {
    try {
      final u = Uri.parse(url.trim());
      if (!u.hasScheme || u.host.isEmpty) return url.trim().toLowerCase();
      final port = u.hasPort
          ? u.port
          : (u.scheme == 'https'
              ? 443
              : u.scheme == 'http'
                  ? 80
                  : 0);
      return '${u.scheme}://${u.host.toLowerCase()}:$port';
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  static String? normalizeUrl(String input) {
    var v = input.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final port = int.tryParse(v);
    if (port != null && port >= 1 && port <= 65535) {
      return 'http://127.0.0.1:$port';
    }
    return 'http://$v';
  }

  static String displayTitle(String url) {
    return url.replaceFirst(RegExp(r'^https?://'), '');
  }
}
