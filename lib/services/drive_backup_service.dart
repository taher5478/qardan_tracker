import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'backup_service.dart';
import 'entitlement.dart';
import 'settings_service.dart';

/// Uploads JSON backups to a visible "OweMe Backups" folder in the user's
/// Google Drive. Uses the drive.file scope (the app can only see files it
/// created), so it never touches the rest of the user's Drive.
class DriveBackupService {
  static const _folderName = 'OweMe Backups';

  final GoogleSignIn _googleSignIn =
      GoogleSignIn(scopes: const [drive.DriveApi.driveFileScope]);

  /// Interactive sign-in. Returns the connected account email, or null if the
  /// user cancelled or it failed.
  Future<String?> connect() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    await AppSettings.instance.setDriveBackup(true, account.email);
    return account.email;
  }

  Future<void> disconnect() async {
    await _googleSignIn.signOut();
    await AppSettings.instance.setDriveBackup(false, null);
  }

  Future<GoogleSignInAccount?> _ensureSignedIn() async =>
      _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();

  /// Upload a fresh backup now. Returns true on success.
  Future<bool> backupNow() async {
    final account = await _ensureSignedIn();
    if (account == null) return false;

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return false;

    try {
      final api = drive.DriveApi(client);
      final folderId = await _findOrCreateFolder(api);

      final json = await BackupService().buildBackupJson();
      final bytes = utf8.encode(json);
      final media = drive.Media(Stream.value(bytes), bytes.length);
      final file = drive.File()
        ..name = BackupService().backupFileName()
        ..parents = [folderId];

      await api.files.create(file, uploadMedia: media);
      await AppSettings.instance.setLastDriveBackup(DateTime.now());
      return true;
    } finally {
      client.close();
    }
  }

  /// Download the most recent backup from Drive and restore it. Returns a
  /// human-readable result; never throws.
  Future<String> restoreLatest() async {
    final account = await _ensureSignedIn();
    if (account == null) return 'Connect Google Drive first';

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return 'Google sign-in expired — reconnect';

    try {
      final api = drive.DriveApi(client);
      final res = await api.files.list(
        q: "name contains 'oweme_backup' and trashed=false",
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id,name)',
        pageSize: 1,
      );
      final files = res.files;
      if (files == null || files.isEmpty) {
        return 'No backup found in Google Drive';
      }

      final media = await api.files.get(
        files.first.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return BackupService().restoreFromContent(utf8.decode(bytes));
    } catch (_) {
      return 'Couldn’t restore from Google Drive';
    } finally {
      client.close();
    }
  }

  Future<String> _findOrCreateFolder(drive.DriveApi api) async {
    final res = await api.files.list(
      q: "name='$_folderName' and "
          "mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final existing = res.files;
    if (existing != null && existing.isNotEmpty) return existing.first.id!;

    final folder = drive.File()
      ..name = _folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(folder);
    return created.id!;
  }

  /// Auto-backup if enabled and more than 24h have passed. Best-effort: never
  /// throws (so it's safe to call on app launch and in the background sweep).
  Future<void> maybeDailyBackup() async {
    final s = AppSettings.instance;
    // Backup is a paid feature — never run during the free trial.
    if (!Entitlement.isLicensed) return;
    if (!s.driveBackupEnabled) return;
    final last = s.lastDriveBackup;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    try {
      await backupNow();
    } catch (_) {
      // Best-effort; the on-open path will catch up next time.
    }
  }
}
