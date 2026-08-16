// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OCR Search';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInFailed => 'Sign-in failed. Please try again.';

  @override
  String get searchDocumentsHint => 'Search documents...';

  @override
  String get noDocumentsYet => 'No documents yet. Tap + to create one.';

  @override
  String get newDocument => 'New Document';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pages',
      one: 'page',
    );
    return '$count $_temp0';
  }

  @override
  String failedToLoadDocuments(String error) {
    return 'Failed to load documents: $error';
  }

  @override
  String get documentTitle => 'Document';

  @override
  String get editTitle => 'Edit title';

  @override
  String get uploadImage => 'Upload Image';

  @override
  String get uploadFromCamera => 'Upload from Camera';

  @override
  String uploadingProgress(int done, int total) {
    return 'Uploading $done/$total...';
  }

  @override
  String failedToLoadPages(String error) {
    return 'Failed to load pages: $error';
  }

  @override
  String get noPagesYet => 'No pages yet. Use Upload Image.';

  @override
  String get renameDocument => 'Rename Document';

  @override
  String get titleLabel => 'Title';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusProcessing => 'Processing';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusFailed => 'Failed';

  @override
  String get searchHint => 'Search...';

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String get noResults => 'No results. Try different terms.';

  @override
  String resultTitle(String title, int page) {
    return '$title - page $page';
  }
}
