import 'dart:io';

import 'package:flutter/services.dart';

/// 大体积 Flutter asset 流式复制 (Android 原生, 避免整包读入 Dart 堆内存)。
class AssetCopy {
  AssetCopy._();

  static const MethodChannel _channel = MethodChannel('sandbox_channel');

  static Future<int> copyFlutterAsset(String asset, String destPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('AssetCopy 仅支持 Android');
    }
    final n = await _channel.invokeMethod<int>('copy_asset', {
      'asset': asset,
      'dest': destPath,
    });
    return n ?? 0;
  }
}
