import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/command_registry.dart';

/// One item on a Home Assistant to-do list.
@immutable
class TodoItem {
  const TodoItem({required this.uid, required this.summary, required this.done});
  final String uid;
  final String summary;
  final bool done;

  TodoItem copyWith({bool? done}) => TodoItem(uid: uid, summary: summary, done: done ?? this.done);
}

/// A Home Assistant to-do list (the Shopping list by default) for the
/// Shopping tile and page: read, add, tick off, clear the ticked ones.
/// Everything goes through Home Assistant's todo services, so the list is
/// the same one the Home Assistant app and voice assistants use.
class TodoService {
  TodoService(this._commands, {required this.configured});

  final CommandRegistry _commands;

  /// Whether Home Assistant is set up (no list without it).
  final bool Function() configured;

  static const _entityKey = 'phx.home.todo_entity';

  /// The to-do lists Home Assistant has: (entity id, name).
  final lists = ValueNotifier<List<(String, String)>>(const []);

  /// The list shown, e.g. todo.shopping_list (empty: none picked or found).
  final entity = ValueNotifier<String>('');

  /// Its items, open ones first; null before the first read.
  final items = ValueNotifier<List<TodoItem>?>(null);

  /// The last failure, for the page (null: fine).
  final problem = ValueNotifier<String?>(null);

  /// The shown list's name.
  String get name {
    for (final (id, n) in lists.value) {
      if (id == entity.value) return n;
    }
    return 'Shopping list';
  }

  /// How many items are still to get.
  int get open => (items.value ?? const []).where((i) => !i.done).length;

  Future<void> load() async {
    if (!configured()) return;
    final prefs = await SharedPreferences.getInstance();
    final found = await _commands.execute('haListEntities', {
      'domains': ['todo'],
    });
    if (found.ok && found.data is List) {
      lists.value = [
        for (final e in found.data as List)
          if (e is Map && '${e['entity_id'] ?? ''}'.startsWith('todo.')) ('${e['entity_id']}', '${e['name'] ?? e['entity_id']}'),
      ];
    }
    final saved = prefs.getString(_entityKey) ?? '';
    final ids = [for (final (id, _) in lists.value) id];
    entity.value = ids.contains(saved)
        ? saved
        : ids.contains('todo.shopping_list')
        ? 'todo.shopping_list'
        : (ids.firstOrNull ?? '');
    await refresh();
  }

  Future<void> pick(String id) async {
    entity.value = id;
    await (await SharedPreferences.getInstance()).setString(_entityKey, id);
    await refresh();
  }

  /// Reads the shown list's items from Home Assistant.
  Future<void> refresh() async {
    final id = entity.value;
    if (id.isEmpty) {
      items.value = const [];
      return;
    }
    final r = await _commands.execute('haCallService', {
      'domain': 'todo',
      'service': 'get_items',
      'entity_id': id,
      'data': {
        'status': ['needs_action', 'completed'],
      },
      'response': true,
    });
    if (!r.ok) {
      problem.value = 'Home Assistant is not reachable right now.';
      return;
    }
    problem.value = null;
    items.value = parseTodoItems(r.data, id);
  }

  Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty || entity.value.isEmpty) return;
    await _call('add_item', {'item': t});
  }

  Future<void> setDone(TodoItem item, bool done) async {
    // Show the tick at once; Home Assistant's answer confirms it.
    items.value = [for (final i in items.value ?? const <TodoItem>[]) i.uid == item.uid ? i.copyWith(done: done) : i];
    await _call('update_item', {'item': item.uid, 'status': done ? 'completed' : 'needs_action'});
  }

  Future<void> clearDone() => _call('remove_completed_items', const {});

  Future<void> _call(String service, Map<String, Object?> data) async {
    final r = await _commands.execute('haCallService', {
      'domain': 'todo',
      'service': service,
      'entity_id': entity.value,
      'data': data,
    });
    if (!r.ok) problem.value = r.error ?? 'Home Assistant refused that.';
    await refresh();
  }

  void dispose() {
    lists.dispose();
    entity.dispose();
    items.dispose();
    problem.dispose();
  }
}

/// The items of [entity] in todo.get_items' response: open ones first, in
/// Home Assistant's order.
List<TodoItem> parseTodoItems(Object? response, String entity) {
  final root = response is Map && response['response'] is Map ? response['response'] as Map : response;
  final list = root is Map && root[entity] is Map ? (root[entity] as Map)['items'] : null;
  if (list is! List) return const [];
  final all = [
    for (final i in list)
      if (i is Map && '${i['summary'] ?? ''}'.isNotEmpty)
        TodoItem(uid: '${i['uid'] ?? i['summary']}', summary: '${i['summary']}', done: i['status'] == 'completed'),
  ];
  return [...all.where((i) => !i.done), ...all.where((i) => i.done)];
}
