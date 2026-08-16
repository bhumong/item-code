// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'Pencarian OCR';

  @override
  String get signInWithGoogle => 'Masuk dengan Google';

  @override
  String get signInFailed => 'Gagal masuk. Silakan coba lagi.';

  @override
  String get searchDocumentsHint => 'Cari dokumen...';

  @override
  String get noDocumentsYet => 'Belum ada dokumen. Ketuk + untuk membuat.';

  @override
  String get newDocument => 'Dokumen Baru';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'halaman',
      one: 'halaman',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadDocuments(String error) {
    return 'Gagal memuat dokumen: $error';
  }

  @override
  String get documentTitle => 'Dokumen';

  @override
  String get editTitle => 'Ubah judul';

  @override
  String get uploadImage => 'Unggah Gambar';

  @override
  String get uploadFromCamera => 'Unggah dari Kamera';

  @override
  String uploadingProgress(int done, int total) {
    return 'Mengunggah $done/$total...';
  }

  @override
  String failedToLoadPages(String error) {
    return 'Gagal memuat halaman: $error';
  }

  @override
  String get noPagesYet => 'Belum ada halaman. Gunakan Unggah Gambar.';

  @override
  String get renameDocument => 'Ubah Nama Dokumen';

  @override
  String get titleLabel => 'Judul';

  @override
  String get cancel => 'Batal';

  @override
  String get save => 'Simpan';

  @override
  String get create => 'Buat';

  @override
  String get statusPending => 'Menunggu';

  @override
  String get statusProcessing => 'Diproses';

  @override
  String get statusCompleted => 'Selesai';

  @override
  String get statusFailed => 'Gagal';

  @override
  String get searchHint => 'Cari...';

  @override
  String searchFailed(String error) {
    return 'Pencarian gagal: $error';
  }

  @override
  String get noResults => 'Tidak ada hasil. Coba kata lain.';

  @override
  String resultTitle(String title, int page) {
    return '$title - halaman $page';
  }
}
