/// Price-change approval policy for the menu studio.
///
/// A price edit that moves the price more than [approvalThreshold] relative
/// to the last *published* snapshot price does NOT apply immediately: the
/// item is flagged `pendingApproval` in the draft and routed to the
/// owner/manager approvals inbox (`menu/approve_price` outbox op).
/// Edits within the threshold apply instantly.
///
/// Pure Dart — unit-tested in test/price_approval_test.dart.
library;

/// Relative change that triggers the approval flow (10%).
const double approvalThreshold = 0.10;

/// True when changing [oldPriceFcfa] → [newPriceFcfa] needs owner/manager
/// approval (absolute relative change strictly greater than 10%).
///
/// Edge cases:
/// - identical prices → never needs approval;
/// - a zero/negative old price (e.g. a free promo item gaining a price)
///   → any change needs approval, since the relative change is undefined.
bool priceChangeNeedsApproval(int oldPriceFcfa, int newPriceFcfa) {
  if (oldPriceFcfa == newPriceFcfa) return false;
  if (oldPriceFcfa <= 0) return true;
  final change = (newPriceFcfa - oldPriceFcfa).abs() / oldPriceFcfa;
  return change > approvalThreshold;
}
