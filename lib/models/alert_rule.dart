import 'dart:convert';

const ruleAny = 'any';
const ruleIncrease = 'increase';
const ruleDecrease = 'decrease';
const ruleEq = 'eq';
const ruleLte = 'lte';
const ruleGte = 'gte';

/// Operators shown in the rule editor, in display order.
const alertRuleOps = {
  ruleAny: 'Qualquer mudança',
  ruleIncrease: 'Aumentou',
  ruleDecrease: 'Diminuiu',
  ruleEq: 'Ficou igual a',
  ruleLte: 'Ficou menor ou igual a',
  ruleGte: 'Ficou maior ou igual a',
};

/// One notification condition of a monitored query. Rules are evaluated only
/// when the count changes; the first matching rule fires (see [firstMatch]).
class AlertRule {
  const AlertRule({
    this.op = ruleAny,
    this.value,
    this.titleTemplate,
    this.bodyTemplate,
  });

  final String op;

  /// Threshold for [ruleEq], [ruleLte] and [ruleGte].
  final int? value;

  /// Optional templates; empty/null falls back to the global ones.
  final String? titleTemplate;
  final String? bodyTemplate;

  bool get needsValue => op == ruleEq || op == ruleLte || op == ruleGte;

  /// `lte`/`gte` fire only when the count *crosses* the threshold, so a
  /// "≤ 1" rule fires on 3→1 but not again on 1→0.
  bool matches(int previous, int current) {
    final v = value;
    if (needsValue && v == null) return false;
    return switch (op) {
      ruleIncrease => current > previous,
      ruleDecrease => current < previous,
      ruleEq => current == v,
      ruleLte => current <= v! && previous > v,
      ruleGte => current >= v! && previous < v,
      _ => true,
    };
  }

  String get label => switch (op) {
        ruleIncrease => '↑ Aumento',
        ruleDecrease => '↓ Diminuição',
        ruleEq => '= $value',
        ruleLte => '≤ $value',
        ruleGte => '≥ $value',
        _ => '↕ Qualquer',
      };

  static AlertRule? firstMatch(List<AlertRule> rules, int previous, int current) {
    for (final rule in rules) {
      if (rule.matches(previous, current)) return rule;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'op': op,
        if (value != null) 'value': value,
        if (titleTemplate != null) 'title': titleTemplate,
        if (bodyTemplate != null) 'body': bodyTemplate,
      };

  static AlertRule fromJson(Map<String, dynamic> json) => AlertRule(
        op: json['op'] as String? ?? ruleAny,
        value: json['value'] as int?,
        titleTemplate: _blankToNull(json['title'] as String?),
        bodyTemplate: _blankToNull(json['body'] as String?),
      );

  static String listToJson(List<AlertRule> rules) =>
      jsonEncode(rules.map((r) => r.toJson()).toList());

  /// Null when [raw] is empty, so callers can fall back to legacy columns.
  static List<AlertRule>? listFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return (jsonDecode(raw) as List)
        .map((e) => AlertRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Converts the pre-rules fields (`alert_on` + per-query templates).
  static AlertRule fromLegacy(String? alertOn, String? title, String? body) => AlertRule(
        op: alertOn ?? ruleAny,
        titleTemplate: _blankToNull(title),
        bodyTemplate: _blankToNull(body),
      );
}

String? _blankToNull(String? value) =>
    value == null || value.trim().isEmpty ? null : value;
