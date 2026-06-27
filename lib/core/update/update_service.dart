import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Lightweight GitHub release update checker.
///
/// Queries the public GitHub Releases API once per session
/// and shows an [AlertDialog] when a newer version is available.
/// Returns [UpdateCheckResult] with a descriptive message for
/// every outcome including network and parse failures.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _repoOwner = 'hardikbansal31';
  static const String _repoName = 'sheep';
  static const String _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _releasesUrl =
      'https://github.com/$_repoOwner/$_repoName/releases/latest';

  /// Whether we have already shown (or attempted) the startup check.
  bool _hasCheckedThisSession = false;

  // ─── Public API ──────────────────────────────────────────────

  /// Called once at app startup. Silently returns on any failure.
  Future<void> checkOnStartup(BuildContext context) async {
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;
    await _check(context);
  }

  /// Manually triggered from Settings. Returns a user-facing result.
  Future<UpdateCheckResult> checkManually(BuildContext context) async {
    return _check(context);
  }

  // ─── Internals ───────────────────────────────────────────────

  Future<UpdateCheckResult> _check(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // e.g. "1.1.0"

      final http.Response response;
      try {
        response = await http
            .get(
              Uri.parse(_apiUrl),
              headers: {'Accept': 'application/vnd.github.v3+json'},
            )
            .timeout(const Duration(seconds: 8));
      } on SocketException {
        return const UpdateCheckResult.error('No internet connection.');
      } on TimeoutException {
        return const UpdateCheckResult.error('Request timed out. Try again later.');
      }

      if (response.statusCode == 404) {
        return const UpdateCheckResult.error('No releases found (404).');
      }
      if (response.statusCode == 403) {
        return const UpdateCheckResult.error('GitHub API rate limit exceeded. Try again later.');
      }
      if (response.statusCode != 200) {
        return UpdateCheckResult.error('Failed to fetch updates (HTTP ${response.statusCode}).');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      final remoteVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      final releaseNotes = (data['body'] as String?) ?? '';

      if (remoteVersion.isEmpty) {
        return const UpdateCheckResult.error('Could not parse release version.');
      }

      if (_isNewer(remoteVersion, localVersion)) {
        if (!context.mounted) {
          return UpdateCheckResult.updateAvailable('Sheep v$remoteVersion is available.');
        }
        _showUpdateDialog(context, remoteVersion, releaseNotes);
        return UpdateCheckResult.updateAvailable('Sheep v$remoteVersion is available.');
      }

      return UpdateCheckResult.upToDate('You\'re on the latest version (v$localVersion).');
    } on FormatException {
      return const UpdateCheckResult.error('Invalid response from server.');
    } catch (e) {
      return UpdateCheckResult.error('Update check failed: $e');
    }
  }

  /// Simple semver comparison: returns `true` when [remote] > [local].
  bool _isNewer(String remote, String local) {
    final r = _parseSemver(remote);
    final l = _parseSemver(local);

    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  List<int> _parseSemver(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }

  void _showUpdateDialog(BuildContext context, String version, String notes) {
    final colors = AppTheme.colorsOf(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Update Available',
          style: TextStyle(color: colors.inkPrimary, fontWeight: FontWeight.w600),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sheep v$version is available.',
                style: TextStyle(color: colors.inkPrimary, fontSize: 14),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'What\'s new:',
                  style: TextStyle(
                    color: colors.inkSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      notes,
                      style: TextStyle(color: colors.inkSecondary, fontSize: 12, height: 1.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Later', style: TextStyle(color: colors.inkSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(Uri.parse(_releasesUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}

enum UpdateCheckStatus { upToDate, updateAvailable, error }

class UpdateCheckResult {
  const UpdateCheckResult.upToDate(this.message) : status = UpdateCheckStatus.upToDate;
  const UpdateCheckResult.updateAvailable(this.message) : status = UpdateCheckStatus.updateAvailable;
  const UpdateCheckResult.error(this.message) : status = UpdateCheckStatus.error;

  final UpdateCheckStatus status;
  final String message;
}
