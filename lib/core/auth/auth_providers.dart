import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'lock_service.dart';

/// The IDs of items (sections or pages) that have been authenticated in this session.
class UnlockedSessionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void add(String id) {
    state = {...state, id};
  }

  void clear() {
    state = {};
  }
}

final unlockedSessionProvider = NotifierProvider<UnlockedSessionNotifier, Set<String>>(() {
  return UnlockedSessionNotifier();
});

/// Provides the lock service for authenticating via biometrics/PIN.
final lockServiceProvider = Provider<LockService>((ref) {
  final repository = ref.watch(repositoryProvider);
  return LockService(
    repository: repository,
    onUnlock: (id) {
      ref.read(unlockedSessionProvider.notifier).add(id);
    },
  );
});

/// Clears the unlocked session when the app goes to the background.
final sessionLifecycleProvider = Provider<void>((ref) {
  final listener = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
        ref.read(unlockedSessionProvider.notifier).clear();
      }
    },
  );
  ref.onDispose(() => listener.dispose());
});
