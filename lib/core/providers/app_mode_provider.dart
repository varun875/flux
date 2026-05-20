import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppMode { flux, fluxCode }

final appModeProvider = StateProvider<AppMode>((ref) => AppMode.flux);
