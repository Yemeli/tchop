import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/features/payments/payment_providers.dart';
import 'package:tchop/features/payments/payment_security.dart';

/// Payment security unit tests — pure Dart, no Flutter SDK widgets needed.
///
/// Covers: fingerprint masking (the ONLY credential-derived string the UI
/// may show), HMAC-SHA256 verify semantics (mirrors the `payment-webhook`
/// edge function), the refund four-eyes rule, and cash-close variance math.
void main() {
  group('maskFingerprint', () {
    test('provider prefix + last 4 chars, e.g. mtn••••9f2a', () {
      expect(maskFingerprint('mtn_momo', 'user-secret-9f2a'), 'mtn••••9f2a');
    });

    test('orange_money prefix is "orange"', () {
      expect(maskFingerprint('orange_money', 'abcdef1234'), 'orange••••1234');
    });

    test('short secrets are not truncated away', () {
      expect(maskFingerprint('wave', 'ab'), 'wave••••ab');
    });

    test('never leaks more than the last 4 chars', () {
      final masked = maskFingerprint('cinetpay', 'supersecretkeyvalue');
      expect(masked.startsWith('cinetpay••••'), isTrue);
      expect(masked, isNot(contains('supersecret')));
    });

    test('matches the server fingerprint shape (mtn••••9f2a)', () {
      expect(
        RegExp(r'^[a-z]+••••[0-9a-fA-F]{1,4}$')
            .hasMatch(maskFingerprint('mtn_momo', 'xx9f2a')),
        isTrue,
      );
    });
  });

  group('sha256 (pure-Dart, FIPS 180-4)', () {
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    test('empty input', () {
      expect(
        hex(sha256([])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc"', () {
      expect(
        hex(sha256('abc'.codeUnits)),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('hmacSha256Hex', () {
    test('RFC 4231 test case 1', () {
      final key = List<int>.filled(20, 0x0b);
      final mac = hmacSha256Hex(key, 'Hi There'.codeUnits);
      expect(
        mac,
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });

    test('RFC 4231 test case 2 (key "Jefe")', () {
      final mac = hmacSha256Hex(
          'Jefe'.codeUnits, 'what do ya want for nothing?'.codeUnits);
      expect(
        mac,
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('RFC 4231 test case 6 (key larger than block size)', () {
      final key = List<int>.filled(80, 0xaa);
      final mac = hmacSha256Hex(
          key, 'Test Using Larger Than Block-Size Key - Hash Key First'.codeUnits);
      expect(
        mac,
        '6953025ed96f0c09f80a96f78e6538dbe2e7b820e3dd970e7ddd39091b32352f',
      );
    });
  });

  group('verifyHmacSha256Hex (webhook signature semantics)', () {
    const secret = 'webhook-signing-secret';
    const body = 'cpm_trans_id=123&cpm_result=ACCEPTED';

    test('accepts the signature it computed', () {
      final sig = hmacSha256Hex(secret.codeUnits, body.codeUnits);
      expect(
        verifyHmacSha256Hex(secret: secret, body: body, signatureHex: sig),
        isTrue,
      );
    });

    test('rejects a tampered body', () {
      final sig = hmacSha256Hex(secret.codeUnits, body.codeUnits);
      expect(
        verifyHmacSha256Hex(
          secret: secret,
          body: 'cpm_trans_id=123&cpm_result=REFUSED',
          signatureHex: sig,
        ),
        isFalse,
      );
    });

    test('rejects a wrong secret', () {
      final sig = hmacSha256Hex(secret.codeUnits, body.codeUnits);
      expect(
        verifyHmacSha256Hex(
            secret: 'other-secret', body: body, signatureHex: sig),
        isFalse,
      );
    });

    test('rejects a truncated signature (length mismatch)', () {
      final sig = hmacSha256Hex(secret.codeUnits, body.codeUnits);
      expect(
        verifyHmacSha256Hex(
            secret: secret, body: body, signatureHex: sig.substring(0, 32)),
        isFalse,
      );
    });

    test('is case-insensitive on hex', () {
      final sig =
          hmacSha256Hex(secret.codeUnits, body.codeUnits).toUpperCase();
      expect(
        verifyHmacSha256Hex(secret: secret, body: body, signatureHex: sig),
        isTrue,
      );
    });
  });

  group('canApproveRefund (four-eyes)', () {
    test('requester cannot approve their own request', () {
      expect(
        canApproveRefund(
          requesterId: 'user-1',
          approverId: 'user-1',
          approverRole: 'owner',
        ),
        isFalse,
      );
    });

    test('a different owner may approve', () {
      expect(
        canApproveRefund(
          requesterId: 'user-1',
          approverId: 'user-2',
          approverRole: 'owner',
        ),
        isTrue,
      );
    });

    test('a different manager may approve', () {
      expect(
        canApproveRefund(
          requesterId: 'user-1',
          approverId: 'user-2',
          approverRole: 'manager',
        ),
        isTrue,
      );
    });

    test('non-manager roles may not approve (fail closed)', () {
      for (final role in ['head_chef', 'secretary', 'kitchen', 'driver', '']) {
        expect(
          canApproveRefund(
            requesterId: 'user-1',
            approverId: 'user-2',
            approverRole: role,
          ),
          isFalse,
          reason: 'role $role',
        );
      }
    });
  });

  group('cashVariance / formatVarianceFr', () {
    test('surplus', () {
      expect(cashVariance(expected: 86000, counted: 86500), 500);
      expect(formatVarianceFr(500), 'Écart : +500 FCFA');
    });

    test('shortfall uses the French minus sign', () {
      expect(cashVariance(expected: 86000, counted: 85500), -500);
      expect(formatVarianceFr(-500), 'Écart : −500 FCFA');
    });

    test('exact close', () {
      expect(cashVariance(expected: 86000, counted: 86000), 0);
      expect(formatVarianceFr(0), 'Écart : 0 FCFA');
    });
  });

  group('paymentProviders catalog', () {
    test('covers every provider in the DB check constraint', () {
      final ids = paymentProviders.map((p) => p.id).toSet();
      expect(
        ids,
        containsAll(
            ['mtn_momo', 'orange_money', 'wave', 'cinetpay', 'flutterwave', 'card']),
      );
    });

    test('every connectable provider has FR helper text for each field', () {
      for (final p in paymentProviders) {
        for (final f in p.fields) {
          expect(f.labelFr, isNotEmpty, reason: '${p.id}.${f.key} label');
          expect(f.helperFr, isNotEmpty, reason: '${p.id}.${f.key} helper');
          expect(f.key, isNotEmpty);
        }
      }
    });

    test('card is aggregator-routed (no direct fields)', () {
      expect(paymentProviderById('card')!.fields, isEmpty);
    });

    test('unknown provider id returns null', () {
      expect(paymentProviderById('nope'), isNull);
    });
  });
}
