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
      district: 'exampleisd',
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
    expect(SchoolConfig.fromJson('junk').district, '');
  });

  group('SchoolCafe set-up', () {
    test('a fresh install has no school: the School page asks to set one up', () {
      const c = SchoolConfig();
      expect(c.provider, 'schoolcafe');
      expect(c.district, isEmpty);
      expect(c.schoolSlug, isEmpty);
      expect(c.schoolName, isEmpty);
      expect(c.calendarUrl, isEmpty);
      expect(c.servingLine, 'auto');
      expect(c.hasMenu, isFalse);
    });

    test('an earlier setup with blanks stays blank; an old Main Line looks itself up', () {
      final c = SchoolConfig.fromJson({'provider': 'schoolcafe', 'district': 'exampleisd', 'school': '', 'calendar': '', 'servingLine': 'Main Line', 'menus': []});
      expect(c.schoolSlug, isEmpty);
      expect(c.calendarUrl, isEmpty);
      expect(c.servingLine, 'auto');
      expect(c.menuTypes, hasLength(2));
    });

    test('a parent-chosen school and calendar are kept', () {
      final c = SchoolConfig.fromJson({'school': 'abc', 'calendar': 'calendar.school', 'servingLine': 'Grab and Go'});
      expect(c.schoolSlug, 'abc');
      expect(c.calendarUrl, 'calendar.school');
      expect(c.servingLine, 'Grab and Go');
    });

    test('serving line from GetServiceLine', () {
      expect(
        parseSchoolCafeServingLine([
          {'SchoolId': '00000000-0000-0000-0000-000000000000', 'ServingLineDescription': 'Main (Trayline)'},
        ]),
        'Main (Trayline)',
      );
      expect(parseSchoolCafeServingLine([]), isNull);
      expect(parseSchoolCafeServingLine({'Message': 'nope'}), isNull);
    });

    test("a SchoolCafe lunch, without the condiments", () {
      final day = parseSchoolCafeDay({
        'ENTREES': [
          {'MenuItemDescription': 'Cheese Tortellini with Marinara '},
          {'MenuItemDescription': 'Chicken Tenders'},
        ],
        'GRAINS': [
          {'MenuItemDescription': 'Whole Grain Cheesy Garlic Breadstick'},
        ],
        'CONDIMENTS': [
          {'MenuItemDescription': 'Ketchup'},
        ],
      }, DateTime(2026, 12, 1));
      expect(day.sections.map((s) => s.$1), ['Entrees', 'Grains']);
      expect(day.items.first, 'Cheese Tortellini with Marinara');
      expect(day.items, isNot(contains('Ketchup')));
    });
  });

  test("SchoolCafe's district and school lists", () {
    expect(parseSchoolCafeIsdId([
      {'ISDId': 1234, 'Status': true, 'StateCd': 'TX', 'ISDName': 'EXAMPLE ISD'},
    ]), '1234');
    expect(parseSchoolCafeIsdId([]), isNull);
    final schools = parseSchoolCafeSchools([
      {'SchoolId': '11111111-1111-1111-1111-111111111111', 'SchoolTypeId': 1420, 'SiteTypeDescription': 'Elementary School', 'SchoolName': 'Birch ES'},
      {'SchoolId': '22222222-2222-2222-2222-222222222222', 'SchoolTypeId': 1420, 'SiteTypeDescription': 'Elementary School', 'SchoolName': 'Oakwood ES'},
    ]);
    expect(schools.map((s) => s.name), ['Birch ES', 'Oakwood ES']);
    expect(bestSchoolMatch(schools, 'Oakwood Elementary')?.slug, '22222222-2222-2222-2222-222222222222');
  });
}
