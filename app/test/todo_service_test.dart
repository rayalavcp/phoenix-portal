import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/core/command_registry.dart';
import 'package:kiosk_satellite/core/logging.dart';
import 'package:kiosk_satellite/managers/home/todo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('todo.get_items answers become items, open ones first', () {
    final items = parseTodoItems({
      'response': {
        'todo.shopping_list': {
          'items': [
            {'summary': 'Milk', 'uid': 'a', 'status': 'completed'},
            {'summary': 'Eggs', 'uid': 'b', 'status': 'needs_action'},
            {'summary': '', 'uid': 'c', 'status': 'needs_action'},
          ],
        },
      },
    }, 'todo.shopping_list');
    expect([for (final i in items) i.summary], ['Eggs', 'Milk']);
    expect(items.last.done, isTrue);
  });

  test('the shopping list is read, added to and ticked off through Home Assistant', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <Map<String, Object?>>[];
    final list = <Map<String, Object?>>[
      {'summary': 'Bread', 'uid': '1', 'status': 'needs_action'},
    ];
    final log = Logger();
    final commands = CommandRegistry(log)
      ..register(
        Command(
          name: 'haListEntities',
          description: '',
          handler: (_) async => const CommandResult.ok([
            {'entity_id': 'todo.chores', 'name': 'Chores'},
            {'entity_id': 'todo.shopping_list', 'name': 'Shopping List'},
          ]),
        ),
      )
      ..register(
        Command(
          name: 'haCallService',
          description: '',
          handler: (p) async {
            calls.add(Map.of(p));
            final data = (p['data'] as Map?) ?? const {};
            switch (p['service']) {
              case 'add_item':
                list.add({'summary': data['item'], 'uid': '${list.length + 1}', 'status': 'needs_action'});
              case 'update_item':
                for (final i in list) {
                  if (i['uid'] == data['item']) i['status'] = data['status'];
                }
              case 'get_items':
                return CommandResult.ok({
                  'response': {
                    p['entity_id']: {'items': list},
                  },
                });
            }
            return const CommandResult.ok();
          },
        ),
      );
    final todo = TodoService(commands, configured: () => true);
    await todo.load();
    expect(todo.entity.value, 'todo.shopping_list');
    expect(todo.name, 'Shopping List');
    expect(todo.open, 1);
    await todo.add('Apples');
    expect([for (final i in todo.items.value!) i.summary], ['Bread', 'Apples']);
    await todo.setDone(todo.items.value!.first, true);
    expect(todo.open, 1);
    expect(todo.items.value!.last.summary, 'Bread');
    expect(calls.where((c) => c['service'] == 'update_item').single['data'], {'item': '1', 'status': 'completed'});
    todo.dispose();
  });
}
