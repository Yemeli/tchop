/// Payment security primitives for Project Tchop.
///
/// Pure Dart (no Flutter import, no external crypto package — the SHA-256
/// below is implemented from the FIPS 180-4 spec so unit tests run anywhere).
///
/// Responsibilities:
///   * [maskFingerprint] — the ONLY credential-derived string the UI may
///     ever display (provider prefix + last 4 chars, e.g. "mtn••••9f2a").
///   * [hmacSha256Hex] / [verifyHmacSha256Hex] — the same HMAC construction
///     the `payment-webhook` edge function uses; kept here so the exact
///     verification semantics are unit-tested on both sides.
///   * [cashVariance] / [formatVarianceFr] — cash-close arithmetic.
///   * [canApproveRefund] — the four-eyes rule (requester ≠ approver).
library;

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// SHA-256 of [message] (FIPS 180-4). Returns 32 bytes.
List<int> sha256(List<int> message) {
  var h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final padded = List<int>.from(message)..add(0x80);
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  final bitLen = message.length * 8;
  for (var i = 7; i >= 0; i--) {
    padded.add((bitLen >> (i * 8)) & 0xFF);
  }
  for (var off = 0; off < padded.length; off += 64) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = (padded[off + i * 4] << 24) |
          (padded[off + i * 4 + 1] << 16) |
          (padded[off + i * 4 + 2] << 8) |
          padded[off + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    h = [
      (h[0] + a) & 0xFFFFFFFF,
      (h[1] + b) & 0xFFFFFFFF,
      (h[2] + c) & 0xFFFFFFFF,
      (h[3] + d) & 0xFFFFFFFF,
      (h[4] + e) & 0xFFFFFFFF,
      (h[5] + f) & 0xFFFFFFFF,
      (h[6] + g) & 0xFFFFFFFF,
      (h[7] + hh) & 0xFFFFFFFF,
    ];
  }
  return h
      .expand((x) => [(x >> 24) & 0xFF, (x >> 16) & 0xFF, (x >> 8) & 0xFF, x & 0xFF])
      .toList();
}

/// HMAC-SHA-256 of [data] under [key], hex-encoded. Mirrors the webhook
/// function's `hmacSha256Hex`.
String hmacSha256Hex(List<int> key, List<int> data) {
  var k = key.length > 64 ? sha256(key) : List<int>.from(key);
  if (k.length < 64) {
    k = [...k, ...List<int>.filled(64 - k.length, 0)];
  }
  final oPad = k.map((b) => b ^ 0x5C).toList();
  final iPad = k.map((b) => b ^ 0x36).toList();
  final digest = sha256([...oPad, ...sha256([...iPad, ...data])]);
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Constant-time hex-signature comparison — the client-side twin of the
/// webhook's `timingSafeEqual`.
bool verifyHmacSha256Hex({
  required String secret,
  required String body,
  required String signatureHex,
}) {
  final expected = hmacSha256Hex(secret.codeUnits, body.codeUnits);
  final a = expected.toLowerCase();
  final b = signatureHex.toLowerCase();
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// The only credential-derived string the UI may display:
/// provider prefix + "••••" + last 4 chars of the secret, e.g. "mtn••••9f2a".
///
/// The server builds this from the real secret; the client builds it only
/// from values it already holds in memory — never persisted.
String maskFingerprint(String providerId, String secret) {
  final prefix = providerId.split('_').first;
  final tail = secret.length <= 4 ? secret : secret.substring(secret.length - 4);
  return '$prefix••••$tail';
}

/// Cash-close arithmetic: counted − expected, in minor units (FCFA).
int cashVariance({required int expected, required int counted}) =>
    counted - expected;

/// French variance label, e.g. "Écart : +500 FCFA", "Écart : −500 FCFA".
String formatVarianceFr(int variance) {
  final sign = variance > 0 ? '+' : (variance < 0 ? '−' : '');
  return 'Écart : $sign${variance.abs()} FCFA';
}

/// Four-eyes rule for refunds: the approver must be a *different*
/// owner/manager than the requester. Fail-closed on unknown roles.
bool canApproveRefund({
  required String requesterId,
  required String approverId,
  required String approverRole,
}) {
  if (requesterId == approverId) return false;
  return approverRole == 'owner' || approverRole == 'manager';
}
