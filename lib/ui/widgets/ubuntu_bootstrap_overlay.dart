import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/terminal_controller.dart';
import 'glass_panel.dart';

/// Ubuntu 安装进度 UI (可用于全屏启动页或主界面遮罩).
class UbuntuBootstrapView extends StatelessWidget {
  const UbuntuBootstrapView({
    super.key,
    required this.controller,
    this.alwaysVisible = false,
  });

  final HomeController controller;
  final bool alwaysVisible;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!alwaysVisible && !controller.ubuntuBootstrapActive.value) {
        return const SizedBox.shrink();
      }

      final progress = controller.ubuntuBootstrapProgress.value;
      final message = controller.ubuntuBootstrapMessage.value;
      final log = controller.ubuntuBootstrapLog.value;
      final logLines = log
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final tail = logLines.length > 8
          ? logLines.sublist(logLines.length - 8)
          : logLines;

      return Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GlassPanel(
                  padding: const EdgeInsets.all(20),
                  opacity: 0.92,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '正在安装 Ubuntu 系统',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '首次启动需解压 Ubuntu 容器, 请保持应用在前台。部分设备可能需要 15–30 分钟。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: progress > 0.01 && progress < 1.0
                              ? progress
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message.isEmpty ? '准备中…' : message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (tail.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          '终端输出',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: SelectableText(
                              tail.join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.35,
                                color: Color(0xFFE0E0E0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 主界面上的全屏遮罩 (安装进行中时叠加).
class UbuntuBootstrapOverlay extends StatelessWidget {
  const UbuntuBootstrapOverlay({super.key, required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return UbuntuBootstrapView(controller: controller);
  }
}
