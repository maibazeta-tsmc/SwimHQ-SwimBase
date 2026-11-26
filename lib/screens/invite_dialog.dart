import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/common.dart';

/// The web address people open to join. Shown next to each invite code.
const appAddress = 'https://maibazeta-tsmc.github.io/SwimHQ-SwimBase/';

/// Makes a one-time invite code and shows it, ready to copy and send.
/// [role] is 'assistant_coach', 'swimmer' or 'parent'; swimmer and parent
/// codes need [swimmerId]. Returns true if a code was made.
Future<bool> createAndShowInvite(
  BuildContext context, {
  required String clubId,
  required String role,
  String? swimmerId,
  required String forWhom,
}) async {
  String? code;
  final ok = await runAction(context, () async {
    code = await db.rpc(
      'create_invite_code',
      params: {'p_club_id': clubId, 'p_role': role, 'p_swimmer_id': swimmerId},
    ) as String;
  });
  if (!ok || code == null || !context.mounted) return false;
  await showInviteCode(context, code: code!, role: role, forWhom: forWhom);
  return true;
}

/// Shows an invite code with a message the coach can copy and send.
Future<void> showInviteCode(
  BuildContext context, {
  required String code,
  required String role,
  required String forWhom,
}) {
  final joinsAs = switch (role) {
    'assistant_coach' => 'as a coach',
    'swimmer' => 'as $forWhom',
    _ => 'as a parent of $forWhom',
  };
  final message =
      'Join our swim club on SwimBase $joinsAs.\n'
      '1. Open $appAddress\n'
      '2. Create an account (or sign in)\n'
      '3. Tap "Enter an invite code" and type: $code\n'
      'The code works once and expires in 7 days.';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(switch (role) {
        'assistant_coach' => 'Coach invite code',
        'swimmer' => 'Login code for $forWhom',
        _ => 'Parent code for $forWhom',
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SelectableText(
              code,
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Send this message by text, Messenger or email:'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(message),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Message copied.')));
            }
          },
          child: const Text('Copy message'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
