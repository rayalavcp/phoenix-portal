import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_container.dart';
import '../../managers/home/todo_service.dart';
import '../theme.dart';
import 'home_glass.dart';

/// The Shopping page: a Home Assistant to-do list in big touch rows. Tick
/// an item off, add one, clear the ticked ones, pick another list.
class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key, required this.container});
  final AppContainer container;

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  final _field = TextEditingController();

  TodoService get todo => widget.container.phoenixHome.todo;

  @override
  void initState() {
    super.initState();
    if (todo.lists.value.isEmpty) unawaited(todo.load());
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _field.text;
    _field.clear();
    await todo.add(text);
  }

  @override
  Widget build(BuildContext context) => PhoenixPageBackdrop(
    container: widget.container,
    child: SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([todo.items, todo.lists, todo.entity, todo.problem]),
        builder: (context, _) {
          final items = todo.items.value;
          final done = (items ?? const <TodoItem>[]).where((i) => i.done).length;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      iconSize: 30,
                      color: Colors.white,
                      tooltip: 'Back',
                      onPressed: () => widget.container.phoenixHome.shoppingOpen.value = false,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.shopping_cart_rounded, color: Phx.ember, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        todo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (todo.lists.value.length > 1)
                      PopupMenuButton<String>(
                        tooltip: 'Pick a list',
                        icon: const Icon(Icons.list_alt_rounded, color: Colors.white),
                        onSelected: (id) => unawaited(todo.pick(id)),
                        itemBuilder: (_) => [
                          for (final (id, name) in todo.lists.value)
                            CheckedPopupMenuItem(value: id, checked: id == todo.entity.value, child: Text(name)),
                        ],
                      ),
                    IconButton(
                      tooltip: 'Refresh',
                      color: Colors.white,
                      onPressed: () => unawaited(todo.refresh()),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    if (done > 0)
                      TextButton.icon(
                        onPressed: () => unawaited(todo.clearDone()),
                        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
                        label: Text('Clear $done done', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Add an item.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: glassFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: glassEdge),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _field,
                          enabled: todo.entity.value.isNotEmpty,
                          style: const TextStyle(color: Colors.white, fontSize: 20),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Add an item',
                            hintStyle: TextStyle(color: Colors.white54, fontSize: 20),
                          ),
                          onSubmitted: (_) => unawaited(_add()),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Phx.ember),
                        onPressed: todo.entity.value.isEmpty ? null : () => unawaited(_add()),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                if (todo.problem.value case final p?)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(p, style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 15)),
                  ),
                const SizedBox(height: 12),
                Expanded(child: _list(items)),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _list(List<TodoItem>? items) {
    if (!widget.container.phoenixHome.homeAssistantConfigured) {
      return _note('Connect Home Assistant to use its shopping list.');
    }
    if (todo.entity.value.isEmpty && todo.lists.value.isEmpty && items != null) {
      return _note('Home Assistant has no to-do list yet. Add the Shopping List integration in Home Assistant.');
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return _note('Nothing on the list. Add something above.');
    return Container(
      decoration: BoxDecoration(
        color: glassFill,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: glassEdge),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 64, color: glassEdge),
        itemBuilder: (context, i) {
          final item = items[i];
          return InkWell(
            onTap: () => unawaited(todo.setDone(item, !item.done)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    item.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: item.done ? Phx.gold : Colors.white70,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      item.summary,
                      style: TextStyle(
                        color: item.done ? Colors.white54 : Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        decoration: item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _note(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 20)),
    ),
  );
}
