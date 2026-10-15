import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';

class FavoriteDeckFilter extends StatelessWidget {
  const FavoriteDeckFilter({
    super.key,
    required this.decks,
    required this.deckId,
    required this.onChanged,
  });
  final List<StoredDeck> decks;
  final int? deckId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final deck in decks) deck.id: deck};
    String label(StoredDeck deck) {
      final names = <String>[deck.name];
      final visited = <int>{deck.id};
      var parent = byId[deck.parentId];
      while (parent != null && visited.add(parent.id)) {
        names.insert(0, parent.name);
        parent = byId[parent.parentId];
      }
      return names.join(' / ');
    }

    final options = decks.map((d) => (id: d.id, label: label(d))).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final missing = deckId != null && !byId.containsKey(deckId);
    return DropdownButtonFormField<int>(
      // Reset the field's internal selection when the external scope changes.
      key: ValueKey('favorite-deck-selection-$deckId'),
      initialValue: deckId ?? 0,
      isExpanded: true,
      itemHeight: null,
      decoration: InputDecoration(
        labelText: '牌组范围',
        errorText: missing ? '所选牌组已删除，请重新选择范围。' : null,
        errorMaxLines: 3,
      ),
      items: [
        const DropdownMenuItem(value: 0, child: Text('全部牌组')),
        if (missing)
          DropdownMenuItem(value: deckId, child: const Text('已删除的牌组')),
        for (final option in options)
          DropdownMenuItem(
            value: option.id,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(option.label),
            ),
          ),
      ],
      onChanged: (value) => onChanged(value == 0 ? null : value),
    );
  }
}
