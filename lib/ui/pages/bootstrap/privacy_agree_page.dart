import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// 首次启动隐私政策同意页 (加载 assets/privacy_policy.md, 与设置页同源)。
class PrivacyAgreePage extends StatefulWidget {
  const PrivacyAgreePage({
    super.key,
    required this.onAgreeTap,
  });

  final VoidCallback onAgreeTap;

  @override
  State<PrivacyAgreePage> createState() => _PrivacyAgreePageState();
}

class _PrivacyAgreePageState extends State<PrivacyAgreePage> {
  String? _content;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/privacy_policy.md').then((value) {
      if (mounted) setState(() => _content = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('MK-BOT 隐私政策与用户协议'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Markdown(
              selectable: true,
              data: _content ?? '加载协议中…',
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                    ),
                    child: const Text('我不同意'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.onAgreeTap,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const RoundedRectangleBorder(),
                    ),
                    child: const Text('同意并继续'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
