import 'daypart.dart';

/// Menu draft document model (mirrors the server `menu_drafts.items` JSON
/// plus the `dayparts` array and the local approvals inbox).
///
/// Pure Dart — no Flutter dependency — so drafts can be built, diffed and
/// unit-tested without a widget tree. Prices are integers in FCFA.
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    this.sort = 0,
  });

  final String id;
  final String name;
  final int sort;

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        sort: (json['sort'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'sort': sort};

  MenuCategory copyWith({String? name, int? sort}) => MenuCategory(
        id: id,
        name: name ?? this.name,
        sort: sort ?? this.sort,
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description = '',
    this.priceFcfa = 0,
    this.photoUrl,
    this.tags = const [],
    this.sort = 0,
    this.pendingApproval = false,
    this.approvalOldPrice,
    this.approvalNewPrice,
    this.approvalRequestedBy,
    this.approvalRequestedAt,
  });

  final String id;
  final String categoryId;
  final String name;
  final String description;

  /// Price in FCFA (integer, no decimals).
  final int priceFcfa;

  /// Storage URL of `menu/{tenant_id}/{item_id}.jpg`, if a photo was set.
  final String? photoUrl;
  final List<String> tags;
  final int sort;

  /// True while a >10% price change awaits owner/manager approval.
  /// [priceFcfa] keeps showing the last *applied* price until approved.
  final bool pendingApproval;
  final int? approvalOldPrice;
  final int? approvalNewPrice;
  final String? approvalRequestedBy;
  final DateTime? approvalRequestedAt;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        categoryId: json['category_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        priceFcfa: (json['price_fcfa'] as num?)?.toInt() ?? 0,
        photoUrl: json['photo_url'] as String?,
        tags: (json['tags'] as List?)
                ?.map((t) => t.toString())
                .toList(growable: false) ??
            const [],
        sort: (json['sort'] as num?)?.toInt() ?? 0,
        pendingApproval: json['pending_approval'] as bool? ?? false,
        approvalOldPrice: (json['approval_old_price'] as num?)?.toInt(),
        approvalNewPrice: (json['approval_new_price'] as num?)?.toInt(),
        approvalRequestedBy: json['approval_requested_by'] as String?,
        approvalRequestedAt: json['approval_requested_at'] == null
            ? null
            : DateTime.tryParse(json['approval_requested_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'price_fcfa': priceFcfa,
        'photo_url': photoUrl,
        'tags': tags,
        'sort': sort,
        'pending_approval': pendingApproval,
        'approval_old_price': approvalOldPrice,
        'approval_new_price': approvalNewPrice,
        'approval_requested_by': approvalRequestedBy,
        'approval_requested_at': approvalRequestedAt?.toIso8601String(),
      };

  MenuItem copyWith({
    String? categoryId,
    String? name,
    String? description,
    int? priceFcfa,
    String? photoUrl,
    List<String>? tags,
    int? sort,
    bool? pendingApproval,
    int? approvalOldPrice,
    int? approvalNewPrice,
    String? approvalRequestedBy,
    DateTime? approvalRequestedAt,
    bool clearApproval = false,
  }) =>
      MenuItem(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        description: description ?? this.description,
        priceFcfa: priceFcfa ?? this.priceFcfa,
        photoUrl: photoUrl ?? this.photoUrl,
        tags: tags ?? this.tags,
        sort: sort ?? this.sort,
        pendingApproval:
            clearApproval ? false : (pendingApproval ?? this.pendingApproval),
        approvalOldPrice:
            clearApproval ? null : (approvalOldPrice ?? this.approvalOldPrice),
        approvalNewPrice:
            clearApproval ? null : (approvalNewPrice ?? this.approvalNewPrice),
        approvalRequestedBy: clearApproval
            ? null
            : (approvalRequestedBy ?? this.approvalRequestedBy),
        approvalRequestedAt: clearApproval
            ? null
            : (approvalRequestedAt ?? this.approvalRequestedAt),
      );
}

/// One entry in the owner/manager approvals inbox.
class MenuApproval {
  const MenuApproval({
    required this.id,
    required this.kind,
    required this.itemId,
    required this.itemName,
    this.oldPriceFcfa,
    this.newPriceFcfa,
    this.requestedBy,
    this.requestedAt,
    this.status = approvalPending,
  });

  static const String kindPriceChange = 'price_change';
  static const String kindRequest86 = 'request_86';

  static const String approvalPending = 'pending';
  static const String approvalApproved = 'approved';
  static const String approvalRejected = 'rejected';

  final String id;
  final String kind;
  final String itemId;
  final String itemName;
  final int? oldPriceFcfa;
  final int? newPriceFcfa;
  final String? requestedBy;
  final DateTime? requestedAt;

  /// pending | approved | rejected
  final String status;

  bool get isPending => status == approvalPending;

  factory MenuApproval.fromJson(Map<String, dynamic> json) => MenuApproval(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? kindPriceChange,
        itemId: json['item_id'] as String? ?? '',
        itemName: json['item_name'] as String? ?? '',
        oldPriceFcfa: (json['old_price_fcfa'] as num?)?.toInt(),
        newPriceFcfa: (json['new_price_fcfa'] as num?)?.toInt(),
        requestedBy: json['requested_by'] as String?,
        requestedAt: json['requested_at'] == null
            ? null
            : DateTime.tryParse(json['requested_at'] as String),
        status: json['status'] as String? ?? approvalPending,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'item_id': itemId,
        'item_name': itemName,
        'old_price_fcfa': oldPriceFcfa,
        'new_price_fcfa': newPriceFcfa,
        'requested_by': requestedBy,
        'requested_at': requestedAt?.toIso8601String(),
        'status': status,
      };

  MenuApproval copyWith({String? status}) => MenuApproval(
        id: id,
        kind: kind,
        itemId: itemId,
        itemName: itemName,
        oldPriceFcfa: oldPriceFcfa,
        newPriceFcfa: newPriceFcfa,
        requestedBy: requestedBy,
        requestedAt: requestedAt,
        status: status ?? this.status,
      );
}

/// The full editable draft: categories + items + dayparts + approvals inbox.
class MenuDraftDoc {
  const MenuDraftDoc({
    this.categories = const [],
    this.items = const [],
    this.dayparts = const [],
    this.approvals = const [],
    this.updatedBy,
    this.updatedAt,
  });

  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final List<Daypart> dayparts;
  final List<MenuApproval> approvals;
  final String? updatedBy;
  final DateTime? updatedAt;

  /// A fresh draft seeded with the default service windows.
  factory MenuDraftDoc.empty() => MenuDraftDoc(dayparts: Daypart.defaults());

  factory MenuDraftDoc.fromJson(Map<String, dynamic> json) => MenuDraftDoc(
        categories: (json['categories'] as List? ?? [])
            .map((c) => MenuCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
        items: (json['items'] as List? ?? [])
            .map((i) => MenuItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        dayparts: (json['dayparts'] as List? ?? [])
            .map((d) => Daypart.fromJson(d as Map<String, dynamic>))
            .toList(),
        approvals: (json['approvals'] as List? ?? [])
            .map((a) => MenuApproval.fromJson(a as Map<String, dynamic>))
            .toList(),
        updatedBy: json['updated_by'] as String?,
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.tryParse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'categories': categories.map((c) => c.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
        'dayparts': dayparts.map((d) => d.toJson()).toList(),
        'approvals': approvals.map((a) => a.toJson()).toList(),
        'updated_by': updatedBy,
        'updated_at': updatedAt?.toIso8601String(),
      };

  List<MenuItem> itemsInCategory(String categoryId) {
    final list =
        items.where((i) => i.categoryId == categoryId).toList(growable: false);
    list.sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  List<MenuCategory> get sortedCategories {
    final list = List<MenuCategory>.from(categories);
    list.sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  /// Approvals still waiting for an owner/manager decision, newest first.
  List<MenuApproval> get pendingApprovals {
    final list = approvals.where((a) => a.isPending).toList();
    list.sort((a, b) => (b.requestedAt ?? DateTime(1970))
        .compareTo(a.requestedAt ?? DateTime(1970)));
    return list;
  }

  MenuDraftDoc copyWith({
    List<MenuCategory>? categories,
    List<MenuItem>? items,
    List<Daypart>? dayparts,
    List<MenuApproval>? approvals,
    String? updatedBy,
    DateTime? updatedAt,
  }) =>
      MenuDraftDoc(
        categories: categories ?? this.categories,
        items: items ?? this.items,
        dayparts: dayparts ?? this.dayparts,
        approvals: approvals ?? this.approvals,
        updatedBy: updatedBy ?? this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
