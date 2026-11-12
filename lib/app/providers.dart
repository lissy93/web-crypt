import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/services/file_service.dart';
import 'package:web_crypt/services/storage_service.dart';

/// overridden in main() once preferences have loaded, and in tests with a fake
final storageServiceProvider = Provider<StorageService>(
  (ref) =>
      throw UnimplementedError('storageServiceProvider was not overridden'),
);

final cryptoServiceProvider = Provider<CryptoService>(
  (ref) => const CryptoService(),
);

final fileServiceProvider = Provider<FileService>((ref) => const FileService());

final themeChoiceProvider = NotifierProvider<ThemeChoiceNotifier, ThemeChoice>(
  ThemeChoiceNotifier.new,
);

class ThemeChoiceNotifier extends Notifier<ThemeChoice> {
  @override
  ThemeChoice build() => ref.read(storageServiceProvider).theme;

  Future<void> set(ThemeChoice choice) async {
    state = choice;
    await ref.read(storageServiceProvider).setTheme(choice);
  }
}

/// a file the OS opened the app with, held until Decrypt takes it
final openedFileProvider = NotifierProvider<OpenedFile, PickedFile?>(
  OpenedFile.new,
);

class OpenedFile extends Notifier<PickedFile?> {
  @override
  PickedFile? build() => null;

  void open(PickedFile file) => state = file;

  PickedFile? take() {
    final file = state;
    state = null;
    return file;
  }
}
