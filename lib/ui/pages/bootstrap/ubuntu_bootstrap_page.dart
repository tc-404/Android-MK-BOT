import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart' hide PrivacyAgreePage;
import 'package:settings/settings.dart';

import '../../../core/constants/scripts.dart';
import '../../controllers/terminal_controller.dart';
import '../../routes/app_routes.dart';
import '../../widgets/ubuntu_bootstrap_overlay.dart';
import 'privacy_agree_page.dart';

/// 应用启动首屏: 检查 / 安装 Ubuntu rootfs, 完成后再进入主界面。
class UbuntuBootstrapPage extends StatefulWidget {
  const UbuntuBootstrapPage({super.key});

  @override
  State<UbuntuBootstrapPage> createState() => _UbuntuBootstrapPageState();
}

class _UbuntuBootstrapPageState extends State<UbuntuBootstrapPage> {
  late final HomeController _home;
  bool _checking = true;
  String _status = '正在检查 Ubuntu 环境…';

  @override
  void initState() {
    super.initState();
    _home = Get.put(HomeController());
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _ensurePrivacy() async {
    final privacy = 'privacy'.setting;
    if (privacy.get() != null) return;
    await Get.to(PrivacyAgreePage(
      onAgreeTap: () {
        privacy.set(true);
        Get.back();
      },
    ));
  }

  Future<void> _run() async {
    try {
      await _ensurePrivacy();
      if (!mounted) return;

      if (isUbuntuInstalled()) {
        Log.i('Ubuntu 已就绪, 进入主界面', tag: 'Bootstrap');
        _home.ubuntuBootstrapActive.value = false;
        Get.offAllNamed(AppRoutes.main);
        return;
      }

      setState(() {
        _checking = false;
        _status = '首次启动, 正在安装 Ubuntu 容器…';
      });

      Log.i('Ubuntu 未安装, 开始自动安装', tag: 'Bootstrap');
      final ok = await _home.bootstrapUbuntu(installOnly: true);
      if (!mounted) return;

      if (ok || isUbuntuInstalled()) {
        _home.ubuntuBootstrapActive.value = false;
        Get.offAllNamed(AppRoutes.main);
      } else {
        setState(() {
          _status = '安装未完成, 3 秒后重试…';
        });
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) _run();
      }
    } catch (e, st) {
      Log.e('Bootstrap 失败: $e\n$st', tag: 'Bootstrap');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _status = '安装出错: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE3F2FD), Color(0xFFFCE4EC), Color(0xFFE8F5E9)],
              ),
            ),
          ),
          if (_checking)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_status, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            )
          else
            Obx(() {
              if (_home.ubuntuBootstrapActive.value) {
                return UbuntuBootstrapView(
                  controller: _home,
                  alwaysVisible: true,
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(_status, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _run,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
