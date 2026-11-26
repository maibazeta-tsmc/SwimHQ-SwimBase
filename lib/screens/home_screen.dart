import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'club_screen.dart';

/// A simple first home screen: shows your clubs and lets you register a
/// club or enter an invite code. The real dashboards come in later phases.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _clubs = _loadClubs();

  static const _roleNames = {
    'head_coach': 'Head coach',
    'assistant_coach': 'Assistant coach',
    'swimmer': 'Swimmer',
    'parent': 'Parent',
  };

  Future<List<Map<String, dynamic>>> _loadClubs() async {
    final rows = await _db
        .from('club_members')
        .select(
          'role, can_create_groups, can_move_swimmers, '
          'clubs(id, name, status)',
        )
        .eq('user_id', _db.auth.currentUser!.id);
    return List<Map<String, dynamic>>.from(rows);
  }

  late Future<List<Map<String, dynamic>>> _pending = _loadPending();

  /// Clubs waiting for approval. Only filled for the superadmin; everyone
  /// else gets an empty list.
  Future<List<Map<String, dynamic>>> _loadPending() async {
    final isAdmin = await _db.rpc('is_superadmin') == true;
    if (!isAdmin) return [];
    final rows = await _db
        .from('clubs')
        .select('id, name, country, created_at, created_by')
        .eq('status', 'pending')
        .order('created_at');
    final clubs = List<Map<String, dynamic>>.from(rows);
    // Who registered each club (the superadmin can see every profile).
    final ids = [
      for (final c in clubs)
        if (c['created_by'] != null) c['created_by'] as String,
    ];
    if (ids.isNotEmpty) {
      final people = await _db
          .from('profiles')
          .select('id, full_name, email')
          .inFilter('id', ids);
      final byId = {for (final p in people) p['id']: p};
      for (final c in clubs) {
        c['registered_by'] = byId[c['created_by']];
      }
    }
    return clubs;
  }

  void _refresh() => setState(() {
    _clubs = _loadClubs();
    _pending = _loadPending();
  });

  Future<void> _approve(Map<String, dynamic> club) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve ${club['name']}?'),
        content: const Text(
          'The club goes live and its coaches can invite '
          'swimmers and parents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(
      () => _db.rpc('approve_club', params: {'p_club_id': club['id']}),
      '${club['name']} approved.',
    );
  }

  void _openClub(Membership club) {
    if (!club.isCoach) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Swimmer and parent screens are coming in a later '
            'update.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ClubScreen(club: club)));
  }

  Future<String?> _ask(String title, String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      _refresh();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _registerClub() async {
    final name = await _ask('Register a club', 'Club name');
    if (name == null || name.isEmpty) return;
    await _run(
      () => _db.rpc('register_club', params: {'p_name': name}),
      'Club registered. It will go live once it is approved.',
    );
  }

  Future<void> _enterCode() async {
    final code = await _ask('Enter an invite code', 'Code, e.g. KX7P-29QD');
    if (code == null || code.isEmpty) return;
    await _run(
      () => _db.rpc('redeem_invite_code', params: {'p_code': code}),
      'Code accepted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _db.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SwimBase'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _db.auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Signed in as ${user?.email ?? ''}'),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _pending,
              builder: (context, snapshot) {
                final pending = snapshot.data ?? const [];
                if (pending.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Clubs waiting for your approval',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final c in pending)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.pending_actions),
                          title: Text(c['name'] ?? ''),
                          subtitle: Text(
                            [
                              c['country'] ?? '',
                              if (c['registered_by'] != null)
                                'by ${c['registered_by']['full_name'] ?? ''} '
                                    '(${c['registered_by']['email'] ?? ''})',
                            ].join('  ·  '),
                          ),
                          trailing: FilledButton(
                            onPressed: () => _approve(c),
                            child: const Text('Approve'),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Your clubs', style: Theme.of(context).textTheme.titleLarge),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _clubs,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  final detail =
                      error is PostgrestException ? error.message : '$error';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Could not load your clubs. Pull to retry.\n'
                        'Details: $detail'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'You are not in a club yet. Enter the code '
                      'your coach gave you, or register your club.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final row in rows)
                      Card(
                        child: ListTile(
                          onTap: () => _openClub(Membership.fromRow(row)),
                          leading: const Icon(Icons.groups),
                          title: Text(row['clubs']?['name'] ?? ''),
                          subtitle: Text(
                            _roleNames[row['role']] ?? row['role'] ?? '',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (row['clubs']?['status'] == 'pending')
                                const Chip(label: Text('Waiting for approval')),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _enterCode,
              icon: const Icon(Icons.vpn_key),
              label: const Text('Enter an invite code'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _registerClub,
              icon: const Icon(Icons.add_business),
              label: const Text('Register a club (head coaches)'),
            ),
          ],
        ),
      ),
    );
  }
}
