import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:storage_repository/constants/_all.dart';
import 'package:storage_repository/implementations/storage_repository_impl.dart';
import 'package:storage_repository/interfaces/storage_repository.dart';

/// A secure implementation of [StorageRepository].
///
/// This implementation is designed to securely persist sensitive data,
/// such as user authentication tokens. It leverages `FlutterSecureStorage`
/// for securely storing encryption keys and `Hive` for encrypted storage.
class SecureStorageRepositoryImpl extends StorageRepositoryImpl
    implements StorageRepository {
  /// Instance of `FlutterSecureStorage` used to securely store encryption keys.
  final FlutterSecureStorage flutterSecureStorage = FlutterSecureStorage();

  /// Constructor for `SecureStorageRepositoryImpl`.
  ///
  /// - [key]: The key used to access the secure storage box.
  /// - [logPrefix]: A prefix for log messages related to secure storage operations.
  SecureStorageRepositoryImpl({
    super.key = StorageRepositoryKeys.defaultSecureBoxKey,
    super.logPrefix =
        StorageRepositoryKeys.defaultSecureStorageRepositoryImplLogPrefix,
  });

  /// Initializes the secure storage repository.
  ///
  /// This method should be called as early as possible in the application lifecycle.
  /// It ensures that a secure encryption key is generated and stored securely.
  ///
  /// - If an encryption key does not exist, it generates a new one.
  /// - If an error occurs while reading the encryption key, it clears secure storage.
  ///
  /// Returns an instance of [StorageRepository] once initialization is complete.
  @override
  Future<StorageRepository> init() async {
    final encryptionKeyStorageKey = StorageRepositoryKeys.encryptionKey;

    var containsEncryptionKey = false;

    try {
      // Check if an encryption key already exists in secure storage.
      containsEncryptionKey =
          await flutterSecureStorage.read(key: encryptionKeyStorageKey) != null;
    } on PlatformException catch (_) {
      // If there's an error accessing secure storage, clear all stored data.
      await flutterSecureStorage.deleteAll();
    }

    // If no encryption key exists, generate a new one and store it securely.
    if (!containsEncryptionKey) {
      final secureEncryptionKey = base64UrlEncode(generateSecureKey());
      await flutterSecureStorage.write(
          key: encryptionKeyStorageKey, value: secureEncryptionKey);
    }

    // Retrieve the encryption key for Hive storage.
    final encryptionKeyValue =
        await flutterSecureStorage.read(key: encryptionKeyStorageKey) ?? '';

    // Open a Hive box with encryption using Hive.compute().
    final result = await Hive.compute(() async {
      try {
        // Open the encrypted box with the encryption key
        return Hive.box(name: key, encryptionKey: encryptionKeyValue);
      } catch (e) {
        // If opening fails, try to delete the corrupted box and retry
        try {
          final boxToDelete = Hive.box(name: key);
          boxToDelete.deleteFromDisk();
        } catch (_) {
          // Ignore deletion errors
        }

        // Retry opening the box
        return Hive.box(name: key, encryptionKey: encryptionKeyValue);
      }
    });

    storage = result;
    return this;
  }

  /// Generates a strong 32-byte (256-bit) encryption key for secure storage.
  ///
  /// This method uses Dart's cryptographically secure random number generator
  /// to create a proper AES-256 encryption key.
  static List<int> generateSecureKey() {
    // Generate 32 cryptographically secure random bytes for AES-256
    final secureRandom = Random.secure();
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = secureRandom.nextInt(256);
    }
    return key;
  }

  /// Returns the stored data as a formatted string.
  ///
  /// This method is primarily for debugging purposes, allowing developers
  /// to inspect the stored data in a readable format.
  ///
  /// Example output:
  /// ```
  /// ----------------------------------------------------------------------------------------
  /// Secure storage repository data:
  /// ----------------------------------------------------------------------------------------
  ///
  /// key1: value1
  /// key2: value2
  ///
  /// ----------------------------------------------------------------------------------------
  /// ```
  @override
  Future<String> asString() async {
    final StringBuffer stringBuffer = StringBuffer();

    stringBuffer.write(
        '\n----------------------------------------------------------------------------------------');
    stringBuffer.write('\n$logPrefix repository data:');
    stringBuffer.write(
        '\n----------------------------------------------------------------------------------------');

    // Retrieve all stored key-value pairs and format them for output.
    (await getAll())
        .forEach((key, value) => stringBuffer.write('\n\n$key: $value'));

    stringBuffer.write(
        '\n----------------------------------------------------------------------------------------');

    return stringBuffer.toString();
  }
}
