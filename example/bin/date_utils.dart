// ignore_for_file: avoid_print
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  Date Manipulation with Day.js & Moment.js — from Dart
/// ═══════════════════════════════════════════════════════════════
///
/// This example shows how to use popular JS date libraries for
/// parsing, formatting, and manipulating dates — all from Dart.
///
/// What you'll see:
///   1. Parse dates from strings
///   2. Format dates with custom patterns
///   3. Add/subtract time
///   4. Compare dates (isBefore, isAfter, diff)
///   5. Get date components (year, month, day)
///   6. Relative time ("3 hours ago")
///   7. UTC handling
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add dayjs moment
///
/// Run:
///   dart run example/bin/date_utils.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('📅 flutter_js_bridger — Date Utilities Example\n');

    // ──────────────────────────────────────────────────
    //  Part A: Day.js — Lightweight (2KB)
    // ──────────────────────────────────────────────────
    print('════════════════════════');
    print(' Part A: Day.js');
    print('════════════════════════\n');

    dynamic dayjs = await js.require('dayjs');

    // --- Parse and format ---
    print('1. Parse & Format:');
    dynamic d1 = await dayjs('2024-06-15T14:30:00');
    final formatted1 = await d1.format('YYYY-MM-DD');
    print('   dayjs("2024-06-15T14:30:00").format("YYYY-MM-DD") → $formatted1');

    final formatted2 = await d1.format('dddd, MMMM D, YYYY h:mm A');
    print('   .format("dddd, MMMM D, YYYY h:mm A") → $formatted2');

    // --- Add / Subtract ---
    print('\n2. Add & Subtract:');
    dynamic base = await dayjs('2024-01-01');

    dynamic plus7 = await base.add(7, 'day');
    print('   Jan 1 + 7 days    → ${await plus7.format("YYYY-MM-DD")}');

    dynamic plus3m = await base.add(3, 'month');
    print('   Jan 1 + 3 months  → ${await plus3m.format("YYYY-MM-DD")}');

    dynamic minus1y = await base.subtract(1, 'year');
    print('   Jan 1 - 1 year    → ${await minus1y.format("YYYY-MM-DD")}');

    // --- Diff ---
    print('\n3. Date Differences:');
    dynamic start = await dayjs('2024-01-01');
    dynamic end = await dayjs('2024-12-31');

    final diffDays = await end.diff(start, 'day');
    print('   Jan 1 → Dec 31: $diffDays days');

    final diffMonths = await end.diff(start, 'month');
    print('   Jan 1 → Dec 31: $diffMonths months');

    // --- Comparison ---
    print('\n4. Comparisons:');
    dynamic jan = await dayjs('2024-01-01');
    dynamic jul = await dayjs('2024-07-01');

    final isBefore = await jan.isBefore(jul);
    print('   Jan isBefore Jul → $isBefore');

    final isAfter = await jan.isAfter(jul);
    print('   Jan isAfter Jul  → $isAfter');

    // --- Components ---
    print('\n5. Date Components:');
    dynamic now = await dayjs('2024-06-15');
    print('   year:  ${await now.year()}');
    print('   month: ${await now.month()} (0-indexed, so 5 = June)');
    print('   date:  ${await now.date()}');
    print('   day:   ${await now.day()} (0=Sun, 6=Sat)');

    // --- Validation ---
    print('\n6. Validation:');
    dynamic valid = await dayjs('2024-01-15');
    dynamic invalid = await dayjs('not-a-date');
    print('   "2024-01-15" isValid → ${await valid.isValid()}');
    print('   "not-a-date" isValid → ${await invalid.isValid()}');

    // --- Start of ---
    print('\n7. Start Of:');
    dynamic mid = await dayjs('2024-06-15');
    dynamic startOfMonth = await mid.startOf('month');
    dynamic startOfYear = await mid.startOf('year');
    print(
        '   Jun 15 → startOf("month") → ${await startOfMonth.format("YYYY-MM-DD")}');
    print(
        '   Jun 15 → startOf("year")  → ${await startOfYear.format("YYYY-MM-DD")}');

    // ──────────────────────────────────────────────────
    //  Part B: Moment.js — Full-featured
    // ──────────────────────────────────────────────────
    print('\n════════════════════════');
    print(' Part B: Moment.js');
    print('════════════════════════\n');

    dynamic moment = await js.require('moment');

    // --- Rich formatting ---
    print('1. Rich Formatting:');
    dynamic m1 = await moment('2024-03-15');
    final mFormatted = await m1.format('MMMM Do YYYY');
    print('   moment("2024-03-15").format("MMMM Do YYYY") → $mFormatted');

    // --- Relative time ---
    print('\n2. Relative Time:');
    dynamic past = await moment('2020-01-01');
    final fromNow = await past.fromNow();
    print('   moment("2020-01-01").fromNow() → $fromNow');

    dynamic recent = await moment('2024-01-01');
    final toNow = await recent.toNow();
    print('   moment("2024-01-01").toNow()   → $toNow');

    // --- Duration ---
    print('\n3. Duration:');
    dynamic dur = await moment.duration(90, 'minutes');
    final hours = await dur.hours();
    final minutes = await dur.minutes();
    print('   duration(90, "minutes"):');
    print('     hours:   $hours');
    print('     minutes: $minutes');

    dynamic dur2 = await moment.duration(3, 'days');
    final asHours = await dur2.asHours();
    print('   duration(3, "days").asHours() → $asHours');

    // --- Calendar time ---
    print('\n4. Calendar Time:');
    dynamic calNow = await moment();
    final calendar = await calNow.calendar();
    print('   moment().calendar() → $calendar');

    // --- UTC ---
    print('\n5. UTC Mode:');
    dynamic utc = await moment.utc('2024-06-15T12:00:00Z');
    final utcFormatted = await utc.format('HH:mm [UTC]');
    print(
        '   moment.utc("2024-06-15T12:00:00Z").format("HH:mm UTC") → $utcFormatted');

    // --- Comparison ---
    print('\n6. Advanced Comparison:');
    dynamic mJan = await moment('2024-01-01');
    dynamic mDec = await moment('2024-12-31');
    dynamic mJanClone = await moment('2024-01-01');

    print('   Jan isBefore Dec → ${await mJan.isBefore(mDec)}');
    print('   Jan isAfter Dec  → ${await mJan.isAfter(mDec)}');
    print('   Jan isSame Jan (day) → ${await mJan.isSame(mJanClone, "day")}');

    // --- Diff ---
    print('\n7. Diff:');
    final mDiff = await mDec.diff(mJan, 'days');
    print('   Dec 31 - Jan 1 = $mDiff days');

    print('\n══════════════════════════════════════════════════════');
    print(' Date Utils — dayjs + moment from Dart, zero JS!');
    print('══════════════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
