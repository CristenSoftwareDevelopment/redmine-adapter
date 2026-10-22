import 'dart:convert';

/// Redmine custom field formats the app edits, with their pt-BR names.
const fieldFormats = {
  'string': 'Texto',
  'text': 'Texto longo',
  'int': 'Inteiro',
  'float': 'Decimal',
  'date': 'Data',
  'bool': 'Sim/Não',
  'list': 'Lista',
  'enumeration': 'Lista chave/valor',
  'user': 'Usuário',
  'version': 'Versão',
  'link': 'Link',
};

/// Type and choices of an issue custom field. Same JSON as Redmine's
/// `/custom_fields.json` (admin only), so the import and the saved settings
/// share one parser; without admin the type is guessed by [CustomFieldDef.infer].
class CustomFieldDef {
  const CustomFieldDef({
    required this.id,
    required this.name,
    this.format = 'string',
    this.multiple = false,
    this.options = const [],
    this.trackerIds = const [],
    this.defaultValue,
  });

  final int id;
  final String name;

  /// Redmine `field_format`; the ones in [fieldFormats] are editable.
  final String format;
  final bool multiple;

  /// (value, label) of `list` (label = value) and `enumeration` (value = id) fields.
  final List<(String, String)> options;

  /// Trackers that have the field; empty = unknown.
  final List<int> trackerIds;
  final String? defaultValue;

  bool get hasOptions => format == 'list' || format == 'enumeration';

  CustomFieldDef copyWith({String? format, bool? multiple, List<(String, String)>? options}) =>
      CustomFieldDef(
        id: id,
        name: name,
        format: format ?? this.format,
        multiple: multiple ?? this.multiple,
        options: options ?? this.options,
        trackerIds: trackerIds,
        defaultValue: defaultValue,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'field_format': format,
        'multiple': multiple,
        'possible_values': [
          for (final (value, label) in options) {'value': value, 'label': label},
        ],
        'trackers': [
          for (final t in trackerIds) {'id': t},
        ],
        'default_value': defaultValue,
      };

  static CustomFieldDef fromJson(Map json) => CustomFieldDef(
        id: json['id'] as int,
        name: '${json['name'] ?? '#${json['id']}'}',
        format: json['field_format'] as String? ?? 'string',
        multiple: json['multiple'] == true,
        options: [
          for (final p in (json['possible_values'] as List? ?? const []).whereType<Map>())
            ('${p['value']}', '${p['label'] ?? p['value']}'),
        ],
        trackerIds: [
          for (final t in (json['trackers'] as List? ?? const []).whereType<Map>()) t['id'] as int,
        ],
        defaultValue: switch (json['default_value']) {
          final String v when v.isNotEmpty => v,
          _ => null,
        },
      );

  /// Guess from values seen on issues (no admin key): only 0/1 → bool, dates,
  /// numbers, line breaks → long text, few repeated values → list of them.
  // ponytail: heuristic; the user fixes the type in Configurações › Campos.
  factory CustomFieldDef.infer({
    required int id,
    required String name,
    required Iterable<Object?> values,
    bool multiple = false,
    List<int> trackerIds = const [],
  }) {
    final seen = [
      for (final v in values)
        if (v is List) ...v.map((e) => '$e') else if (v != null) '$v',
    ].where((v) => v.isNotEmpty).toList();
    final distinct = {...seen}.toList()..sort();
    bool all(String pattern) => seen.isNotEmpty && seen.every(RegExp(pattern).hasMatch);
    final format = all(r'^[01]$')
        ? 'bool'
        : all(r'^\d{4}-\d{2}-\d{2}$')
            ? 'date'
            : all(r'^-?\d+$')
                ? 'int'
                : all(r'^-?\d+([.,]\d+)?$')
                    ? 'float'
                    : seen.any((v) => v.contains('\n'))
                        ? 'text'
                        : multiple ||
                                (distinct.isNotEmpty &&
                                    distinct.length <= 20 &&
                                    seen.length >= distinct.length * 2)
                            ? 'list'
                            : 'string';
    return CustomFieldDef(
      id: id,
      name: name,
      format: format,
      multiple: multiple,
      options: format == 'list' ? [for (final v in distinct) (v, v)] : const [],
      trackerIds: trackerIds,
    );
  }

  static String listToJson(List<CustomFieldDef> defs) =>
      jsonEncode(defs.map((d) => d.toJson()).toList());

  static List<CustomFieldDef> listFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return (jsonDecode(raw) as List).whereType<Map>().map(CustomFieldDef.fromJson).toList();
  }
}

/// Custom fields seen on [issues] (`/issues.json` items), with types guessed by
/// [CustomFieldDef.infer] and the trackers they showed up on. Sorted by name.
List<CustomFieldDef> scanCustomFields(List<Map> issues) {
  final names = <int, String>{};
  final values = <int, List<Object?>>{};
  final trackers = <int, Set<int>>{};
  final multiple = <int>{};
  for (final issue in issues) {
    final tracker = (issue['tracker'] as Map?)?['id'] as int?;
    for (final f in (issue['custom_fields'] as List? ?? const []).whereType<Map>()) {
      final id = f['id'] as int;
      names[id] = '${f['name']}';
      (values[id] ??= []).add(f['value']);
      if (tracker != null) (trackers[id] ??= {}).add(tracker);
      if (f['multiple'] == true) multiple.add(id);
    }
  }
  return [
    for (final MapEntry(key: id, value: name) in names.entries)
      CustomFieldDef.infer(
        id: id,
        name: name,
        values: values[id]!,
        multiple: multiple.contains(id),
        trackerIds: [...?trackers[id]]..sort(),
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
