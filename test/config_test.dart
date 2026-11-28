import 'package:flutter_test/flutter_test.dart';

import 'package:swimbase/config.dart';

void main() {
  const want = 'https://aqbdsfleqnfdyjashdck.supabase.co';

  test('Supabase address is cleaned up from common paste slips', () {
    for (final pasted in [
      'https://aqbdsfleqnfdyjashdck.supabase.co',
      'https://aqbdsfleqnfdyjashdck.supabase.co/',
      'https://aqbdsfleqnfdyjashdck.supabase.co/rest/v1/',
      'https://aqbdsfleqnfdyjashdck.supabase.co/rest/v1',
      'https://aqbdsfleqnfdyjashdck.supabase.co/auth/v1/',
      '  https://aqbdsfleqnfdyjashdck.supabase.co \n',
      '"https://aqbdsfleqnfdyjashdck.supabase.co"',
      'aqbdsfleqnfdyjashdck.supabase.co',
      'https://supabase.com/dashboard/project/aqbdsfleqnfdyjashdck',
      'https://supabase.com/dashboard/project/aqbdsfleqnfdyjashdck/settings/api',
    ]) {
      expect(cleanSupabaseUrl(pasted), want, reason: 'pasted: "$pasted"');
    }
  });

  test('Local addresses keep their port', () {
    expect(
      cleanSupabaseUrl('http://localhost:54321/rest/v1/'),
      'http://localhost:54321',
    );
  });

  test('Key is trimmed of spaces, line breaks and quotes', () {
    expect(cleanValue(' "sb_publishable_abc"\n'), 'sb_publishable_abc');
  });

  test('Empty stays empty', () {
    expect(cleanSupabaseUrl(''), '');
    expect(cleanValue('  '), '');
  });
}
