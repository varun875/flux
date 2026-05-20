import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  final Queue<_TtsTask> _queue = Queue<_TtsTask>();
  bool _isSpeaking = false;
  bool _muted = false;
  Completer<void>? _currentCompleter;

  bool get isSpeaking => _isSpeaking;

  Future<void> _init() async {
    try {
      print("TTS: Initializing...");
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      
      final languages = await _tts.getLanguages;
      print("TTS: Available languages: $languages");
      
      await _tts.setLanguage("en-US");
      await _tts.awaitSpeakCompletion(true);
      
      _tts.setCompletionHandler(() {
        print("TTS: Speech completed");
        _isSpeaking = false;
        _currentCompleter?.complete();
        _currentCompleter = null;
        _remuteMusicIfNeeded();
        _processQueue();
      });

      _tts.setCancelHandler(() {
        print("TTS: Speech cancelled");
        _isSpeaking = false;
        _currentCompleter?.complete();
        _currentCompleter = null;
        _remuteMusicIfNeeded();
      });

      _tts.setErrorHandler((msg) {
        print("TTS: Speech error: $msg");
        _isSpeaking = false;
        _currentCompleter?.completeError(msg);
        _currentCompleter = null;
        _remuteMusicIfNeeded();
        _processQueue();
      });
      print("TTS: Initialization complete");
    } catch (e) {
      print("TTS Init Error: $e");
    }
  }

  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      stop();
    }
  }

  Future<void> speak(String text) async {
    if (_muted || text.isEmpty) return;
    
    final completer = Completer<void>();
    _queue.add(_TtsTask(text, completer));
    
    if (!_isSpeaking) {
      _processQueue();
    }
    
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty || _isSpeaking || _muted) {
      if (_queue.isEmpty && !_isSpeaking) {
        _remuteMusicIfNeeded();
      }
      return;
    }

    _isSpeaking = true;
    final task = _queue.removeFirst();
    _currentCompleter = task.completer;
    
    try {
      // Ensure music is unmuted so user can hear TTS
      await _unmuteMusic();
      
      print("TTS: Speaking: ${task.text}");
      await _tts.speak(task.text);
    } catch (e) {
      _isSpeaking = false;
      task.completer.completeError(e);
      _processQueue();
    }
  }

  bool enableAutoMute = false;

  Future<void> _unmuteMusic() async {
    try {
      // Small delay to ensure STT start beeps (if any remain) are finished while music is still muted
      await Future.delayed(const Duration(milliseconds: 1000));
      const channel = MethodChannel('com.finn.flux/storage');
      await channel.invokeMethod('unmuteMusicStream');
    } catch (_) {}
  }

  Future<void> _remuteMusicIfNeeded() async {
    if (!enableAutoMute) return;
    try {
      const channel = MethodChannel('com.finn.flux/storage');
      await channel.invokeMethod('muteMusicStream');
    } catch (_) {}
  }

  Future<void> stop() async {
    _queue.clear();
    _isSpeaking = false;
    await _tts.stop();
    _currentCompleter?.complete();
    _currentCompleter = null;
  }
}

class _TtsTask {
  final String text;
  final Completer<void> completer;
  _TtsTask(this.text, this.completer);
}
