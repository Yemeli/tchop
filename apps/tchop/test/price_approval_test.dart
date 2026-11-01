import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/menu/price_approval.dart';

void main() {
  group('priceChangeNeedsApproval', () {
    test('small changes apply immediately', () {
      expect(priceChangeNeedsApproval(2000, 2100), isFalse); // +5%
      expect(priceChangeNeedsApproval(2000, 1900), isFalse); // -5%
      expect(priceChangeNeedsApproval(2500, 2500), isFalse); // unchanged
    });

    test('exactly 10% does not need approval (strictly greater than)', () {
      expect(priceChangeNeedsApproval(2000, 2200), isFalse); // +10%
      expect(priceChangeNeedsApproval(2000, 1800), isFalse); // -10%
    });

    test('more than 10% needs approval, up or down', () {
      expect(priceChangeNeedsApproval(2000, 2201), isTrue); // +10.05%
      expect(priceChangeNeedsApproval(2000, 2500), isTrue); // +25%
      expect(priceChangeNeedsApproval(2000, 1799), isTrue); // -10.05%
      expect(priceChangeNeedsApproval(2000, 1000), isTrue); // -50%
    });

    test('zero old price: any change needs approval', () {
      expect(priceChangeNeedsApproval(0, 100), isTrue);
      expect(priceChangeNeedsApproval(0, 0), isFalse);
    });

    test('threshold constant is 10%', () {
      expect(approvalThreshold, 0.10);
    });
  });
}
