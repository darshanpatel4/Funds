import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../utils/format.dart';

// ----------------------------------------------------------- encryption

/// Password protection for backup files: AES-256-GCM with a key made from
/// the password by PBKDF2-SHA256. The result is still a small JSON file.
class BackupCrypto {
  BackupCrypto._();

  static const format = 'funds-backup-encrypted';
  static const _iterations = 120000;

  static bool isEncrypted(String text) {
    try {
      final d = jsonDecode(text);
      return d is Map && d['format'] == format;
    } catch (_) {
      return false;
    }
  }

  /// Runs on a background isolate so the screen does not freeze.
  static Future<String> encrypt(String plain, String password) =>
      Isolate.run(() => _encrypt(plain, password));

  /// Throws [FormatException] for a wrong password or a damaged file.
  static Future<String> decrypt(String text, String password) =>
      Isolate.run(() => _decrypt(text, password));

  static Pbkdf2 _kdf(int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  static Future<String> _encrypt(String plain, String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _kdf(_iterations).deriveKeyFromPassword(password: password, nonce: salt);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(plain), secretKey: key);
    return jsonEncode({
      'format': format,
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    });
  }

  static Future<String> _decrypt(String text, String password) async {
    Map d;
    try {
      d = jsonDecode(text) as Map;
    } catch (_) {
      throw const FormatException('The backup file is damaged.');
    }
    try {
      final key = await _kdf(d['iterations'] as int)
          .deriveKeyFromPassword(password: password, nonce: base64Decode(d['salt'] as String));
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(d['data'] as String),
          nonce: base64Decode(d['nonce'] as String),
          mac: Mac(base64Decode(d['mac'] as String)),
        ),
        secretKey: key,
      );
      return utf8.decode(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong password.');
    } catch (_) {
      throw const FormatException('The backup file is damaged.');
    }
  }
}

// ------------------------------------------------------------ downloads

/// A backup file saved in Downloads/Funds.
class SavedBackup {
  final String uri;
  final String name;
  final DateTime added;

  const SavedBackup(this.uri, this.name, this.added);
}

/// Files in the phone's Downloads/Funds folder (Android 10+). They stay
/// even if the app is uninstalled.
class Downloads {
  Downloads._();

  static const _channel = MethodChannel('funds/downloads');
  static const prefix = 'funds-backup-';

  static Future<bool> supported() async {
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(String name, String text) =>
      _channel.invokeMethod<String>('save', {'name': name, 'bytes': utf8.encode(text)});

  /// Saves any file (a PDF or Excel report) to Downloads/Funds.
  static Future<void> saveFile(String name, List<int> bytes, String mime) =>
      _channel.invokeMethod<String>(
          'save', {'name': name, 'bytes': Uint8List.fromList(bytes), 'mime': mime});

  /// This app's backups, newest first.
  static Future<List<SavedBackup>> list() async {
    final rows = await _channel.invokeListMethod<Map>('list', {'prefix': prefix}) ?? const [];
    return [
      for (final r in rows)
        SavedBackup(
          r['uri'] as String,
          r['name'] as String,
          DateTime.fromMillisecondsSinceEpoch(((r['added'] as num?) ?? 0).toInt() * 1000),
        ),
    ];
  }

  static Future<void> delete(String uri) => _channel.invokeMethod('delete', {'uri': uri});
}

// --------------------------------------------------------------- backups

class BackupService {
  BackupService._();

  static const keepCopies = 5;
  static bool _running = false;

  /// The backup text, password-protected when a password is set.
  static Future<String> buildText(AppState s) async {
    final json = await s.exportJson();
    final pw = s.backupPassword;
    return pw == null ? json : BackupCrypto.encrypt(json, pw);
  }

  static String fileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${Downloads.prefix}${dayKey(now)}-${two(now.hour)}${two(now.minute)}.json';
  }

  /// Saves a backup to Downloads/Funds and keeps only the newest copies.
  static Future<void> saveToDownloads(AppState s) async {
    final now = DateTime.now();
    await Downloads.save(fileName(now), await buildText(s));
    await s.setSetting('last_auto_backup', '${now.millisecondsSinceEpoch}');
    await s.setSetting('auto_backup_error', '');
    await s.markBackedUp();
    try {
      final files = await Downloads.list();
      for (final f in files.skip(keepCopies)) {
        await Downloads.delete(f.uri);
      }
    } catch (_) {
      // Old copies from before a reinstall can't be removed; that's fine.
    }
  }

  /// Called when the app opens or comes back: backs up if one is due.
  static Future<void> autoBackupIfDue(AppState s) async {
    if (_running || !s.autoBackup || !s.autoBackupDue) return;
    if (!await Downloads.supported()) return;
    _running = true;
    try {
      await saveToDownloads(s);
    } catch (e) {
      await s.setSetting('auto_backup_error', 'Could not save the backup ($e).');
    } finally {
      _running = false;
    }
  }

  /// Turns a picked file into backup tables, asking for the password when
  /// the file is protected. Throws [FormatException] with a readable message.
  static Future<Map<String, List<Map<String, Object?>>>> read(
    String text,
    Future<String?> Function() askPassword,
  ) async {
    var plain = text;
    if (BackupCrypto.isEncrypted(text)) {
      final pw = await askPassword();
      if (pw == null) throw const FormatException('Import cancelled.');
      plain = await BackupCrypto.decrypt(text, pw);
    }
    return AppState.parseBackup(plain);
  }
}
