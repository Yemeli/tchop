// GENERATED CODE - DO NOT MODIFY BY HAND
// Hand-written on a VM without the Flutter SDK (FEATURE 1).
// Regenerate with:
//   cd apps/tchop && dart run build_runner build --delete-conflicting-outputs
// ignore_for_file: type=lint

part of 'tchop_database.dart';

class $TenantsTable extends Tenants with TableInfo<$TenantsTable, Tenant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TenantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta =
      const VerificationMeta('id');
  static const VerificationMeta _nameMeta =
      const VerificationMeta('name');
  static const VerificationMeta _brandJsonMeta =
      const VerificationMeta('brandJson');
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> brandJson = GeneratedColumn<String>(
      'brand_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, name, brandJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tenants';
  @override
  VerificationContext validateIntegrity(Insertable<Tenant> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta,
          id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta,
          name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand_json')) {
      context.handle(_brandJsonMeta,
          brandJson.isAcceptableOrUnknown(data['brand_json']!, _brandJsonMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tenant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tenant(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      brandJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}brand_json'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TenantsTable createAlias(String alias) {
    return $TenantsTable(attachedDatabase, alias);
  }
}

class Tenant extends DataClass implements Insertable<Tenant> {
  final String id;
  final String name;
  final String brandJson;
  final DateTime updatedAt;
  const Tenant({required this.id, required this.name, required this.brandJson, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['brand_json'] = Variable<String>(brandJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }
  TenantsCompanion toCompanion(bool nullToAbsent) {
    return TenantsCompanion(
      id: Value(id),
      name: Value(name),
      brandJson: Value(brandJson),
      updatedAt: Value(updatedAt),
    );
  }
  factory Tenant.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tenant(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      brandJson: serializer.fromJson<String>(json['brandJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'brandJson': serializer.toJson<String>(brandJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }
  Tenant copyWith({String? id, String? name, String? brandJson, DateTime? updatedAt}) => Tenant(
        id: id ?? this.id,
        name: name ?? this.name,
        brandJson: brandJson ?? this.brandJson,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Tenant(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('brandJson: $brandJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(id, name, brandJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tenant &&
          other.id == this.id &&
          other.name == this.name &&
          other.brandJson == this.brandJson &&
          other.updatedAt == this.updatedAt);
}

class TenantsCompanion extends UpdateCompanion<Tenant> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> brandJson;
  final Value<DateTime> updatedAt;
  const TenantsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.brandJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TenantsCompanion.insert({
    required String id,
    required String name,
    this.brandJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })
      : id = Value(id),
        name = Value(name);
  static Insertable<Tenant> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? brandJson,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (brandJson != null) 'brand_json': brandJson,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brandJson.present) {
      map['brand_json'] = Variable<String>(brandJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('TenantsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('brandJson: $brandJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
}

class $MenuSnapshotsTable extends MenuSnapshots with TableInfo<$MenuSnapshotsTable, MenuSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MenuSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta =
      const VerificationMeta('id');
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  static const VerificationMeta _itemsJsonMeta =
      const VerificationMeta('itemsJson');
  static const VerificationMeta _publishedAtMeta =
      const VerificationMeta('publishedAt');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<String> itemsJson = GeneratedColumn<String>(
      'items_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  late final GeneratedColumn<DateTime> publishedAt = GeneratedColumn<DateTime>(
      'published_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, tenantId, version, itemsJson, publishedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'menu_snapshots';
  @override
  VerificationContext validateIntegrity(Insertable<MenuSnapshot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta,
          id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('items_json')) {
      context.handle(_itemsJsonMeta,
          itemsJson.isAcceptableOrUnknown(data['items_json']!, _itemsJsonMeta));
    }
    if (data.containsKey('published_at')) {
      context.handle(_publishedAtMeta,
          publishedAt.isAcceptableOrUnknown(data['published_at']!, _publishedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MenuSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MenuSnapshot(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      version: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      itemsJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}items_json'])!,
      publishedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}published_at']),
    );
  }

  @override
  $MenuSnapshotsTable createAlias(String alias) {
    return $MenuSnapshotsTable(attachedDatabase, alias);
  }
}

class MenuSnapshot extends DataClass implements Insertable<MenuSnapshot> {
  final String id;
  final String tenantId;
  final int version;
  final String itemsJson;
  final DateTime? publishedAt;
  const MenuSnapshot({required this.id, required this.tenantId, required this.version, required this.itemsJson, this.publishedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['version'] = Variable<int>(version);
    map['items_json'] = Variable<String>(itemsJson);
    if (!nullToAbsent || publishedAt != null) {
      map['published_at'] = Variable<DateTime>(publishedAt);
    }
    return map;
  }
  MenuSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return MenuSnapshotsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      version: Value(version),
      itemsJson: Value(itemsJson),
      publishedAt: Value(publishedAt),
    );
  }
  factory MenuSnapshot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MenuSnapshot(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      version: serializer.fromJson<int>(json['version']),
      itemsJson: serializer.fromJson<String>(json['itemsJson']),
      publishedAt: serializer.fromJson<DateTime?>(json['publishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'version': serializer.toJson<int>(version),
      'itemsJson': serializer.toJson<String>(itemsJson),
      'publishedAt': serializer.toJson<DateTime?>(publishedAt),
    };
  }
  MenuSnapshot copyWith({String? id, String? tenantId, int? version, String? itemsJson, Value<DateTime?> publishedAt = const Value.absent()}) => MenuSnapshot(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        version: version ?? this.version,
        itemsJson: itemsJson ?? this.itemsJson,
        publishedAt: publishedAt.present ? publishedAt.value : this.publishedAt,
      );
  @override
  String toString() {
    return (StringBuffer('MenuSnapshot(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('version: $version, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('publishedAt: $publishedAt, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(id, tenantId, version, itemsJson, publishedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MenuSnapshot &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.version == this.version &&
          other.itemsJson == this.itemsJson &&
          other.publishedAt == this.publishedAt);
}

class MenuSnapshotsCompanion extends UpdateCompanion<MenuSnapshot> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<int> version;
  final Value<String> itemsJson;
  final Value<DateTime?> publishedAt;
  const MenuSnapshotsCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.version = const Value.absent(),
    this.itemsJson = const Value.absent(),
    this.publishedAt = const Value.absent(),
  });
  MenuSnapshotsCompanion.insert({
    required String id,
    required String tenantId,
    required int version,
    this.itemsJson = const Value.absent(),
    this.publishedAt = const Value.absent(),
  })
      : id = Value(id),
        tenantId = Value(tenantId),
        version = Value(version);
  static Insertable<MenuSnapshot> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<int>? version,
    Expression<String>? itemsJson,
    Expression<DateTime?>? publishedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (version != null) 'version': version,
      if (itemsJson != null) 'items_json': itemsJson,
      if (publishedAt != null) 'published_at': publishedAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (itemsJson.present) {
      map['items_json'] = Variable<String>(itemsJson.value);
    }
    if (publishedAt.present) {
      map['published_at'] = Variable<DateTime>(publishedAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('MenuSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('version: $version, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('publishedAt: $publishedAt, ')
          ..write(')'))
        .toString();
  }
}

class $ItemAvailabilitiesTable extends ItemAvailabilities with TableInfo<$ItemAvailabilitiesTable, ItemAvailability> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemAvailabilitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _itemIdMeta =
      const VerificationMeta('itemId');
  static const VerificationMeta _availableMeta =
      const VerificationMeta('available');
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<bool> available = GeneratedColumn<bool>(
      'available', aliasedName, false,
      type: DriftSqlType.bool, requiredDuringInsert: false,
      defaultValue: const Constant(true));
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [tenantId, itemId, available, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_availability';
  @override
  VerificationContext validateIntegrity(Insertable<ItemAvailability> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('available')) {
      context.handle(_availableMeta,
          available.isAcceptableOrUnknown(data['available']!, _availableMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId, itemId};
  @override
  ItemAvailability map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemAvailability(
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      itemId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      available: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}available'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ItemAvailabilitiesTable createAlias(String alias) {
    return $ItemAvailabilitiesTable(attachedDatabase, alias);
  }
}

class ItemAvailability extends DataClass implements Insertable<ItemAvailability> {
  final String tenantId;
  final String itemId;
  final bool available;
  final DateTime updatedAt;
  const ItemAvailability({required this.tenantId, required this.itemId, required this.available, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['item_id'] = Variable<String>(itemId);
    map['available'] = Variable<bool>(available);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }
  ItemAvailabilitiesCompanion toCompanion(bool nullToAbsent) {
    return ItemAvailabilitiesCompanion(
      tenantId: Value(tenantId),
      itemId: Value(itemId),
      available: Value(available),
      updatedAt: Value(updatedAt),
    );
  }
  factory ItemAvailability.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemAvailability(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      available: serializer.fromJson<bool>(json['available']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'itemId': serializer.toJson<String>(itemId),
      'available': serializer.toJson<bool>(available),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }
  ItemAvailability copyWith({String? tenantId, String? itemId, bool? available, DateTime? updatedAt}) => ItemAvailability(
        tenantId: tenantId ?? this.tenantId,
        itemId: itemId ?? this.itemId,
        available: available ?? this.available,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('ItemAvailability(')
          ..write('tenantId: $tenantId, ')
          ..write('itemId: $itemId, ')
          ..write('available: $available, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(tenantId, itemId, available, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemAvailability &&
          other.tenantId == this.tenantId &&
          other.itemId == this.itemId &&
          other.available == this.available &&
          other.updatedAt == this.updatedAt);
}

class ItemAvailabilitiesCompanion extends UpdateCompanion<ItemAvailability> {
  final Value<String> tenantId;
  final Value<String> itemId;
  final Value<bool> available;
  final Value<DateTime> updatedAt;
  const ItemAvailabilitiesCompanion({
    this.tenantId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.available = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ItemAvailabilitiesCompanion.insert({
    required String tenantId,
    required String itemId,
    this.available = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })
      : tenantId = Value(tenantId),
        itemId = Value(itemId);
  static Insertable<ItemAvailability> custom({
    Expression<String>? tenantId,
    Expression<String>? itemId,
    Expression<bool>? available,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (itemId != null) 'item_id': itemId,
      if (available != null) 'available': available,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (available.present) {
      map['available'] = Variable<bool>(available.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('ItemAvailabilitiesCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('itemId: $itemId, ')
          ..write('available: $available, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
}

class $OrdersTable extends Orders with TableInfo<$OrdersTable, Order> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta =
      const VerificationMeta('id');
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _statusMeta =
      const VerificationMeta('status');
  static const VerificationMeta _paymentStatusMeta =
      const VerificationMeta('paymentStatus');
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  static const VerificationMeta _menuVersionMeta =
      const VerificationMeta('menuVersion');
  static const VerificationMeta _linesJsonMeta =
      const VerificationMeta('linesJson');
  static const VerificationMeta _subtotalCentsMeta =
      const VerificationMeta('subtotalCents');
  static const VerificationMeta _deliveryFeeCentsMeta =
      const VerificationMeta('deliveryFeeCents');
  static const VerificationMeta _totalCentsMeta =
      const VerificationMeta('totalCents');
  static const VerificationMeta _clientMutationIdMeta =
      const VerificationMeta('clientMutationId');
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  static const VerificationMeta _channelMeta =
      const VerificationMeta('channel');
  static const VerificationMeta _customerNameMeta =
      const VerificationMeta('customerName');
  static const VerificationMeta _customerPhoneMeta =
      const VerificationMeta('customerPhone');
  static const VerificationMeta _tableNumberMeta =
      const VerificationMeta('tableNumber');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant('placed'));
  late final GeneratedColumn<String> paymentStatus = GeneratedColumn<String>(
      'payment_status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> menuVersion = GeneratedColumn<int>(
      'menu_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false,
      defaultValue: const Constant(1));
  late final GeneratedColumn<String> linesJson = GeneratedColumn<String>(
      'lines_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  late final GeneratedColumn<int> subtotalCents = GeneratedColumn<int>(
      'subtotal_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false,
      defaultValue: const Constant(0));
  late final GeneratedColumn<int> deliveryFeeCents = GeneratedColumn<int>(
      'delivery_fee_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false,
      defaultValue: const Constant(0));
  late final GeneratedColumn<int> totalCents = GeneratedColumn<int>(
      'total_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false,
      defaultValue: const Constant(0));
  late final GeneratedColumn<String> clientMutationId = GeneratedColumn<String>(
      'client_mutation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
      'channel', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
      'customer_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> customerPhone = GeneratedColumn<String>(
      'customer_phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> tableNumber = GeneratedColumn<int>(
      'table_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, tenantId, status, paymentStatus, paymentMethod, menuVersion, linesJson, subtotalCents, deliveryFeeCents, totalCents, clientMutationId, createdAt, updatedAt, channel, customerName, customerPhone, tableNumber];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'orders';
  @override
  VerificationContext validateIntegrity(Insertable<Order> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta,
          id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('payment_status')) {
      context.handle(_paymentStatusMeta,
          paymentStatus.isAcceptableOrUnknown(data['payment_status']!, _paymentStatusMeta));
    }
    if (data.containsKey('payment_method')) {
      context.handle(_paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(data['payment_method']!, _paymentMethodMeta));
    }
    if (data.containsKey('menu_version')) {
      context.handle(_menuVersionMeta,
          menuVersion.isAcceptableOrUnknown(data['menu_version']!, _menuVersionMeta));
    }
    if (data.containsKey('lines_json')) {
      context.handle(_linesJsonMeta,
          linesJson.isAcceptableOrUnknown(data['lines_json']!, _linesJsonMeta));
    }
    if (data.containsKey('subtotal_cents')) {
      context.handle(_subtotalCentsMeta,
          subtotalCents.isAcceptableOrUnknown(data['subtotal_cents']!, _subtotalCentsMeta));
    }
    if (data.containsKey('delivery_fee_cents')) {
      context.handle(_deliveryFeeCentsMeta,
          deliveryFeeCents.isAcceptableOrUnknown(data['delivery_fee_cents']!, _deliveryFeeCentsMeta));
    }
    if (data.containsKey('total_cents')) {
      context.handle(_totalCentsMeta,
          totalCents.isAcceptableOrUnknown(data['total_cents']!, _totalCentsMeta));
    }
    if (data.containsKey('client_mutation_id')) {
      context.handle(_clientMutationIdMeta,
          clientMutationId.isAcceptableOrUnknown(data['client_mutation_id']!, _clientMutationIdMeta));
    } else if (isInserting) {
      context.missing(_clientMutationIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('channel')) {
      context.handle(_channelMeta,
          channel.isAcceptableOrUnknown(data['channel']!, _channelMeta));
    }
    if (data.containsKey('customer_name')) {
      context.handle(_customerNameMeta,
          customerName.isAcceptableOrUnknown(data['customer_name']!, _customerNameMeta));
    }
    if (data.containsKey('customer_phone')) {
      context.handle(_customerPhoneMeta,
          customerPhone.isAcceptableOrUnknown(data['customer_phone']!, _customerPhoneMeta));
    }
    if (data.containsKey('table_number')) {
      context.handle(_tableNumberMeta,
          tableNumber.isAcceptableOrUnknown(data['table_number']!, _tableNumberMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Order map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Order(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      status: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      paymentStatus: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payment_status'])!,
      paymentMethod: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payment_method']),
      menuVersion: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}menu_version'])!,
      linesJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}lines_json'])!,
      subtotalCents: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}subtotal_cents'])!,
      deliveryFeeCents: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}delivery_fee_cents'])!,
      totalCents: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}total_cents'])!,
      clientMutationId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}client_mutation_id'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      channel: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}channel']),
      customerName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}customer_name']),
      customerPhone: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}customer_phone']),
      tableNumber: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}table_number']),
    );
  }

  @override
  $OrdersTable createAlias(String alias) {
    return $OrdersTable(attachedDatabase, alias);
  }
}

class Order extends DataClass implements Insertable<Order> {
  final String id;
  final String tenantId;
  final String status;
  final String paymentStatus;
  final String? paymentMethod;
  final int menuVersion;
  final String linesJson;
  final int subtotalCents;
  final int deliveryFeeCents;
  final int totalCents;
  final String clientMutationId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? channel;
  final String? customerName;
  final String? customerPhone;
  final int? tableNumber;
  const Order({required this.id, required this.tenantId, required this.status, required this.paymentStatus, this.paymentMethod, required this.menuVersion, required this.linesJson, required this.subtotalCents, required this.deliveryFeeCents, required this.totalCents, required this.clientMutationId, required this.createdAt, required this.updatedAt, this.channel, this.customerName, this.customerPhone, this.tableNumber});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['status'] = Variable<String>(status);
    map['payment_status'] = Variable<String>(paymentStatus);
    if (!nullToAbsent || paymentMethod != null) {
      map['payment_method'] = Variable<String>(paymentMethod);
    }
    map['menu_version'] = Variable<int>(menuVersion);
    map['lines_json'] = Variable<String>(linesJson);
    map['subtotal_cents'] = Variable<int>(subtotalCents);
    map['delivery_fee_cents'] = Variable<int>(deliveryFeeCents);
    map['total_cents'] = Variable<int>(totalCents);
    map['client_mutation_id'] = Variable<String>(clientMutationId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || channel != null) {
      map['channel'] = Variable<String>(channel);
    }
    if (!nullToAbsent || customerName != null) {
      map['customer_name'] = Variable<String>(customerName);
    }
    if (!nullToAbsent || customerPhone != null) {
      map['customer_phone'] = Variable<String>(customerPhone);
    }
    if (!nullToAbsent || tableNumber != null) {
      map['table_number'] = Variable<int>(tableNumber);
    }
    return map;
  }
  OrdersCompanion toCompanion(bool nullToAbsent) {
    return OrdersCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      status: Value(status),
      paymentStatus: Value(paymentStatus),
      paymentMethod: Value(paymentMethod),
      menuVersion: Value(menuVersion),
      linesJson: Value(linesJson),
      subtotalCents: Value(subtotalCents),
      deliveryFeeCents: Value(deliveryFeeCents),
      totalCents: Value(totalCents),
      clientMutationId: Value(clientMutationId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      channel: Value(channel),
      customerName: Value(customerName),
      customerPhone: Value(customerPhone),
      tableNumber: Value(tableNumber),
    );
  }
  factory Order.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Order(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      status: serializer.fromJson<String>(json['status']),
      paymentStatus: serializer.fromJson<String>(json['paymentStatus']),
      paymentMethod: serializer.fromJson<String?>(json['paymentMethod']),
      menuVersion: serializer.fromJson<int>(json['menuVersion']),
      linesJson: serializer.fromJson<String>(json['linesJson']),
      subtotalCents: serializer.fromJson<int>(json['subtotalCents']),
      deliveryFeeCents: serializer.fromJson<int>(json['deliveryFeeCents']),
      totalCents: serializer.fromJson<int>(json['totalCents']),
      clientMutationId: serializer.fromJson<String>(json['clientMutationId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      channel: serializer.fromJson<String?>(json['channel']),
      customerName: serializer.fromJson<String?>(json['customerName']),
      customerPhone: serializer.fromJson<String?>(json['customerPhone']),
      tableNumber: serializer.fromJson<int?>(json['tableNumber']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'status': serializer.toJson<String>(status),
      'paymentStatus': serializer.toJson<String>(paymentStatus),
      'paymentMethod': serializer.toJson<String?>(paymentMethod),
      'menuVersion': serializer.toJson<int>(menuVersion),
      'linesJson': serializer.toJson<String>(linesJson),
      'subtotalCents': serializer.toJson<int>(subtotalCents),
      'deliveryFeeCents': serializer.toJson<int>(deliveryFeeCents),
      'totalCents': serializer.toJson<int>(totalCents),
      'clientMutationId': serializer.toJson<String>(clientMutationId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'channel': serializer.toJson<String?>(channel),
      'customerName': serializer.toJson<String?>(customerName),
      'customerPhone': serializer.toJson<String?>(customerPhone),
      'tableNumber': serializer.toJson<int?>(tableNumber),
    };
  }
  Order copyWith({String? id, String? tenantId, String? status, String? paymentStatus, Value<String?> paymentMethod = const Value.absent(), int? menuVersion, String? linesJson, int? subtotalCents, int? deliveryFeeCents, int? totalCents, String? clientMutationId, DateTime? createdAt, DateTime? updatedAt, Value<String?> channel = const Value.absent(), Value<String?> customerName = const Value.absent(), Value<String?> customerPhone = const Value.absent(), Value<int?> tableNumber = const Value.absent()}) => Order(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paymentMethod: paymentMethod.present ? paymentMethod.value : this.paymentMethod,
        menuVersion: menuVersion ?? this.menuVersion,
        linesJson: linesJson ?? this.linesJson,
        subtotalCents: subtotalCents ?? this.subtotalCents,
        deliveryFeeCents: deliveryFeeCents ?? this.deliveryFeeCents,
        totalCents: totalCents ?? this.totalCents,
        clientMutationId: clientMutationId ?? this.clientMutationId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        channel: channel.present ? channel.value : this.channel,
        customerName: customerName.present ? customerName.value : this.customerName,
        customerPhone: customerPhone.present ? customerPhone.value : this.customerPhone,
        tableNumber: tableNumber.present ? tableNumber.value : this.tableNumber,
      );
  @override
  String toString() {
    return (StringBuffer('Order(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('status: $status, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('menuVersion: $menuVersion, ')
          ..write('linesJson: $linesJson, ')
          ..write('subtotalCents: $subtotalCents, ')
          ..write('deliveryFeeCents: $deliveryFeeCents, ')
          ..write('totalCents: $totalCents, ')
          ..write('clientMutationId: $clientMutationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('channel: $channel, ')
          ..write('customerName: $customerName, ')
          ..write('customerPhone: $customerPhone, ')
          ..write('tableNumber: $tableNumber, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(id, tenantId, status, paymentStatus, paymentMethod, menuVersion, linesJson, subtotalCents, deliveryFeeCents, totalCents, clientMutationId, createdAt, updatedAt, channel, customerName, customerPhone, tableNumber);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Order &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.status == this.status &&
          other.paymentStatus == this.paymentStatus &&
          other.paymentMethod == this.paymentMethod &&
          other.menuVersion == this.menuVersion &&
          other.linesJson == this.linesJson &&
          other.subtotalCents == this.subtotalCents &&
          other.deliveryFeeCents == this.deliveryFeeCents &&
          other.totalCents == this.totalCents &&
          other.clientMutationId == this.clientMutationId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.channel == this.channel &&
          other.customerName == this.customerName &&
          other.customerPhone == this.customerPhone &&
          other.tableNumber == this.tableNumber);
}

class OrdersCompanion extends UpdateCompanion<Order> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> status;
  final Value<String> paymentStatus;
  final Value<String?> paymentMethod;
  final Value<int> menuVersion;
  final Value<String> linesJson;
  final Value<int> subtotalCents;
  final Value<int> deliveryFeeCents;
  final Value<int> totalCents;
  final Value<String> clientMutationId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> channel;
  final Value<String?> customerName;
  final Value<String?> customerPhone;
  final Value<int?> tableNumber;
  const OrdersCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.status = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.menuVersion = const Value.absent(),
    this.linesJson = const Value.absent(),
    this.subtotalCents = const Value.absent(),
    this.deliveryFeeCents = const Value.absent(),
    this.totalCents = const Value.absent(),
    this.clientMutationId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.channel = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerPhone = const Value.absent(),
    this.tableNumber = const Value.absent(),
  });
  OrdersCompanion.insert({
    required String id,
    required String tenantId,
    this.status = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.menuVersion = const Value.absent(),
    this.linesJson = const Value.absent(),
    this.subtotalCents = const Value.absent(),
    this.deliveryFeeCents = const Value.absent(),
    this.totalCents = const Value.absent(),
    required String clientMutationId,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.channel = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerPhone = const Value.absent(),
    this.tableNumber = const Value.absent(),
  })
      : id = Value(id),
        tenantId = Value(tenantId),
        clientMutationId = Value(clientMutationId);
  static Insertable<Order> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? status,
    Expression<String>? paymentStatus,
    Expression<String?>? paymentMethod,
    Expression<int>? menuVersion,
    Expression<String>? linesJson,
    Expression<int>? subtotalCents,
    Expression<int>? deliveryFeeCents,
    Expression<int>? totalCents,
    Expression<String>? clientMutationId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? channel,
    Expression<String>? customerName,
    Expression<String>? customerPhone,
    Expression<int>? tableNumber,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (status != null) 'status': status,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (menuVersion != null) 'menu_version': menuVersion,
      if (linesJson != null) 'lines_json': linesJson,
      if (subtotalCents != null) 'subtotal_cents': subtotalCents,
      if (deliveryFeeCents != null) 'delivery_fee_cents': deliveryFeeCents,
      if (totalCents != null) 'total_cents': totalCents,
      if (clientMutationId != null) 'client_mutation_id': clientMutationId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (channel != null) 'channel': channel,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (tableNumber != null) 'table_number': tableNumber,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (paymentStatus.present) {
      map['payment_status'] = Variable<String>(paymentStatus.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (menuVersion.present) {
      map['menu_version'] = Variable<int>(menuVersion.value);
    }
    if (linesJson.present) {
      map['lines_json'] = Variable<String>(linesJson.value);
    }
    if (subtotalCents.present) {
      map['subtotal_cents'] = Variable<int>(subtotalCents.value);
    }
    if (deliveryFeeCents.present) {
      map['delivery_fee_cents'] = Variable<int>(deliveryFeeCents.value);
    }
    if (totalCents.present) {
      map['total_cents'] = Variable<int>(totalCents.value);
    }
    if (clientMutationId.present) {
      map['client_mutation_id'] = Variable<String>(clientMutationId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (customerPhone.present) {
      map['customer_phone'] = Variable<String>(customerPhone.value);
    }
    if (tableNumber.present) {
      map['table_number'] = Variable<int>(tableNumber.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('OrdersCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('status: $status, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('menuVersion: $menuVersion, ')
          ..write('linesJson: $linesJson, ')
          ..write('subtotalCents: $subtotalCents, ')
          ..write('deliveryFeeCents: $deliveryFeeCents, ')
          ..write('totalCents: $totalCents, ')
          ..write('clientMutationId: $clientMutationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('channel: $channel, ')
          ..write('customerName: $customerName, ')
          ..write('customerPhone: $customerPhone, ')
          ..write('tableNumber: $tableNumber, ')
          ..write(')'))
        .toString();
  }
}

class $DeliveriesTable extends Deliveries with TableInfo<$DeliveriesTable, Delivery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeliveriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta =
      const VerificationMeta('id');
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _orderIdMeta =
      const VerificationMeta('orderId');
  static const VerificationMeta _driverIdMeta =
      const VerificationMeta('driverId');
  static const VerificationMeta _pickedUpAtMeta =
      const VerificationMeta('pickedUpAt');
  static const VerificationMeta _deliveredAtMeta =
      const VerificationMeta('deliveredAt');
  static const VerificationMeta _podPhotoUrlMeta =
      const VerificationMeta('podPhotoUrl');
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
      'order_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> driverId = GeneratedColumn<String>(
      'driver_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> pickedUpAt = GeneratedColumn<DateTime>(
      'picked_up_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
      'delivered_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<String> podPhotoUrl = GeneratedColumn<String>(
      'pod_photo_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, tenantId, orderId, driverId, pickedUpAt, deliveredAt, podPhotoUrl, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deliveries';
  @override
  VerificationContext validateIntegrity(Insertable<Delivery> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta,
          id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(_orderIdMeta,
          orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta));
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('driver_id')) {
      context.handle(_driverIdMeta,
          driverId.isAcceptableOrUnknown(data['driver_id']!, _driverIdMeta));
    }
    if (data.containsKey('picked_up_at')) {
      context.handle(_pickedUpAtMeta,
          pickedUpAt.isAcceptableOrUnknown(data['picked_up_at']!, _pickedUpAtMeta));
    }
    if (data.containsKey('delivered_at')) {
      context.handle(_deliveredAtMeta,
          deliveredAt.isAcceptableOrUnknown(data['delivered_at']!, _deliveredAtMeta));
    }
    if (data.containsKey('pod_photo_url')) {
      context.handle(_podPhotoUrlMeta,
          podPhotoUrl.isAcceptableOrUnknown(data['pod_photo_url']!, _podPhotoUrlMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Delivery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Delivery(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      orderId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}order_id'])!,
      driverId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}driver_id']),
      pickedUpAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}picked_up_at']),
      deliveredAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}delivered_at']),
      podPhotoUrl: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}pod_photo_url']),
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $DeliveriesTable createAlias(String alias) {
    return $DeliveriesTable(attachedDatabase, alias);
  }
}

class Delivery extends DataClass implements Insertable<Delivery> {
  final String id;
  final String tenantId;
  final String orderId;
  final String? driverId;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? podPhotoUrl;
  final DateTime createdAt;
  const Delivery({required this.id, required this.tenantId, required this.orderId, this.driverId, this.pickedUpAt, this.deliveredAt, this.podPhotoUrl, required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['order_id'] = Variable<String>(orderId);
    if (!nullToAbsent || driverId != null) {
      map['driver_id'] = Variable<String>(driverId);
    }
    if (!nullToAbsent || pickedUpAt != null) {
      map['picked_up_at'] = Variable<DateTime>(pickedUpAt);
    }
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || podPhotoUrl != null) {
      map['pod_photo_url'] = Variable<String>(podPhotoUrl);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }
  DeliveriesCompanion toCompanion(bool nullToAbsent) {
    return DeliveriesCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      orderId: Value(orderId),
      driverId: Value(driverId),
      pickedUpAt: Value(pickedUpAt),
      deliveredAt: Value(deliveredAt),
      podPhotoUrl: Value(podPhotoUrl),
      createdAt: Value(createdAt),
    );
  }
  factory Delivery.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Delivery(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      orderId: serializer.fromJson<String>(json['orderId']),
      driverId: serializer.fromJson<String?>(json['driverId']),
      pickedUpAt: serializer.fromJson<DateTime?>(json['pickedUpAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      podPhotoUrl: serializer.fromJson<String?>(json['podPhotoUrl']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'orderId': serializer.toJson<String>(orderId),
      'driverId': serializer.toJson<String?>(driverId),
      'pickedUpAt': serializer.toJson<DateTime?>(pickedUpAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'podPhotoUrl': serializer.toJson<String?>(podPhotoUrl),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }
  Delivery copyWith({String? id, String? tenantId, String? orderId, Value<String?> driverId = const Value.absent(), Value<DateTime?> pickedUpAt = const Value.absent(), Value<DateTime?> deliveredAt = const Value.absent(), Value<String?> podPhotoUrl = const Value.absent(), DateTime? createdAt}) => Delivery(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        orderId: orderId ?? this.orderId,
        driverId: driverId.present ? driverId.value : this.driverId,
        pickedUpAt: pickedUpAt.present ? pickedUpAt.value : this.pickedUpAt,
        deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
        podPhotoUrl: podPhotoUrl.present ? podPhotoUrl.value : this.podPhotoUrl,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('Delivery(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('orderId: $orderId, ')
          ..write('driverId: $driverId, ')
          ..write('pickedUpAt: $pickedUpAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('podPhotoUrl: $podPhotoUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(id, tenantId, orderId, driverId, pickedUpAt, deliveredAt, podPhotoUrl, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Delivery &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.orderId == this.orderId &&
          other.driverId == this.driverId &&
          other.pickedUpAt == this.pickedUpAt &&
          other.deliveredAt == this.deliveredAt &&
          other.podPhotoUrl == this.podPhotoUrl &&
          other.createdAt == this.createdAt);
}

class DeliveriesCompanion extends UpdateCompanion<Delivery> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> orderId;
  final Value<String?> driverId;
  final Value<DateTime?> pickedUpAt;
  final Value<DateTime?> deliveredAt;
  final Value<String?> podPhotoUrl;
  final Value<DateTime> createdAt;
  const DeliveriesCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.orderId = const Value.absent(),
    this.driverId = const Value.absent(),
    this.pickedUpAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.podPhotoUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  DeliveriesCompanion.insert({
    required String id,
    required String tenantId,
    required String orderId,
    this.driverId = const Value.absent(),
    this.pickedUpAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.podPhotoUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
  })
      : id = Value(id),
        tenantId = Value(tenantId),
        orderId = Value(orderId);
  static Insertable<Delivery> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? orderId,
    Expression<String?>? driverId,
    Expression<DateTime?>? pickedUpAt,
    Expression<DateTime?>? deliveredAt,
    Expression<String?>? podPhotoUrl,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (orderId != null) 'order_id': orderId,
      if (driverId != null) 'driver_id': driverId,
      if (pickedUpAt != null) 'picked_up_at': pickedUpAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (podPhotoUrl != null) 'pod_photo_url': podPhotoUrl,
      if (createdAt != null) 'created_at': createdAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (driverId.present) {
      map['driver_id'] = Variable<String>(driverId.value);
    }
    if (pickedUpAt.present) {
      map['picked_up_at'] = Variable<DateTime>(pickedUpAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (podPhotoUrl.present) {
      map['pod_photo_url'] = Variable<String>(podPhotoUrl.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('DeliveriesCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('orderId: $orderId, ')
          ..write('driverId: $driverId, ')
          ..write('pickedUpAt: $pickedUpAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('podPhotoUrl: $podPhotoUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries with TableInfo<$OutboxEntriesTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta =
      const VerificationMeta('id');
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _opMeta =
      const VerificationMeta('op');
  static const VerificationMeta _entityMeta =
      const VerificationMeta('entity');
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  static const VerificationMeta _clientMutationIdMeta =
      const VerificationMeta('clientMutationId');
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  static const VerificationMeta _nextRetryAtMeta =
      const VerificationMeta('nextRetryAt');
  static const VerificationMeta _deadLetterMeta =
      const VerificationMeta('deadLetter');
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
      'op', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> clientMutationId = GeneratedColumn<String>(
      'client_mutation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false,
      defaultValue: const Constant(0));
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
      'next_retry_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<bool> deadLetter = GeneratedColumn<bool>(
      'dead_letter', aliasedName, false,
      type: DriftSqlType.bool, requiredDuringInsert: false,
      defaultValue: const Constant(false));
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, tenantId, op, entity, entityId, payloadJson, clientMutationId, attempts, nextRetryAt, deadLetter, lastError, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta,
          id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta,
          op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(_payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('client_mutation_id')) {
      context.handle(_clientMutationIdMeta,
          clientMutationId.isAcceptableOrUnknown(data['client_mutation_id']!, _clientMutationIdMeta));
    } else if (isInserting) {
      context.missing(_clientMutationIdMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(_nextRetryAtMeta,
          nextRetryAt.isAcceptableOrUnknown(data['next_retry_at']!, _nextRetryAtMeta));
    }
    if (data.containsKey('dead_letter')) {
      context.handle(_deadLetterMeta,
          deadLetter.isAcceptableOrUnknown(data['dead_letter']!, _deadLetterMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      op: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}op'])!,
      entity: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      entityId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      payloadJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      clientMutationId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}client_mutation_id'])!,
      attempts: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      nextRetryAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}next_retry_at']),
      deadLetter: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}dead_letter'])!,
      lastError: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final String id;
  final String tenantId;
  final String op;
  final String entity;
  final String entityId;
  final String payloadJson;
  final String clientMutationId;
  final int attempts;
  final DateTime? nextRetryAt;
  final bool deadLetter;
  final String? lastError;
  final DateTime createdAt;
  const OutboxEntry({required this.id, required this.tenantId, required this.op, required this.entity, required this.entityId, required this.payloadJson, required this.clientMutationId, required this.attempts, this.nextRetryAt, required this.deadLetter, this.lastError, required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['op'] = Variable<String>(op);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['client_mutation_id'] = Variable<String>(clientMutationId);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    map['dead_letter'] = Variable<bool>(deadLetter);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }
  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      op: Value(op),
      entity: Value(entity),
      entityId: Value(entityId),
      payloadJson: Value(payloadJson),
      clientMutationId: Value(clientMutationId),
      attempts: Value(attempts),
      nextRetryAt: Value(nextRetryAt),
      deadLetter: Value(deadLetter),
      lastError: Value(lastError),
      createdAt: Value(createdAt),
    );
  }
  factory OutboxEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      op: serializer.fromJson<String>(json['op']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      clientMutationId: serializer.fromJson<String>(json['clientMutationId']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      deadLetter: serializer.fromJson<bool>(json['deadLetter']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'op': serializer.toJson<String>(op),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'clientMutationId': serializer.toJson<String>(clientMutationId),
      'attempts': serializer.toJson<int>(attempts),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'deadLetter': serializer.toJson<bool>(deadLetter),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }
  OutboxEntry copyWith({String? id, String? tenantId, String? op, String? entity, String? entityId, String? payloadJson, String? clientMutationId, int? attempts, Value<DateTime?> nextRetryAt = const Value.absent(), bool? deadLetter, Value<String?> lastError = const Value.absent(), DateTime? createdAt}) => OutboxEntry(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        op: op ?? this.op,
        entity: entity ?? this.entity,
        entityId: entityId ?? this.entityId,
        payloadJson: payloadJson ?? this.payloadJson,
        clientMutationId: clientMutationId ?? this.clientMutationId,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
        deadLetter: deadLetter ?? this.deadLetter,
        lastError: lastError.present ? lastError.value : this.lastError,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('op: $op, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('clientMutationId: $clientMutationId, ')
          ..write('attempts: $attempts, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('deadLetter: $deadLetter, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(id, tenantId, op, entity, entityId, payloadJson, clientMutationId, attempts, nextRetryAt, deadLetter, lastError, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.op == this.op &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.payloadJson == this.payloadJson &&
          other.clientMutationId == this.clientMutationId &&
          other.attempts == this.attempts &&
          other.nextRetryAt == this.nextRetryAt &&
          other.deadLetter == this.deadLetter &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> op;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> payloadJson;
  final Value<String> clientMutationId;
  final Value<int> attempts;
  final Value<DateTime?> nextRetryAt;
  final Value<bool> deadLetter;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  const OutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.op = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.clientMutationId = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.deadLetter = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    required String id,
    required String tenantId,
    required String op,
    required String entity,
    required String entityId,
    required String payloadJson,
    required String clientMutationId,
    this.attempts = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.deadLetter = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  })
      : id = Value(id),
        tenantId = Value(tenantId),
        op = Value(op),
        entity = Value(entity),
        entityId = Value(entityId),
        payloadJson = Value(payloadJson),
        clientMutationId = Value(clientMutationId);
  static Insertable<OutboxEntry> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? op,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? payloadJson,
    Expression<String>? clientMutationId,
    Expression<int>? attempts,
    Expression<DateTime?>? nextRetryAt,
    Expression<bool>? deadLetter,
    Expression<String?>? lastError,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (op != null) 'op': op,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (clientMutationId != null) 'client_mutation_id': clientMutationId,
      if (attempts != null) 'attempts': attempts,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (deadLetter != null) 'dead_letter': deadLetter,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (clientMutationId.present) {
      map['client_mutation_id'] = Variable<String>(clientMutationId.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (deadLetter.present) {
      map['dead_letter'] = Variable<bool>(deadLetter.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('op: $op, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('clientMutationId: $clientMutationId, ')
          ..write('attempts: $attempts, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('deadLetter: $deadLetter, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write(')'))
        .toString();
  }
}

class $MenuDraftsTable extends MenuDrafts with TableInfo<$MenuDraftsTable, MenuDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MenuDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _docJsonMeta =
      const VerificationMeta('docJson');
  static const VerificationMeta _updatedByMeta =
      const VerificationMeta('updatedBy');
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> docJson = GeneratedColumn<String>(
      'doc_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  late final GeneratedColumn<String> updatedBy = GeneratedColumn<String>(
      'updated_by', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [tenantId, docJson, updatedBy, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'menu_drafts';
  @override
  VerificationContext validateIntegrity(Insertable<MenuDraft> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('doc_json')) {
      context.handle(_docJsonMeta,
          docJson.isAcceptableOrUnknown(data['doc_json']!, _docJsonMeta));
    }
    if (data.containsKey('updated_by')) {
      context.handle(_updatedByMeta,
          updatedBy.isAcceptableOrUnknown(data['updated_by']!, _updatedByMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tenantId};
  @override
  MenuDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MenuDraft(
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      docJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}doc_json'])!,
      updatedBy: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}updated_by']),
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $MenuDraftsTable createAlias(String alias) {
    return $MenuDraftsTable(attachedDatabase, alias);
  }
}

class MenuDraft extends DataClass implements Insertable<MenuDraft> {
  final String tenantId;
  final String docJson;
  final String? updatedBy;
  final DateTime updatedAt;
  const MenuDraft({required this.tenantId, required this.docJson, this.updatedBy, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tenant_id'] = Variable<String>(tenantId);
    map['doc_json'] = Variable<String>(docJson);
    if (!nullToAbsent || updatedBy != null) {
      map['updated_by'] = Variable<String>(updatedBy);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }
  MenuDraftsCompanion toCompanion(bool nullToAbsent) {
    return MenuDraftsCompanion(
      tenantId: Value(tenantId),
      docJson: Value(docJson),
      updatedBy: updatedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedBy),
      updatedAt: Value(updatedAt),
    );
  }
  factory MenuDraft.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MenuDraft(
      tenantId: serializer.fromJson<String>(json['tenantId']),
      docJson: serializer.fromJson<String>(json['docJson']),
      updatedBy: serializer.fromJson<String?>(json['updatedBy']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tenantId': serializer.toJson<String>(tenantId),
      'docJson': serializer.toJson<String>(docJson),
      'updatedBy': serializer.toJson<String?>(updatedBy),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MenuDraft copyWith(
          {String? tenantId,
          String? docJson,
          Value<String?> updatedBy = const Value.absent(),
          DateTime? updatedAt}) =>
      MenuDraft(
        tenantId: tenantId ?? this.tenantId,
        docJson: docJson ?? this.docJson,
        updatedBy: updatedBy.present ? updatedBy.value : this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('MenuDraft(')
          ..write('tenantId: $tenantId, ')
          ..write('docJson: $docJson, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tenantId, docJson, updatedBy, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MenuDraft &&
          other.tenantId == this.tenantId &&
          other.docJson == this.docJson &&
          other.updatedBy == this.updatedBy &&
          other.updatedAt == this.updatedAt);
}

class MenuDraftsCompanion extends UpdateCompanion<MenuDraft> {
  final Value<String> tenantId;
  final Value<String> docJson;
  final Value<String?> updatedBy;
  final Value<DateTime> updatedAt;
  const MenuDraftsCompanion({
    this.tenantId = const Value.absent(),
    this.docJson = const Value.absent(),
    this.updatedBy = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MenuDraftsCompanion.insert({
    required String tenantId,
    this.docJson = const Value.absent(),
    this.updatedBy = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : tenantId = Value(tenantId);
  static Insertable<MenuDraft> custom({
    Expression<String>? tenantId,
    Expression<String>? docJson,
    Expression<String>? updatedBy,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (tenantId != null) 'tenant_id': tenantId,
      if (docJson != null) 'doc_json': docJson,
      if (updatedBy != null) 'updated_by': updatedBy,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (docJson.present) {
      map['doc_json'] = Variable<String>(docJson.value);
    }
    if (updatedBy.present) {
      map['updated_by'] = Variable<String>(updatedBy.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('MenuDraftsCompanion(')
          ..write('tenantId: $tenantId, ')
          ..write('docJson: $docJson, ')
          ..write('updatedBy: $updatedBy, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
}

class $MembershipsTable extends Memberships with TableInfo<$MembershipsTable, Membership> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembershipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta =
      const VerificationMeta('id');
  static const VerificationMeta _tenantIdMeta =
      const VerificationMeta('tenantId');
  static const VerificationMeta _userIdMeta =
      const VerificationMeta('userId');
  static const VerificationMeta _roleMeta =
      const VerificationMeta('role');
  static const VerificationMeta _tenantNameMeta =
      const VerificationMeta('tenantName');
  static const VerificationMeta _invitedPhoneMeta =
      const VerificationMeta('invitedPhone');
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
      'tenant_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tenantName = GeneratedColumn<String>(
      'tenant_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: false,
      defaultValue: const Constant(''));
  late final GeneratedColumn<String> invitedPhone = GeneratedColumn<String>(
      'invited_phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool, requiredDuringInsert: false,
      defaultValue: const Constant(false));
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, tenantId, userId, role, tenantName, invitedPhone, isActive, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memberships';
  @override
  VerificationContext validateIntegrity(Insertable<Membership> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta,
          id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(_tenantIdMeta,
          tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta));
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(_roleMeta,
          role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('tenant_name')) {
      context.handle(_tenantNameMeta,
          tenantName.isAcceptableOrUnknown(data['tenant_name']!, _tenantNameMeta));
    }
    if (data.containsKey('invited_phone')) {
      context.handle(_invitedPhoneMeta,
          invitedPhone.isAcceptableOrUnknown(data['invited_phone']!, _invitedPhoneMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Membership map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Membership(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tenantId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_id'])!,
      userId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      role: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      tenantName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tenant_name'])!,
      invitedPhone: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}invited_phone']),
      isActive: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $MembershipsTable createAlias(String alias) {
    return $MembershipsTable(attachedDatabase, alias);
  }
}

class Membership extends DataClass implements Insertable<Membership> {
  final String id;
  final String tenantId;
  final String userId;
  final String role;
  final String tenantName;
  final String? invitedPhone;
  final bool isActive;
  final DateTime updatedAt;
  const Membership({required this.id, required this.tenantId, required this.userId, required this.role, required this.tenantName, this.invitedPhone, required this.isActive, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['user_id'] = Variable<String>(userId);
    map['role'] = Variable<String>(role);
    map['tenant_name'] = Variable<String>(tenantName);
    if (!nullToAbsent || invitedPhone != null) {
      map['invited_phone'] = Variable<String>(invitedPhone);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }
  MembershipsCompanion toCompanion(bool nullToAbsent) {
    return MembershipsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      userId: Value(userId),
      role: Value(role),
      tenantName: Value(tenantName),
      invitedPhone: Value(invitedPhone),
      isActive: Value(isActive),
      updatedAt: Value(updatedAt),
    );
  }
  factory Membership.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Membership(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      userId: serializer.fromJson<String>(json['userId']),
      role: serializer.fromJson<String>(json['role']),
      tenantName: serializer.fromJson<String>(json['tenantName']),
      invitedPhone: serializer.fromJson<String?>(json['invitedPhone']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'userId': serializer.toJson<String>(userId),
      'role': serializer.toJson<String>(role),
      'tenantName': serializer.toJson<String>(tenantName),
      'invitedPhone': serializer.toJson<String?>(invitedPhone),
      'isActive': serializer.toJson<bool>(isActive),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }
  Membership copyWith({String? id, String? tenantId, String? userId, String? role, String? tenantName, Value<String?> invitedPhone = const Value.absent(), bool? isActive, DateTime? updatedAt}) => Membership(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        userId: userId ?? this.userId,
        role: role ?? this.role,
        tenantName: tenantName ?? this.tenantName,
        invitedPhone: invitedPhone.present ? invitedPhone.value : this.invitedPhone,
        isActive: isActive ?? this.isActive,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Membership(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('tenantName: $tenantName, ')
          ..write('invitedPhone: $invitedPhone, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
  @override
  int get hashCode => Object.hash(id, tenantId, userId, role, tenantName, invitedPhone, isActive, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Membership &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.userId == this.userId &&
          other.role == this.role &&
          other.tenantName == this.tenantName &&
          other.invitedPhone == this.invitedPhone &&
          other.isActive == this.isActive &&
          other.updatedAt == this.updatedAt);
}

class MembershipsCompanion extends UpdateCompanion<Membership> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> userId;
  final Value<String> role;
  final Value<String> tenantName;
  final Value<String?> invitedPhone;
  final Value<bool> isActive;
  final Value<DateTime> updatedAt;
  const MembershipsCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.userId = const Value.absent(),
    this.role = const Value.absent(),
    this.tenantName = const Value.absent(),
    this.invitedPhone = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MembershipsCompanion.insert({
    required String id,
    required String tenantId,
    required String userId,
    required String role,
    this.tenantName = const Value.absent(),
    this.invitedPhone = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })
      : id = Value(id),
        tenantId = Value(tenantId),
        userId = Value(userId),
        role = Value(role);
  static Insertable<Membership> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? userId,
    Expression<String>? role,
    Expression<String>? tenantName,
    Expression<String?>? invitedPhone,
    Expression<bool>? isActive,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (userId != null) 'user_id': userId,
      if (role != null) 'role': role,
      if (tenantName != null) 'tenant_name': tenantName,
      if (invitedPhone != null) 'invited_phone': invitedPhone,
      if (isActive != null) 'is_active': isActive,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (tenantName.present) {
      map['tenant_name'] = Variable<String>(tenantName.value);
    }
    if (invitedPhone.present) {
      map['invited_phone'] = Variable<String>(invitedPhone.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }
  @override
  String toString() {
    return (StringBuffer('MembershipsCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('tenantName: $tenantName, ')
          ..write('invitedPhone: $invitedPhone, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write(')'))
        .toString();
  }
}

abstract class _$TchopDatabase extends GeneratedDatabase {
  _$TchopDatabase(QueryExecutor e) : super(e);
  late final $TenantsTable tenants = $TenantsTable(this);
  late final $MenuSnapshotsTable menuSnapshots = $MenuSnapshotsTable(this);
  late final $MenuDraftsTable menuDrafts = $MenuDraftsTable(this);
  late final $ItemAvailabilitiesTable itemAvailabilities = $ItemAvailabilitiesTable(this);
  late final $OrdersTable orders = $OrdersTable(this);
  late final $DeliveriesTable deliveries = $DeliveriesTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  late final $MembershipsTable memberships = $MembershipsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        tenants,
        menuSnapshots,
        menuDrafts,
        itemAvailabilities,
        orders,
        deliveries,
        outboxEntries,
        memberships,
      ];
}
