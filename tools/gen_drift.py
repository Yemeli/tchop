#!/usr/bin/env python3
"""Hand-written stand-in for `dart run build_runner build` (drift_dev).

The Flutter SDK is absent on this VM, so this script emits
`apps/tchop/lib/data/database/tchop_database.g.dart` following drift 2.28
codegen patterns by hand. Regenerate for real with:
    cd apps/tchop && dart run build_runner build --delete-conflicting-outputs

Spec: (table_class, row_class, sql_name, pk_getters, columns)
column: (getter, sql_name, dart_type, nullable, required_during_insert, default_expr)
"""

DRIFT_TYPE = {
    "String": "DriftSqlType.string",
    "int": "DriftSqlType.int",
    "bool": "DriftSqlType.bool",
    "DateTime": "DriftSqlType.dateTime",
}

TABLES = [
    ("Tenants", "Tenant", "tenants", ["id"], [
        ("id", "id", "String", False, True, None),
        ("name", "name", "String", False, True, None),
        ("brandJson", "brand_json", "String", False, False, "const Constant('{}')"),
        ("updatedAt", "updated_at", "DateTime", False, False, "currentDateAndTime"),
    ]),
    ("MenuSnapshots", "MenuSnapshot", "menu_snapshots", ["id"], [
        ("id", "id", "String", False, True, None),
        ("tenantId", "tenant_id", "String", False, True, None),
        ("version", "version", "int", False, True, None),
        ("itemsJson", "items_json", "String", False, False, "const Constant('[]')"),
        ("publishedAt", "published_at", "DateTime", True, False, None),
    ]),
    ("ItemAvailabilities", "ItemAvailability", "item_availability",
     ["tenantId", "itemId"], [
        ("tenantId", "tenant_id", "String", False, True, None),
        ("itemId", "item_id", "String", False, True, None),
        ("available", "available", "bool", False, False, "const Constant(true)"),
        ("updatedAt", "updated_at", "DateTime", False, False, "currentDateAndTime"),
    ]),
    ("Orders", "Order", "orders", ["id"], [
        ("id", "id", "String", False, True, None),
        ("tenantId", "tenant_id", "String", False, True, None),
        ("status", "status", "String", False, False, "const Constant('placed')"),
        ("paymentStatus", "payment_status", "String", False, False, "const Constant('pending')"),
        ("paymentMethod", "payment_method", "String", True, False, None),
        ("menuVersion", "menu_version", "int", False, False, "const Constant(1)"),
        ("linesJson", "lines_json", "String", False, False, "const Constant('[]')"),
        ("subtotalCents", "subtotal_cents", "int", False, False, "const Constant(0)"),
        ("deliveryFeeCents", "delivery_fee_cents", "int", False, False, "const Constant(0)"),
        ("totalCents", "total_cents", "int", False, False, "const Constant(0)"),
        ("clientMutationId", "client_mutation_id", "String", False, True, None),
        ("createdAt", "created_at", "DateTime", False, False, "currentDateAndTime"),
        ("updatedAt", "updated_at", "DateTime", False, False, "currentDateAndTime"),
    ]),
    ("Deliveries", "Delivery", "deliveries", ["id"], [
        ("id", "id", "String", False, True, None),
        ("tenantId", "tenant_id", "String", False, True, None),
        ("orderId", "order_id", "String", False, True, None),
        ("driverId", "driver_id", "String", True, False, None),
        ("pickedUpAt", "picked_up_at", "DateTime", True, False, None),
        ("deliveredAt", "delivered_at", "DateTime", True, False, None),
        ("podPhotoUrl", "pod_photo_url", "String", True, False, None),
        ("createdAt", "created_at", "DateTime", False, False, "currentDateAndTime"),
    ]),
    ("OutboxEntries", "OutboxEntry", "outbox_entries", ["id"], [
        ("id", "id", "String", False, True, None),
        ("tenantId", "tenant_id", "String", False, True, None),
        ("op", "op", "String", False, True, None),
        ("entity", "entity", "String", False, True, None),
        ("entityId", "entity_id", "String", False, True, None),
        ("payloadJson", "payload_json", "String", False, True, None),
        ("clientMutationId", "client_mutation_id", "String", False, True, None),
        ("attempts", "attempts", "int", False, False, "const Constant(0)"),
        ("nextRetryAt", "next_retry_at", "DateTime", True, False, None),
        ("deadLetter", "dead_letter", "bool", False, False, "const Constant(false)"),
        ("lastError", "last_error", "String", True, False, None),
        ("createdAt", "created_at", "DateTime", False, False, "currentDateAndTime"),
    ]),
]


def dart_type(t, nullable):
    return t + ("?" if nullable else "")


def gen_table(table, row, sql_name, pk, cols):
    o = []
    tcls = f"${table}Table"
    o.append(f"class {tcls} extends {table} with TableInfo<{tcls}, {row}> {{")
    o.append("  @override")
    o.append("  final GeneratedDatabase attachedDatabase;")
    o.append("  final String? _alias;")
    o.append(f"  {tcls}(this.attachedDatabase, [this._alias]);")
    for (getter, _sql, _t, _n, _r, _d) in cols:
        o.append(f"  static const VerificationMeta _{getter}Meta =")
        o.append(f"      const VerificationMeta('{getter}');")
    for (getter, sql, t, nullable, required, default) in cols:
        null_str = "true" if nullable else "false"
        o.append(f"  late final GeneratedColumn<{t}> {getter} = GeneratedColumn<{t}>(")
        o.append(f"      '{sql}', aliasedName, {null_str},")
        tail = ("      type: " + DRIFT_TYPE[t]
                + ", requiredDuringInsert: " + ("true" if required else "false"))
        if default:
            o.append(tail + ",")
            o.append(f"      defaultValue: {default});")
        else:
            o.append(tail + ");")
    o.append("  @override")
    o.append("  List<GeneratedColumn> get $columns => ["
             + ", ".join(g for (g, _s, _t, _n, _r, _d) in cols) + "];")
    o.append("  @override")
    o.append("  String get aliasedName => _alias ?? actualTableName;")
    o.append("  @override")
    o.append("  String get actualTableName => $name;")
    o.append(f"  static const String $name = '{sql_name}';")
    o.append("  @override")
    o.append(f"  VerificationContext validateIntegrity(Insertable<{row}> instance,")
    o.append("      {bool isInserting = false}) {")
    o.append("    final context = VerificationContext();")
    o.append("    final data = instance.toColumns(true);")
    for (getter, sql, _t, _n, required, _d) in cols:
        o.append(f"    if (data.containsKey('{sql}')) {{")
        o.append(f"      context.handle(_{getter}Meta,")
        o.append(f"          {getter}.isAcceptableOrUnknown(data['{sql}']!, _{getter}Meta));")
        if required:
            # Real drift codegen only flags columns that are required during
            # insert (non-nullable, no default). Defaulted/nullable columns
            # are filled by the DB or legitimately omitted.
            o.append("    } else if (isInserting) {")
            o.append(f"      context.missing(_{getter}Meta);")
        o.append("    }")
    o.append("    return context;")
    o.append("  }")
    o.append("")
    o.append("  @override")
    o.append("  Set<GeneratedColumn> get $primaryKey => {"
             + ", ".join(pk) + "};")
    o.append("  @override")
    o.append(f"  {row} map(Map<String, dynamic> data, {{String? tablePrefix}}) {{")
    o.append("    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';")
    o.append(f"    return {row}(")
    for (getter, sql, t, nullable, _r, _d) in cols:
        bang = "" if nullable else "!"
        o.append("      " + getter + ": attachedDatabase.typeMapping.read("
                 + DRIFT_TYPE[t] + ", data['${effectivePrefix}" + sql + "'])" + bang + ",")
    o.append("    );")
    o.append("  }")
    o.append("")
    o.append("  @override")
    o.append(f"  {tcls} createAlias(String alias) {{")
    o.append(f"    return {tcls}(attachedDatabase, alias);")
    o.append("  }")
    o.append("}")
    o.append("")
    return "\n".join(o)


def gen_row(table, row, cols):
    o = []
    o.append(f"class {row} extends DataClass implements Insertable<{row}> {{")
    for (getter, _s, t, nullable, _r, _d) in cols:
        o.append(f"  final {dart_type(t, nullable)} {getter};")
    params = []
    for (getter, _s, _t, nullable, _r, _d) in cols:
        params.append(f"this.{getter}" if nullable else f"required this.{getter}")
    o.append(f"  const {row}({{{', '.join(params)}}});")
    o.append("  @override")
    o.append("  Map<String, Expression> toColumns(bool nullToAbsent) {")
    o.append("    final map = <String, Expression>{};")
    for (getter, sql, t, nullable, _r, _d) in cols:
        if nullable:
            o.append(f"    if (!nullToAbsent || {getter} != null) {{")
            o.append(f"      map['{sql}'] = Variable<{t}>({getter});")
            o.append("    }")
        else:
            o.append(f"    map['{sql}'] = Variable<{t}>({getter});")
    o.append("    return map;")
    o.append("  }")
    o.append(f"  {table}Companion toCompanion(bool nullToAbsent) {{")
    o.append(f"    return {table}Companion(")
    for (getter, _s, _t, _n, _r, _d) in cols:
        o.append(f"      {getter}: Value({getter}),")
    o.append("    );")
    o.append("  }")
    o.append(f"  factory {row}.fromJson(Map<String, dynamic> json,")
    o.append("      {ValueSerializer? serializer}) {")
    o.append("    serializer ??= driftRuntimeOptions.defaultSerializer;")
    o.append(f"    return {row}(")
    for (getter, _s, t, nullable, _r, _d) in cols:
        o.append(f"      {getter}: serializer.fromJson<{dart_type(t, nullable)}>(json['{getter}']),")
    o.append("    );")
    o.append("  }")
    o.append("  @override")
    o.append("  Map<String, dynamic> toJson({ValueSerializer? serializer}) {")
    o.append("    serializer ??= driftRuntimeOptions.defaultSerializer;")
    o.append("    return <String, dynamic>{")
    for (getter, _s, t, nullable, _r, _d) in cols:
        o.append(f"      '{getter}': serializer.toJson<{dart_type(t, nullable)}>({getter}),")
    o.append("    };")
    o.append("  }")
    cparams = []
    for (getter, _s, t, nullable, _r, _d) in cols:
        if nullable:
            cparams.append(f"Value<{t}?> {getter} = const Value.absent()")
        else:
            cparams.append(f"{t}? {getter}")
    o.append(f"  {row} copyWith({{{', '.join(cparams)}}}) => {row}(")
    for (getter, _s, _t, nullable, _r, _d) in cols:
        if nullable:
            o.append(f"        {getter}: {getter}.present ? {getter}.value : this.{getter},")
        else:
            o.append(f"        {getter}: {getter} ?? this.{getter},")
    o.append("      );")
    o.append("  @override")
    o.append("  String toString() {")
    o.append(f"    return (StringBuffer('{row}(')")
    for (getter, _s, _t, _n, _r, _d) in cols:
        o.append(f"          ..write('{getter}: ${getter}, ')")
    o.append("          ..write(')'))")
    o.append("        .toString();")
    o.append("  }")
    o.append("  @override")
    o.append("  int get hashCode => Object.hash("
             + ", ".join(g for (g, _s, _t, _n, _r, _d) in cols) + ");")
    o.append("  @override")
    o.append("  bool operator ==(Object other) =>")
    o.append("      identical(this, other) ||")
    o.append(f"      (other is {row} &&")
    o.append("          " + " &&\n          ".join(
        f"other.{g} == this.{g}" for (g, _s, _t, _n, _r, _d) in cols) + ");")
    o.append("}")
    o.append("")
    return "\n".join(o)


def gen_companion(table, row, cols):
    o = []
    o.append(f"class {table}Companion extends UpdateCompanion<{row}> {{")
    for (getter, _s, t, nullable, _r, _d) in cols:
        o.append(f"  final Value<{dart_type(t, nullable)}> {getter};")
    o.append(f"  const {table}Companion({{")
    for (getter, _s, _t, _n, _r, _d) in cols:
        o.append(f"    this.{getter} = const Value.absent(),")
    o.append("  });")
    iparams, inits = [], []
    for (getter, _s, t, nullable, required, _d) in cols:
        if required:
            iparams.append(f"required {dart_type(t, nullable)} {getter}")
            inits.append(f"{getter} = Value({getter})")
        else:
            iparams.append(f"this.{getter} = const Value.absent()")
    o.append(f"  {table}Companion.insert({{")
    for p in iparams:
        o.append(f"    {p},")
    o.append("  })")
    o.append("      : " + ",\n        ".join(inits) + ";")
    o.append(f"  static Insertable<{row}> custom({{")
    for (getter, _s, t, nullable, _r, _d) in cols:
        o.append(f"    Expression<{dart_type(t, nullable)}>? {getter},")
    o.append("  }) {")
    o.append("    return RawValuesInsertable({")
    for (getter, sql, _t, _n, _r, _d) in cols:
        o.append(f"      if ({getter} != null) '{sql}': {getter},")
    o.append("    });")
    o.append("  }")
    o.append("  @override")
    o.append("  Map<String, Expression> toColumns(bool nullToAbsent) {")
    o.append("    final map = <String, Expression>{};")
    for (getter, sql, t, _n, _r, _d) in cols:
        o.append(f"    if ({getter}.present) {{")
        o.append(f"      map['{sql}'] = Variable<{t}>({getter}.value);")
        o.append("    }")
    o.append("    return map;")
    o.append("  }")
    o.append("  @override")
    o.append("  String toString() {")
    o.append(f"    return (StringBuffer('{table}Companion(')")
    for (getter, _s, _t, _n, _r, _d) in cols:
        o.append(f"          ..write('{getter}: ${getter}, ')")
    o.append("          ..write(')'))")
    o.append("        .toString();")
    o.append("  }")
    o.append("}")
    o.append("")
    return "\n".join(o)


def main():
    import os
    out = []
    out.append("// GENERATED CODE - DO NOT MODIFY BY HAND")
    out.append("// Hand-written on a VM without the Flutter SDK (FEATURE 1).")
    out.append("// Regenerate with:")
    out.append("//   cd apps/tchop && dart run build_runner build --delete-conflicting-outputs")
    out.append("// ignore_for_file: type=lint")
    out.append("")
    out.append("part of 'tchop_database.dart';")
    out.append("")
    for (table, row, sql_name, pk, cols) in TABLES:
        out.append(gen_table(table, row, sql_name, pk, cols))
        out.append(gen_row(table, row, cols))
        out.append(gen_companion(table, row, cols))
    out.append("abstract class _$TchopDatabase extends GeneratedDatabase {")
    out.append("  _$TchopDatabase(QueryExecutor e) : super(e);")
    for (table, _r, _s, _p, _c) in TABLES:
        getter = table[0].lower() + table[1:]
        out.append(f"  late final ${table}Table {getter} = ${table}Table(this);")
    out.append("  @override")
    out.append("  Iterable<TableInfo<Table, Object?>> get allTables =>")
    out.append("      allSchemaEntities.whereType<TableInfo<Table, Object?>>();")
    out.append("  @override")
    out.append("  List<DatabaseSchemaEntity> get allSchemaEntities => [")
    for (table, _r, _s, _p, _c) in TABLES:
        getter = table[0].lower() + table[1:]
        out.append(f"        {getter},")
    out.append("      ];")
    out.append("}")
    out.append("")
    target = os.path.expanduser(
        "~/workspace/tchop/apps/tchop/lib/data/database/tchop_database.g.dart")
    with open(target, "w") as f:
        f.write("\n".join(out))
    print("wrote", target)


if __name__ == "__main__":
    main()
