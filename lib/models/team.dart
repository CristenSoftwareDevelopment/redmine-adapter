import 'dart:convert';

class TeamMember {
  const TeamMember({required this.id, required this.name});

  /// Redmine user id.
  final int id;
  final String name;

  Map<String, Object> toJson() => {'id': id, 'name': name};

  static TeamMember fromJson(Map<String, dynamic> json) =>
      TeamMember(id: json['id'] as int, name: json['name'] as String? ?? '?');
}

/// Group of Redmine users whose spent time is reported together.
class Team {
  const Team({this.id, required this.name, this.members = const []});

  final int? id;
  final String name;
  final List<TeamMember> members;

  Map<String, Object?> toDbMap() => {
        'id': id,
        'name': name,
        'members': jsonEncode(members.map((m) => m.toJson()).toList()),
      };

  static Team fromDbMap(Map<String, Object?> map) => Team(
        id: map['id'] as int,
        name: map['name'] as String,
        members: (jsonDecode(map['members'] as String? ?? '[]') as List)
            .map((m) => TeamMember.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}
