import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

import '../database/repository.dart';

class LockService {
  LockService({
    required this.repository,
    required this.onUnlock,
  });

  final SheepRepository repository;
  final void Function(String id) onUnlock;
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool get isMobile => Platform.isIOS || Platform.isAndroid;

  Future<bool> authenticateMobile() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!isAvailable) return false;

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock protected note',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  Future<bool> authenticateDesktop(String pin) async {
    final storedHash = await repository.getLockPinHash();
    final storedSalt = await repository.getLockPinSalt();

    if (storedHash == null || storedSalt == null) return false;

    final bytes = utf8.encode(pin + storedSalt);
    final digest = sha256.convert(bytes).toString();

    return digest == storedHash;
  }

  Future<void> setupDesktopPin(String pin) async {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    final salt = base64Url.encode(values);

    final bytes = utf8.encode(pin + salt);
    final digest = sha256.convert(bytes).toString();

    await repository.setLockPinSalt(salt);
    await repository.setLockPinHash(digest);
  }

  Future<bool> isDesktopPinSetup() async {
    final hash = await repository.getLockPinHash();
    return hash != null && hash.isNotEmpty;
  }

  void unlockItem(String id) {
    onUnlock(id);
  }
}
