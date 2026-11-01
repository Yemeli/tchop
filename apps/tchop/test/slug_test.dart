import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/core/session/slugify.dart';

/// Pure-Dart tests for workspace slug generation / validation.
/// Run: `flutter test test/slug_test.dart`
void main() {
  group('slugify', () {
    test('lowercases and hyphenates a plain name', () {
      expect(slugify('Le Baobab Gourmand'), 'le-baobab-gourmand');
    });

    test('strips French accents', () {
      expect(slugify('Chez Maman Ngassa'), 'chez-maman-ngassa');
      expect(
        slugify('Crêperie Brûlée à l’Œuf'),
        'creperie-brulee-a-l-oeuf',
      );
      expect(slugify('Çaçá Ñoño'), 'caca-nono');
    });

    test('collapses separators and trims dashes', () {
      expect(slugify('  Le   Baobab -- Gourmand!! '), 'le-baobab-gourmand');
      expect(slugify('---test---'), 'test');
    });

    test('keeps digits', () {
      expect(slugify('Restaurant 237'), 'restaurant-237');
    });

    test('caps length at 40 chars without trailing dash', () {
      final long = slugify(
          'Un nom de restaurant vraiment beaucoup trop long pour un slug');
      expect(long.length, lessThanOrEqualTo(40));
      expect(long.endsWith('-'), isFalse);
      expect(isValidSlug(long), isTrue);
    });

    test('empty or symbol-only input yields empty string', () {
      expect(slugify(''), isEmpty);
      expect(slugify('!!!'), isEmpty);
    });
  });

  group('isValidSlug', () {
    test('accepts well-formed slugs', () {
      expect(isValidSlug('lapalmeraie'), isTrue);
      expect(isValidSlug('le-baobab-gourmand'), isTrue);
      expect(isValidSlug('resto-237'), isTrue);
      expect(isValidSlug('a12'), isTrue);
    });

    test('rejects malformed slugs', () {
      expect(isValidSlug(''), isFalse);
      expect(isValidSlug('ab'), isFalse); // too short
      expect(isValidSlug('-lead'), isFalse);
      expect(isValidSlug('trail-'), isFalse);
      expect(isValidSlug('UPPER'), isFalse);
      expect(isValidSlug('with space'), isFalse);
      expect(isValidSlug('with_underscore'), isFalse);
      expect(isValidSlug('café'), isFalse);
      expect(isValidSlug('a' * 41), isFalse); // too long
    });
  });
}
