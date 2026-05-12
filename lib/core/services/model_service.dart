import 'dart:io';
import 'package:flutter/services.dart';
import '../models/hf_model.dart';

class ModelService {
  static const _channel = MethodChannel('com.finn.flux/storage');

  // Flux lineup via flutter_gemma / LiteRT-LM
  static final List<HFModel> _allModels = [
    HFModel(
      id: 'flux-lite-gemma3-1b',
      name: 'Flux Lite',
      baseModel: 'Gemma 3 1B',
      description: 'Lightweight Gemma 3 model with INT4 quantization. Fast on-device inference.',
      sizeMB: 650,
      requiredRAM: 2,
      speed: 4.5,
      quality: 3.0,
      capabilities: ['chat'],
      modelType: 'gemma4',
      fileType: 'litertlm',
      downloadFilename: 'gemma3-1b-it-int4.litertlm',
    ),
    HFModel(
      id: 'flux-steady-gemma4-e2b',
      name: 'Flux Steady',
      baseModel: 'Gemma 4 E2B',
      description: 'Next-gen multimodal model with balanced performance. Supports vision, audio, function calling, and thinking mode.',
      sizeMB: 2458,
      requiredRAM: 5,
      speed: 4.2,
      quality: 4.6,
      capabilities: ['chat', 'reasoning', 'vision', 'multimodal'],
      modelType: 'gemma4',
      fileType: 'litertlm',
      downloadFilename: 'gemma-4-E2B-it.litertlm',
    ),
    HFModel(
      id: 'flux-smart-gemma4-e4b',
      name: 'Flux Smart',
      baseModel: 'Gemma 4 E4B',
      description: 'High-performance flagship model. Excels at complex problem solving, creative writing, deep analysis, vision, and audio.',
      sizeMB: 4403,
      requiredRAM: 7,
      speed: 3.5,
      quality: 5.0,
      capabilities: ['chat', 'expert', 'reasoning', 'creative', 'vision', 'multimodal'],
      modelType: 'gemma4',
      fileType: 'litertlm',
      downloadFilename: 'gemma-4-E4B-it.litertlm',
    ),
  ];

  static Future<int> getDeviceRAM() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _getDesktopRAM();
    }
    try {
      final memoryBytes = await _channel.invokeMethod<int>('getDeviceRAM');
      if (memoryBytes == null || memoryBytes <= 0) return 4;
      return (memoryBytes / (1024 * 1024 * 1024)).round();
    } on PlatformException {
      return 4;
    } catch (_) {
      return 4;
    }
  }

  static int _getDesktopRAM() {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final result = Process.runSync('sysctl', ['-n', 'hw.memsize']);
        if (result.exitCode == 0) {
          final bytes = int.parse(result.stdout.toString().trim());
          return (bytes / (1024 * 1024 * 1024)).round();
        }
      }
      if (Platform.isLinux) {
        final result = Process.runSync('free', ['-b']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length > 1) {
              final bytes = int.tryParse(parts[1]);
              if (bytes != null) return (bytes / (1024 * 1024 * 1024)).round();
            }
          }
        }
      }
      if (Platform.isWindows) {
        final result = Process.runSync('powershell', [
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory'
        ]);
        if (result.exitCode == 0) {
          final bytes = int.tryParse(result.stdout.toString().trim());
          if (bytes != null) return (bytes / (1024 * 1024 * 1024)).round();
        }
      }
    } catch (_) {}
    return 16;
  }

  static Future<Map<String, int>> getStorageSpace() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await _channel.invokeMethod('getStorageSpace');
        final total = (result['total'] as int);
        final free = (result['free'] as int);
        return {'total': total, 'free': free};
      } catch (_) {
        return {'total': 0, 'free': 0};
      }
    }
    return _getDesktopStorage();
  }

  static Map<String, int> _getDesktopStorage() {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '/';
        final result = Process.runSync('df', ['-B1', home]);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final total = int.tryParse(parts[1]);
              final used = int.tryParse(parts[2]);
              final avail = int.tryParse(parts[3]);
              if (total != null && avail != null) {
                return {'total': total, 'free': avail};
              }
              if (total != null && used != null) {
                return {'total': total, 'free': total - used};
              }
            }
          }
        }
      }
      if (Platform.isWindows) {
        final result = Process.runSync('powershell', [
          '-Command',
          r"Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | ForEach-Object { '{0} {1}' -f $_.FreeSpace, $_.Size }"
        ]);
        if (result.exitCode == 0) {
          final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final free = int.tryParse(parts[0]);
            final total = int.tryParse(parts[1]);
            if (total != null && free != null) {
              return {'total': total, 'free': free};
            }
          }
        }
      }
    } catch (_) {}
    return {'total': 0, 'free': 0};
  }

  /// Get models available for the device's RAM
  /// 2GB: Flux Lite (Gemma 3 1B)
  /// 5GB: + Flux Steady (Gemma 4 E2B)
  /// 7GB+: + Flux Smart (Gemma 4 E4B)
  static Future<List<HFModel>> getAvailableModels() async {
    // Desktop always has enough RAM for these small models;
    // filtering is only relevant on mobile.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return List.from(_allModels);
    }
    final ram = await getDeviceRAM();
    return _allModels.where((m) => m.requiredRAM <= ram).toList();
  }

  /// Alias for getAvailableModels - used by UI components
  static Future<List<HFModel>> getRecommendedModels() async {
    return getAvailableModels();
  }

  /// Get all models (for settings/models page)
  static List<HFModel> getAllModels() => List.from(_allModels);

  static String getDownloadUrl(String modelId) {
    switch (modelId) {
      case 'flux-lite-gemma3-1b':
        return 'https://huggingface.co/On-device/Gemma3-1B-IT-litert-lm/resolve/main/gemma3-1b-it-int4.litertlm';
      case 'flux-steady-gemma4-e2b':
        return 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
      case 'flux-smart-gemma4-e4b':
        return 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm';
      default:
        return '';
    }
  }

  /// Whether the model requires a HuggingFace auth token to download
  static bool modelNeedsAuth(String modelId) => false;
}
