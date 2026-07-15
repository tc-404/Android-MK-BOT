import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/config/ui_preferences.dart';
import '../../core/constants/scripts.dart';
import '../../core/utils/asset_copy.dart';
import '../../core/utils/file_utils.dart';
import 'terminal_tab_manager.dart';
import 'webview_tab_manager.dart';

class HomeController extends GetxController {
  // 终端标签页管理器
  late final TerminalTabManager terminalTabManager;
  // 通用 WebUI 标签页管理器 (无特定业务语义)
  final WebViewTabManager webViewTabManager = WebViewTabManager();
  // 再次点击当前导航图标的信号: 终端页弹出更多菜单; WebUI 页切换二级浏览器工具栏
  final RxInt terminalMenuSignal = 0.obs;
  final RxBool webviewToolbarVisible = false.obs;

  SettingNode privacySetting = 'privacy'.setting;

  final RxString homeBackgroundPath = ''.obs;
  final RxDouble cardGlassOpacity = 0.62.obs;
  final RxDouble glassBlurAmount = 0.45.obs;
  final RxDouble topNavGlassOpacity = 0.62.obs;
  final RxDouble statusOverlayOpacity = 0.38.obs;
  final RxDouble terminalOverlayOpacity = 0.65.obs;
  final RxnInt pendingMainTabIndex = RxnInt();

  /// 启动时 Ubuntu 安装遮罩 (全屏最顶层)
  final RxBool ubuntuBootstrapActive = false.obs;
  final RxDouble ubuntuBootstrapProgress = 0.0.obs;
  final RxString ubuntuBootstrapMessage = ''.obs;
  final RxString ubuntuBootstrapLog = ''.obs;
  bool _ubuntuBootstrapRunning = false;
  Timer? _ubuntuBootstrapPollTimer;
  DateTime? _ubuntuBootstrapLastProgressAt;
  String _ubuntuBootstrapLastMessage = '';

  void clearPendingMainTabIndex(int index) {
    if (pendingMainTabIndex.value == index) {
      pendingMainTabIndex.value = null;
    }
  }

  // 检查两个条件是否都满足，如果满足则切到新版主界面的 WebUI 页。
  Future<void> initEnvir() async {
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so'
    ];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      // when android target sdk > 28
      // cannot execute file in /data/data/com.xxx/files/usr/bin
      // so we need create a link to /data/data/com.xxx/files/usr/bin
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(RegExp('^lib|\\.so\$'), '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      // custom path, termux-api will invoke
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        // old version adb is plain file
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
      if (link.existsSync()) {
        link.deleteSync();
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }
  }

  // 同步当前进度
  // Sync the current progress
  void createBusyboxLink() {
    try {
      List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip'
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd'
        ]
      ];

      for (String linkName in links) {
        Link link = Link('${RuntimeEnvir.binPath}/$linkName');
        if (!link.existsSync()) {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        }
      }
      Link link = Link('${RuntimeEnvir.binPath}/file');
      link.createSync('/system/bin/file');
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  String _toUnixLineEndings(String content) {
    return content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  void onInit() {
    super.onInit();

    // 初始化终端标签页管理器
    terminalTabManager = TerminalTabManager();
    terminalTabManager.onTabClosed = (tabId) {
      // 用户手动关闭终端标签页 → 反查 spawn key 并更新运行态
      final key = _spawnTabIds.entries
          .where((e) => e.value == tabId)
          .map((e) => e.key)
          .firstOrNull;
      if (key != null) {
        _spawnTabIds.remove(key);
        _setSpawnRunning(key, false);
      }
    };

    _loadUiPreferences();

    // 监听应用生命周期状态变化
    WidgetsBinding.instance.addObserver(
      LifecycleObserver(
        onResume: () {},
        onPause: () {},
      ),
    );
  }

  // 加载自定义 WebView 列表
  void _loadUiPreferences() {
    homeBackgroundPath.value = UiPreferences.homeBackgroundPath;
    cardGlassOpacity.value = UiPreferences.cardGlassOpacity;
    glassBlurAmount.value = UiPreferences.glassBlurAmount;
    topNavGlassOpacity.value = UiPreferences.topNavGlassOpacity;
    statusOverlayOpacity.value = UiPreferences.statusOverlayOpacity;
    terminalOverlayOpacity.value = UiPreferences.terminalOverlayOpacity;
  }

  void setHomeBackgroundPath(String path) {
    UiPreferences.saveHomeBackgroundPath(path);
    homeBackgroundPath.value = path;
  }

  void clearHomeBackgroundPath() {
    UiPreferences.clearHomeBackgroundPath();
    homeBackgroundPath.value = '';
  }

  void setCardGlassOpacity(double value) {
    UiPreferences.saveCardGlassOpacity(value);
    cardGlassOpacity.value = UiPreferences.cardGlassOpacity;
  }

  void setGlassBlurAmount(double value) {
    UiPreferences.saveGlassBlurAmount(value);
    glassBlurAmount.value = UiPreferences.glassBlurAmount;
  }

  void setTopNavGlassOpacity(double value) {
    UiPreferences.saveTopNavGlassOpacity(value);
    topNavGlassOpacity.value = UiPreferences.topNavGlassOpacity;
  }

  void setStatusOverlayOpacity(double value) {
    UiPreferences.saveStatusOverlayOpacity(value);
    statusOverlayOpacity.value = UiPreferences.statusOverlayOpacity;
  }

  void setTerminalOverlayOpacity(double value) {
    UiPreferences.saveTerminalOverlayOpacity(value);
    terminalOverlayOpacity.value = UiPreferences.terminalOverlayOpacity;
  }

  String _shellSingleQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  /// 将多行脚本写入 TMPDIR (proot 内同路径可见), 避免 login_ubuntu 引号嵌套导致脚本未执行。
  String _writeHostScript(String name, String body) {
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    final path = '${RuntimeEnvir.tmpPath}/$name';
    File(path).writeAsStringSync(_toUnixLineEndings(body));
    return path;
  }

  String _loginViaScript(String hostScriptPath) =>
      _shellSingleQuote('bash $hostScriptPath');

  Future<void> runShellCommand(String command) => _runUbuntuShell(command);

  /// 供 Lua 脚本调用: 某 key 对应的实例是否正在运行 (有活动 Pty)。
  Future<void> ensureContainerScripts({
    void Function(String message, double progress)? onPhase,
  }) async {
    void phase(String message, double progress) {
      onPhase?.call(message, progress);
    }

    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);

    phase('正在初始化运行库…', 0.04);
    await initEnvir();
    createBusyboxLink();

    final ubuntuAssetFile =
        File('${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    final assetKey = 'assets/${Config.ubuntuFileName}';
    var needCopy = true;
    if (await ubuntuAssetFile.exists()) {
      final len = await ubuntuAssetFile.length();
      if (len >= Config.ubuntuArchiveMinBytes) {
        needCopy = false;
        phase('系统镜像已就绪', 0.14);
      } else {
        try {
          await ubuntuAssetFile.delete();
        } catch (_) {}
        phase('检测到不完整镜像, 将重新复制…', 0.06);
      }
    }

    if (needCopy) {
      phase('正在从安装包复制系统镜像 (首次较慢, 请耐心等待)…', 0.08);
      try {
        if (Platform.isAndroid) {
          final bytes = await AssetCopy.copyFlutterAsset(
            assetKey,
            ubuntuAssetFile.path,
          );
          final onDisk = await ubuntuAssetFile.length();
          if (onDisk < Config.ubuntuArchiveMinBytes ||
              (bytes > 0 && onDisk != bytes)) {
            throw FileSystemException(
              '镜像复制不完整 (${onDisk ~/ (1024 * 1024)} MB)',
              ubuntuAssetFile.path,
            );
          }
        } else {
          await AssetsUtils.copyAssetToPath(assetKey, ubuntuAssetFile.path);
        }
        phase('系统镜像复制完成', 0.18);
      } catch (e) {
        Log.e('复制 Ubuntu 镜像失败: $e');
        rethrow;
      }
    }

    phase('正在写入安装脚本…', 0.20);
    final appVersion = await getAppVersion();
    File('${RuntimeEnvir.homePath}/common.sh').writeAsStringSync(
      _toUnixLineEndings(getCommonScript(appVersion)),
    );
  }

  void _setBootstrapPhase(String message, double progress) {
    ubuntuBootstrapMessage.value = message;
    if (progress > ubuntuBootstrapProgress.value) {
      ubuntuBootstrapProgress.value = progress.clamp(0.0, 0.98);
    }
    _ubuntuBootstrapLastMessage = message;
    _ubuntuBootstrapLastProgressAt = DateTime.now();
    try {
      File('${RuntimeEnvir.tmpPath}/progress_des').writeAsStringSync(message);
    } catch (_) {}
  }

  /// 启动时安装 Ubuntu rootfs; 返回是否安装成功。
  /// [installOnly] 为 true 时由启动页调用, 不重复检查 running 状态。
  Future<bool> bootstrapUbuntu({bool installOnly = false}) async {
    if (_ubuntuBootstrapRunning) return isUbuntuInstalled();
    if (!installOnly && isUbuntuInstalled()) return true;

    _ubuntuBootstrapRunning = true;
    ubuntuBootstrapActive.value = true;
    ubuntuBootstrapProgress.value = 0.02;
    ubuntuBootstrapMessage.value = '正在准备 Ubuntu 环境…';
    ubuntuBootstrapLog.value = '';
    _ubuntuBootstrapLastMessage = ubuntuBootstrapMessage.value;
    _ubuntuBootstrapLastProgressAt = DateTime.now();
    await Future<void>.delayed(Duration.zero);

    try {
      Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
      File('${RuntimeEnvir.tmpPath}/progress').writeAsStringSync('0');
      File('${RuntimeEnvir.tmpPath}/progress_des')
          .writeAsStringSync('正在准备 Ubuntu 环境…');
    } catch (_) {}

    _ubuntuBootstrapPollTimer?.cancel();
    _ubuntuBootstrapPollTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      _pollUbuntuBootstrapProgress();
    });

    var ok = false;
    try {
      await ensureContainerScripts(onPhase: _setBootstrapPhase);

      _setBootstrapPhase('正在解压并配置 Ubuntu 容器…', 0.22);

      final marker = '__ROOTFS_DONE_${DateTime.now().millisecondsSinceEpoch}__';
      final bootstrapScript = _writeHostScript(
        'bootstrap_ubuntu.sh',
        'set -e\n'
            'source ${RuntimeEnvir.homePath}/common.sh\n'
            'install_ubuntu\n'
            'echo $marker\n',
      );

      final handle = await terminalTabManager.runEphemeralCommand(
        command: 'bash ${_shellSingleQuote(bootstrapScript)}\n',
        onDoneMarker: marker,
        onOutput: _appendUbuntuBootstrapLog,
        hideEcho: true,
      );
      await handle.done.timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          ubuntuBootstrapMessage.value = '安装超时, 请重启应用重试';
        },
      );
      ok = isUbuntuInstalled();
      if (ok) {
        markUbuntuReady();
        ubuntuBootstrapProgress.value = 1.0;
        ubuntuBootstrapMessage.value = 'Ubuntu 环境就绪';
        await Future.delayed(const Duration(milliseconds: 900));
      } else {
        ubuntuBootstrapMessage.value = 'Ubuntu 安装未完成, 请重启应用重试';
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      Log.e('Ubuntu 启动安装失败: $e');
      ubuntuBootstrapMessage.value = '安装失败: $e';
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      _ubuntuBootstrapPollTimer?.cancel();
      _ubuntuBootstrapPollTimer = null;
      ubuntuBootstrapActive.value = false;
      _ubuntuBootstrapRunning = false;
    }
    return ok;
  }

  @Deprecated('Use bootstrapUbuntu()')
  Future<void> bootstrapUbuntuIfNeeded() async {
    await bootstrapUbuntu();
  }

  void _pollUbuntuBootstrapProgress() {
    try {
      final desFile = File('${RuntimeEnvir.tmpPath}/progress_des');
      if (desFile.existsSync()) {
        final msg = desFile.readAsStringSync().trim();
        if (msg.isNotEmpty && msg != _ubuntuBootstrapLastMessage) {
          ubuntuBootstrapMessage.value = msg;
          _ubuntuBootstrapLastMessage = msg;
          _ubuntuBootstrapLastProgressAt = DateTime.now();
        }
      }
      final extractLog = File('${RuntimeEnvir.tmpPath}/ubuntu_extract.log');
      if (extractLog.existsSync()) {
        final lines = extractLog
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          final tail = lines.last.length > 72
              ? '…${lines.last.substring(lines.last.length - 72)}'
              : lines.last;
          final msg = '解压中: $tail';
          if (msg != _ubuntuBootstrapLastMessage) {
            ubuntuBootstrapMessage.value = msg;
            _ubuntuBootstrapLastMessage = msg;
            _ubuntuBootstrapLastProgressAt = DateTime.now();
          }
        }
      }
      final progFile = File('${RuntimeEnvir.tmpPath}/progress');
      if (progFile.existsSync()) {
        final step =
            int.tryParse(progFile.readAsStringSync().trim()) ?? 0;
        final ratio = step / ubuntuInstallProgressSteps;
        if (ratio > ubuntuBootstrapProgress.value) {
          ubuntuBootstrapProgress.value = ratio.clamp(0.0, 0.98);
          _ubuntuBootstrapLastProgressAt = DateTime.now();
        }
      }
      final last = _ubuntuBootstrapLastProgressAt;
      if (last != null &&
          DateTime.now().difference(last) > const Duration(seconds: 90) &&
          ubuntuBootstrapActive.value) {
        ubuntuBootstrapMessage.value =
            '${_ubuntuBootstrapLastMessage.isEmpty ? "仍在处理中" : _ubuntuBootstrapLastMessage} (耗时较长, 请保持前台并确保存储空间充足)';
        _ubuntuBootstrapLastProgressAt = DateTime.now();
      }
    } catch (_) {}
  }

  void _appendUbuntuBootstrapLog(String chunk) {
    if (chunk.isEmpty) return;
    final cleaned = chunk
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    ubuntuBootstrapLog.value += cleaned;
    if (ubuntuBootstrapLog.value.length > 12000) {
      ubuntuBootstrapLog.value = ubuntuBootstrapLog.value
          .substring(ubuntuBootstrapLog.value.length - 12000);
    }
    for (final line in cleaned.split('\n')) {
      final t = line.trim();
      if (t.startsWith('[state]') ||
          t.startsWith('[backup]') ||
          t.startsWith('[restore]') ||
          t.startsWith('[result]') ||
          t.startsWith('[error]') ||
          t.startsWith('[cmd]')) {
        ubuntuBootstrapMessage.value = t;
      }
    }
  }

  /// 原语: 解压/初始化 Ubuntu rootfs (进容器前的准备), 流式输出到终端 tab。
  Future<void> installRootfs({
    String title = '初始化容器',
    void Function()? onExit,
  }) async {
    await ensureContainerScripts();
    try {
      File('${RuntimeEnvir.homePath}/.ubuntu_ready').deleteSync();
    } catch (_) {}
    final marker = '__ROOTFS_DONE_${DateTime.now().millisecondsSinceEpoch}__';
    final script = _writeHostScript(
      'install_rootfs.sh',
      'source ${RuntimeEnvir.homePath}/common.sh\n'
          'install_ubuntu\n'
          'echo $marker\n',
    );
    await terminalTabManager.addCommandTerminalTab(
      title: title,
      command: 'bash ${_shellSingleQuote(script)}\n'
          'stty sane 2>/dev/null; stty echo 2>/dev/null\n',
      onDoneMarker: marker,
      onCommandDone: () {
        if (isUbuntuInstalled()) markUbuntuReady();
        onExit?.call();
      },
    );
  }

  /// 通用 spawn 运行态跟踪 (按调用方给的 key)。
  final RxInt spawnRevision = 0.obs;
  final Map<String, bool> spawnRunning = {};
  final Map<String, String> _spawnTabIds = {};
  final Map<String, void Function()> _silentSpawnCancels = {};
  final Map<String, StringBuffer> _spawnLogBuffers = {};
  static const int _maxSpawnLogChars = 200000;

  bool isSpawnRunning(String key) => spawnRunning[key] == true;

  String spawnLog(String key) {
    final tabId = _spawnTabIds[key];
    if (tabId != null) {
      for (final tab in terminalTabManager.tabs) {
        if (tab.id == tabId && tab.logText.isNotEmpty) {
          return tab.logText;
        }
      }
    }
    final buf = _spawnLogBuffers[key];
    if (buf != null && buf.isNotEmpty) {
      return buf.toString();
    }
    try {
      final f = File('${RuntimeEnvir.tmpPath}/spawn_log_$key.txt');
      if (f.existsSync()) return f.readAsStringSync();
    } catch (_) {}
    return '';
  }

  void _appendSpawnLog(String? key, String chunk) {
    if (key == null || chunk.isEmpty) return;
    final buf = _spawnLogBuffers.putIfAbsent(key, () => StringBuffer());
    final cleaned = chunk
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    buf.write(cleaned);
    if (buf.length > _maxSpawnLogChars) {
      final s = buf.toString();
      buf
        ..clear()
        ..write(s.substring(s.length - _maxSpawnLogChars));
    }
    try {
      File('${RuntimeEnvir.tmpPath}/spawn_log_$key.txt')
          .writeAsStringSync(buf.toString());
    } catch (_) {}
  }

  void _clearSpawnLog(String? key) {
    if (key == null) return;
    _spawnLogBuffers.remove(key);
    try {
      File('${RuntimeEnvir.tmpPath}/spawn_log_$key.txt').deleteSync();
    } catch (_) {}
  }

  void _setSpawnRunning(String? key, bool value) {
    if (key == null) return;
    spawnRunning[key] = value;
    spawnRevision.value++;
  }

  /// 原语: 在容器内运行一条(可长驻)命令, 流式输出到新终端 tab。
  /// key 非空时跟踪运行态 (标签活着=运行中; 命令退出或标签被关=停止)。
  Future<void> spawnContainer(
    String command, {
    String title = '容器任务',
    String? key,
    void Function()? onExit,
  }) async {
    await ensureContainerScripts();
    final marker = '__SPAWN_DONE_${DateTime.now().millisecondsSinceEpoch}__';
    final scriptPath = _writeHostScript(
      'spawn_${DateTime.now().millisecondsSinceEpoch}.sh',
      'clear\n$command\n'
          'echo $marker\n',
    );
    final tabId = await terminalTabManager.addCommandTerminalTab(
      title: title,
      command: 'source ${RuntimeEnvir.homePath}/common.sh\n'
          'install_ubuntu\n'
          'login_ubuntu ${_loginViaScript(scriptPath)}\n'
          'stty sane 2>/dev/null; stty echo 2>/dev/null\n',
      onDoneMarker: marker,
      onCommandDone: () {
        if (key != null) _spawnTabIds.remove(key);
        _setSpawnRunning(key, false);
        onExit?.call();
      },
    );
    if (key != null && tabId.isNotEmpty) _spawnTabIds[key] = tabId;
    _setSpawnRunning(key, true);
  }

  /// 停止 key 对应的 spawn (关闭其终端 tab 或后台 PTY)。
  void stopSpawn(String key) {
    final id = _spawnTabIds.remove(key);
    if (id != null) terminalTabManager.closeTabById(id);
    final cancel = _silentSpawnCancels.remove(key);
    cancel?.call();
    _setSpawnRunning(key, false);
  }

  /// 在 Ubuntu 容器内执行扁平 bash 脚本 (与手动 login_ubuntu 后执行等价)。
  /// 输出写入终端 tab 缓冲, 可通过 [spawnLog] 读取; 不跳转页面。
  Future<void> runUbuntuJob(
    String innerScript, {
    String? key,
    String title = '后台任务',
    bool longRunning = false,
    void Function()? onExit,
  }) async {
    await ensureContainerScripts();
    _clearSpawnLog(key);
    final marker = '__SPAWN_DONE_${DateTime.now().millisecondsSinceEpoch}__';
    final body = longRunning ? innerScript : '$innerScript\necho $marker\n';
    final scriptPath = _writeHostScript(
      'ubuntu_job_${DateTime.now().millisecondsSinceEpoch}.sh',
      body,
    );
    final fullCmd = 'source ${RuntimeEnvir.homePath}/common.sh\n'
        'install_ubuntu\n'
        'login_ubuntu ${_loginViaScript(scriptPath)}\n'
        'stty sane 2>/dev/null; stty echo 2>/dev/null\n';

    _setSpawnRunning(key, true);
    final tabId = await terminalTabManager.addCommandTerminalTab(
      title: title,
      command: fullCmd,
      onDoneMarker: longRunning ? null : marker,
      onCommandDone: () {
        if (key != null) _spawnTabIds.remove(key);
        _setSpawnRunning(key, false);
        onExit?.call();
      },
    );
    if (key != null && tabId.isNotEmpty) {
      _spawnTabIds[key] = tabId;
    }
  }

  @Deprecated('Use runUbuntuJob')
  Future<void> spawnBgContainer(
    String command, {
    String? key,
    String title = '后台任务',
    bool longRunning = false,
    void Function()? onExit,
  }) =>
      runUbuntuJob(
        command,
        key: key,
        title: title,
        longRunning: longRunning,
        onExit: onExit,
      );

  /// 新建一个交互式终端标签页 (进入容器 bash)。
  /// 末尾的 clear 会被喂给已进入的 ubuntu 交互 bash (而非外层容器),
  /// 从而清掉安装/登录过程的噪声, 得到干净的 root 提示符。
  Future<void> newTerminalTab() async {
    await ensureContainerScripts();
    final n = terminalTabManager.tabs.length + 1;
    final cmd = 'source ${RuntimeEnvir.homePath}/common.sh\n'
        'install_ubuntu\n'
        "login_ubuntu 'bash -il'\n"
        'stty sane 2>/dev/null; stty echo 2>/dev/null\n'
        'clear\n';
    await terminalTabManager.addCommandTerminalTab(
      title: '终端 $n',
      command: cmd,
    );
  }

  /// 供 Lua 脚本调用: 在容器内执行命令并捕获输出与退出码。
  /// 返回 { 'code': int, 'output': String }。用唯一标记框住真实输出, 过滤 PTY 回显与提示符。
  Future<Map<String, dynamic>> runShellCapture(
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    const startMark = '__EXEC_START_7f3a2b__';
    const endMark = '__EXEC_END_7f3a2b__';
    final pty = createPTY();
    final done = Completer<void>();
    final buffer = StringBuffer();
    final sub = pty.output.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        if (buffer.toString().contains('$endMark:')) {
          if (!done.isCompleted) done.complete();
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    final wrapped = 'echo $startMark; $command; echo "$endMark:\$?"';
    final execPath = _writeHostScript(
      'exec_${DateTime.now().millisecondsSinceEpoch}.sh',
      wrapped,
    );
    pty.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'install_ubuntu\n'
      'login_ubuntu ${_loginViaScript(execPath)}\n'
      'exit\n',
    );
    await done.future.timeout(timeout, onTimeout: () {});
    await sub.cancel();
    pty.kill();

    final raw = buffer.toString();
    var code = -1;
    var out = raw;
    final startIdx = raw.lastIndexOf(startMark);
    if (startIdx >= 0) {
      final afterStart = raw.substring(startIdx + startMark.length);
      final endIdx = afterStart.indexOf(endMark);
      out = endIdx >= 0 ? afterStart.substring(0, endIdx) : afterStart;
    }
    final endMatch = RegExp('$endMark:(\\d+)').firstMatch(raw);
    if (endMatch != null) code = int.tryParse(endMatch.group(1) ?? '') ?? -1;
    out = out.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '').trim();
    return {'code': code, 'output': out};
  }

  Future<void> _runUbuntuShell(String command) async {
    final pty = createPTY();
    final done = Completer<void>();
    final sub = pty.output.listen(
      (_) {},
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    pty.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'login_ubuntu ${_shellSingleQuote(command)}\n'
      'exit\n',
    );
    await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    await sub.cancel();
    pty.kill();
  }

  void onClose() {
    _ubuntuBootstrapPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(
      LifecycleObserver(
        onResume: () {},
        onPause: () {},
      ),
    );
    super.onClose();
  }
}

// 应用生命周期观察者类
class LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  final VoidCallback onPause;

  LifecycleObserver({required this.onResume, required this.onPause});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        onResume();
        break;
      case AppLifecycleState.paused:
        onPause();
        break;
      default:
        break;
    }
  }
}
