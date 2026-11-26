// The small pieces of data the coach screens work with, read from Supabase.
// Each class turns one database row (a Map) into named fields, so the
// screens can say `group.name` instead of `row['name']`.

/// One of the signed-in person's roles in one club.
class Membership {
  Membership({
    required this.clubId,
    required this.clubName,
    required this.clubStatus,
    required this.role,
    required this.canCreateGroups,
    required this.canMoveSwimmers,
  });

  factory Membership.fromRow(Map<String, dynamic> row) {
    final club = (row['clubs'] as Map?) ?? const {};
    return Membership(
      clubId: club['id'] as String? ?? '',
      clubName: club['name'] as String? ?? '',
      clubStatus: club['status'] as String? ?? 'pending',
      role: row['role'] as String? ?? '',
      canCreateGroups: row['can_create_groups'] == true,
      canMoveSwimmers: row['can_move_swimmers'] == true,
    );
  }

  final String clubId;
  final String clubName;
  final String clubStatus;
  final String role;
  final bool canCreateGroups;
  final bool canMoveSwimmers;

  bool get isHeadCoach => role == 'head_coach';
  bool get isCoach => role == 'head_coach' || role == 'assistant_coach';
  bool get isPending => clubStatus == 'pending';

  /// Create, edit and archive groups (head coach, or a switched-on assistant).
  bool get canManageGroups => isHeadCoach || canCreateGroups;

  /// Move swimmers between groups (head coach, or a switched-on assistant).
  bool get canMove => isHeadCoach || canMoveSwimmers;
}

/// A training group, like "Gold (level 3)".
class Group {
  Group({
    required this.id,
    required this.name,
    required this.level,
    this.colour,
    this.description,
    this.archived = false,
  });

  factory Group.fromRow(Map<String, dynamic> row) => Group(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    level: (row['level'] as num?)?.toInt() ?? 1,
    colour: row['colour'] as String?,
    description: row['description'] as String?,
    archived: row['archived_at'] != null,
  );

  final String id;
  final String name;
  final int level;
  final String? colour;
  final String? description;
  final bool archived;
}

/// A swimmer's record, kept by the coaches.
class Swimmer {
  Swimmer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.gender,
    this.currentGroupId,
    this.hasLogin = false,
  });

  factory Swimmer.fromRow(Map<String, dynamic> row) => Swimmer(
    id: row['id'] as String,
    firstName: row['first_name'] as String? ?? '',
    lastName: row['last_name'] as String? ?? '',
    birthDate: DateTime.parse(row['birth_date'] as String),
    gender: row['gender'] as String? ?? 'female',
    currentGroupId: row['current_group_id'] as String?,
    hasLogin: row['user_id'] != null,
  );

  final String id;
  final String firstName;
  final String lastName;
  final DateTime birthDate;
  final String gender;
  final String? currentGroupId;
  final bool hasLogin;

  String get fullName => '$firstName $lastName';
}

/// The columns the screens read from the swimmers table.
const swimmerColumns =
    'id, first_name, last_name, birth_date, gender, current_group_id, user_id';
