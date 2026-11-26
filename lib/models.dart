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

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

int _minutes(Object? value) {
  final parts = (value as String).split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// One line of a group's weekly pattern, e.g. "Tue 6:00-7:00 AM".
class WeeklySession {
  WeeklySession({
    required this.id,
    required this.weekday,
    required this.start,
    required this.end,
    required this.startsOn,
    this.endsOn,
    this.label,
    this.venue,
  });

  factory WeeklySession.fromRow(Map<String, dynamic> row) => WeeklySession(
    id: row['id'] as String,
    weekday: (row['weekday'] as num).toInt(),
    start: _minutes(row['start_time']),
    end: _minutes(row['end_time']),
    startsOn: _date(row['starts_on'])!,
    endsOn: _date(row['ends_on']),
    label: row['label'] as String?,
    venue: row['venue'] as String?,
  );

  final String id;
  final int weekday; // 1 = Monday ... 7 = Sunday
  final int start; // minutes after midnight
  final int end;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String? label;
  final String? venue;
}

/// One real training session on one date.
class TrainingSession {
  TrainingSession({
    required this.id,
    required this.groupId,
    required this.date,
    required this.start,
    required this.end,
    this.label,
    this.venue,
    this.cancelled = false,
    this.cancelReason,
    this.restDayId,
    this.oneOff = false,
  });

  factory TrainingSession.fromRow(Map<String, dynamic> row) => TrainingSession(
    id: row['id'] as String,
    groupId: row['group_id'] as String,
    date: _date(row['session_date'])!,
    start: _minutes(row['start_time']),
    end: _minutes(row['end_time']),
    label: row['label'] as String?,
    venue: row['venue'] as String?,
    cancelled: row['status'] == 'cancelled',
    cancelReason: row['cancel_reason'] as String?,
    restDayId: row['rest_day_id'] as String?,
    oneOff: row['weekly_session_id'] == null,
  );

  final String id;
  final String groupId;
  final DateTime date;
  final int start;
  final int end;
  final String? label;
  final String? venue;
  final bool cancelled;
  final String? cancelReason;
  final String? restDayId;
  final bool oneOff;
}

/// A rest day or break, for one group or (groupId null) the whole club.
class RestDay {
  RestDay({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.isBreak,
    this.groupId,
    this.title,
  });

  factory RestDay.fromRow(Map<String, dynamic> row) => RestDay(
    id: row['id'] as String,
    groupId: row['group_id'] as String?,
    startDate: _date(row['start_date'])!,
    endDate: _date(row['end_date'])!,
    isBreak: row['kind'] == 'break',
    title: row['title'] as String?,
  );

  final String id;
  final String? groupId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isBreak;
  final String? title;

  String get name =>
      title?.isNotEmpty == true ? title! : (isBreak ? 'Break' : 'Rest day');
}

/// One line of a swimmer's own calendar (from swimmer_schedule).
class ScheduleEntry {
  ScheduleEntry({
    required this.date,
    required this.groupId,
    required this.groupName,
    required this.status,
    this.sessionId,
    this.start,
    this.end,
    this.label,
    this.venue,
    this.note,
  });

  factory ScheduleEntry.fromRow(Map<String, dynamic> row) => ScheduleEntry(
    date: _date(row['session_date'])!,
    groupId: row['group_id'] as String,
    groupName: row['group_name'] as String? ?? '',
    status: row['status'] as String? ?? 'scheduled',
    sessionId: row['session_id'] as String?,
    start: row['start_time'] == null ? null : _minutes(row['start_time']),
    end: row['end_time'] == null ? null : _minutes(row['end_time']),
    label: row['label'] as String?,
    venue: row['venue'] as String?,
    note: row['note'] as String?,
  );

  final DateTime date;
  final String groupId;
  final String groupName;
  final String status; // scheduled, cancelled or rest
  final String? sessionId;
  final int? start;
  final int? end;
  final String? label;
  final String? venue;
  final String? note;

  bool get isRest => status == 'rest';
  bool get isCancelled => status == 'cancelled';
}

/// One swimmer on a session's attendance list (from session_roster).
class RosterEntry {
  RosterEntry({
    required this.swimmerId,
    required this.firstName,
    required this.lastName,
    this.status,
    this.excuseReason,
    this.note,
    this.markedAt,
    this.markedBy,
  });

  factory RosterEntry.fromRow(Map<String, dynamic> row) => RosterEntry(
    swimmerId: row['swimmer_id'] as String,
    firstName: row['first_name'] as String? ?? '',
    lastName: row['last_name'] as String? ?? '',
    status: row['status'] as String?,
    excuseReason: row['excuse_reason'] as String?,
    note: row['note'] as String?,
    markedAt: row['marked_at'] == null
        ? null
        : DateTime.parse(row['marked_at'] as String).toLocal(),
    markedBy: row['marked_by_name'] as String?,
  );

  final String swimmerId;
  final String firstName;
  final String lastName;
  final String? status; // null = not marked yet
  final String? excuseReason;
  final String? note;
  final DateTime? markedAt;
  final String? markedBy;

  String get fullName => '$firstName $lastName';
}

/// One session in the coach's attendance overview, with how many
/// swimmers are marked (from club_attendance_overview).
class SessionOverview {
  SessionOverview({
    required this.sessionId,
    required this.groupId,
    required this.groupName,
    required this.groupLevel,
    required this.date,
    required this.start,
    required this.end,
    required this.marked,
    required this.swimmers,
    this.groupColour,
    this.label,
    this.venue,
    this.cancelled = false,
    this.note,
    this.lastMarkedAt,
    this.lastMarkedBy,
  });

  factory SessionOverview.fromRow(Map<String, dynamic> row) => SessionOverview(
    sessionId: row['session_id'] as String,
    groupId: row['group_id'] as String,
    groupName: row['group_name'] as String? ?? '',
    groupLevel: (row['group_level'] as num?)?.toInt() ?? 1,
    groupColour: row['group_colour'] as String?,
    date: _date(row['session_date'])!,
    start: _minutes(row['start_time']),
    end: _minutes(row['end_time']),
    label: row['label'] as String?,
    venue: row['venue'] as String?,
    cancelled: row['status'] == 'cancelled',
    note: row['cancel_reason'] as String?,
    marked: (row['marked'] as num?)?.toInt() ?? 0,
    swimmers: (row['swimmers'] as num?)?.toInt() ?? 0,
    lastMarkedAt: row['last_marked_at'] == null
        ? null
        : DateTime.parse(row['last_marked_at'] as String).toLocal(),
    lastMarkedBy: row['last_marked_by'] as String?,
  );

  final String sessionId;
  final String groupId;
  final String groupName;
  final int groupLevel;
  final String? groupColour;
  final DateTime date;
  final int start;
  final int end;
  final String? label;
  final String? venue;
  final bool cancelled;
  final String? note; // cancel reason or rest day name
  final int marked; // swimmers with a mark
  final int swimmers; // swimmers in the group that day
  final DateTime? lastMarkedAt;
  final String? lastMarkedBy;

  bool get isMarked => marked > 0;
}

/// One of a swimmer's attendance marks (from swimmer_attendance).
class AttendanceRecord {
  AttendanceRecord({
    required this.sessionId,
    required this.date,
    required this.start,
    required this.end,
    required this.groupName,
    required this.status,
    this.label,
    this.excuseReason,
    this.note,
  });

  factory AttendanceRecord.fromRow(Map<String, dynamic> row) =>
      AttendanceRecord(
        sessionId: row['session_id'] as String,
        date: _date(row['session_date'])!,
        start: _minutes(row['start_time']),
        end: _minutes(row['end_time']),
        label: row['label'] as String?,
        groupName: row['group_name'] as String? ?? '',
        status: row['status'] as String,
        excuseReason: row['excuse_reason'] as String?,
        note: row['note'] as String?,
      );

  final String sessionId;
  final DateTime date;
  final int start;
  final int end;
  final String? label;
  final String groupName;
  final String status;
  final String? excuseReason;
  final String? note; // coaches only
}
