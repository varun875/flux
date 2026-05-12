import 'dart:io';
import 'package:flutter/services.dart';
import '../models/hf_model.dart';

class ModelService {
  static const _channel = MethodChannel('com.finn.flux/storage');

  // Flux lineup with Qwen 3.5 models (Unsloth GGUF quantizations)
  static final List<HFModel> _allModels = [
    HFModel(
      id: 'flux-lite-qwen-3.5-0.8b',
      name: 'Flux Lite',
      baseModel: 'Qwen 3.5 0.8B',
      description: 'Ultra-lightweight model for basic assistance and fast chat. Perfect for devices with limited RAM.',
      sizeMB: 533,
      requiredRAM: 4,
      speed: 5.0,
      quality: 4.0,
      capabilities: ['chat', 'speed', 'low-ram'],
    ),
    HFModel(
      id: 'flux-steady-qwen-3.5-2b',
      name: 'Flux Steady',
      baseModel: 'Qwen 3.5 2B',
      description: 'Balanced performance with enhanced reasoning. Ideal for complex instructions and structured tasks.',
      sizeMB: 1280,
      requiredRAM: 6,
      speed: 4.2,
      quality: 4.6,
      capabilities: ['chat', 'reasoning', 'balanced'],
    ),
    HFModel(
      id: 'flux-smart-qwen-3.5-4b',
      name: 'Flux Smart',
      baseModel: 'Qwen 3.5 4B',
      description: 'High-performance flagship model. Excels at complex problem solving, creative writing, and deep analysis.',
      sizeMB: 2740,
      requiredRAM: 8,
      speed: 3.5,
      quality: 5.0,
      capabilities: ['chat', 'expert', 'reasoning', 'creative'],
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
  /// 4GB: Only Flux Lite
  /// 6GB: Flux Lite + Steady
  /// 8GB+: All three
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
      case 'flux-lite-qwen-3.5-0.8b':
        return 'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf';
      case 'flux-steady-qwen-3.5-2b':
        return 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf';
      case 'flux-smart-qwen-3.5-4b':
        return 'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf';
      default:
        return '';
    }
  }
}
