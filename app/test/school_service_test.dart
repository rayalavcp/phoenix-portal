import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/home/school_service.dart';

// The School page reads the district's Nutrislice menus and an iCal feed.
// These pin the parsing to the shapes those services publish.
void main() {
  test('Nutrislice school list with menus, sorted by name', () {
    final schools = parseNutrisliceSchools([
      {
        'name': 'Zeta Elementary',
        'slug': 'zeta-elementary',
        'active_menu_types': [
          {'name': 'Breakfast', 'slug': 'breakfast'},
          {'name': 'Lunch', 'slug': 'lunch'},
        ],
      },
      {'name': 'Alpha Middle', 'slug': 'alpha-middle', 'active_menu_types': []},
      {'name': 'No slug'},
      'junk',
    ]);
    expect(schools.map((s) => s.slug), ['alpha-middle', 'zeta-elementary']);
    expect(schools[1].menuTypes, [('breakfast', 'Breakfast'), ('lunch', 'Lunch')]);
  });

  test('Nutrislice week groups items under section titles', () {
    final days = parseNutrisliceWeek({
      'start_date': '2026-11-23',
      'days': [
        {
          'date': '2026-11-23',
          'menu_items': [
            {'is_section_title': true, 'text': 'Entrees'},
            {'is_section_title': false, 'food': {'name': 'Chicken Nuggets'}},
            {'is_section_title': false, 'food': {'name': 'Cheese Pizza'}},
            {'is_section_title': true, 'text': 'Sides'},
            {'is_section_title': false, 'food': {'name': 'Green Beans'}},
            {'is_section_title': false, 'text': 'Milk choice'},
            {'is_section_title': false, 'food': null, 'text': ''},
          ],
        },
        {'date': '2026-11-24', 'menu_items': []},
        {'date': 'not a date'},
      ],
    });
    expect(days, hasLength(2));
    expect(days[0].sections.map((s) => s.$1), ['Entrees', 'Sides']);
    expect(days[0].sections[0].$2, ['Chicken Nuggets', 'Cheese Pizza']);
    expect(days[0].sections[1].$2, ['Green Beans', 'Milk choice']);
    expect(days[0].items.first, 'Chicken Nuggets');
    expect(days[1].isEmpty, isTrue);
    expect(parseNutrisliceWeek('junk'), isEmpty);
  });

  test('iCal all-day, multi-day and timed events with folded lines', () {
    const ics = 'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20261123\r\n'
        'DTEND;VALUE=DATE:20261128\r\n'
        'SUMMARY:Thanksgiving Break - No\r\n'
        '  School\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\n'
        'DTSTART:20261204T190000Z\r\n'
        'DTEND:20261204T200000Z\r\n'
        'SUMMARY:Winter Concert\\, Gym\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20261211\r\n'
        'SUMMARY:Early Release\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
    final events = parseIcs(ics);
    expect(events, hasLength(3));
    expect(events[0].title, 'Thanksgiving Break - No School');
    expect(events[0].allDay, isTrue);
    expect(events[0].noSchool, isTrue);
    expect(events[0].covers(DateTime(2026, 11, 27)), isTrue);
    expect(events[0].covers(DateTime(2026, 11, 28)), isFalse);
    expect(events[1].title, 'Winter Concert, Gym');
    expect(events[1].allDay, isFalse);
    expect(events[2].earlyRelease, isTrue);
    expect(events[2].end, DateTime(2026, 12, 12));
  });

  test('the config survives a round trip', () {
    const cfg = SchoolConfig(
      district: 'friscoisd',
      schoolSlug: 'x-elementary',
      schoolName: 'X Elementary',
      menuTypes: [('lunch', 'Lunch')],
      calendarUrl: 'webcal://example.com/cal.ics',
      startTime: '7:50',
      endTime: '15:05',
    );
    final back = SchoolConfig.fromJson(cfg.toJson());
    expect(back.schoolSlug, 'x-elementary');
    expect(back.menuTypes, [('lunch', 'Lunch')]);
    expect(back.hasMenu, isTrue);
    expect(SchoolConfig.fromJson('junk').district, 'friscoisd');
  });
}
