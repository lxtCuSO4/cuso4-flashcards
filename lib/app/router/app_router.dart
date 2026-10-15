import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_page.dart';
import '../../features/decks/presentation/deck_list_page.dart';
import '../../features/decks/presentation/card_list_page.dart';
import '../../features/decks/presentation/note_editor_page.dart';
import '../../features/records/presentation/records_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/study_settings_page.dart';
import '../../features/import/presentation/import_page.dart';
import '../../features/study/presentation/study_page.dart';
import '../../features/favorites/presentation/favorites_page.dart';
import '../../features/favorites/presentation/favorite_preview_page.dart';
import '../../features/backup/presentation/backup_page.dart';
import '../../features/practice/presentation/practice_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/practice/:deckId',
        builder: (_, state) =>
            PracticePage(deckId: int.parse(state.pathParameters['deckId']!)),
      ),
      GoRoute(
        path: '/study-settings',
        builder: (_, _) => const StudySettingsPage(),
      ),
      GoRoute(path: '/backup', builder: (_, _) => const BackupPage()),
      GoRoute(path: '/import', builder: (_, _) => const ImportPage()),
      GoRoute(
        path: '/favorites',
        builder: (_, _) => const FavoritesPage(),
        routes: [
          GoRoute(
            path: ':cardId',
            builder: (_, state) => FavoritePreviewPage(
              cardId: int.parse(state.pathParameters['cardId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/study',
        builder: (_, state) => StudyPage(
          deckId: int.tryParse(state.uri.queryParameters['deckId'] ?? ''),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppNavigation(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomePage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/decks',
                builder: (_, _) => const DeckListPage(),
                routes: [
                  GoRoute(
                    path: ':deckId',
                    builder: (_, state) => CardListPage(
                      deckId: int.parse(state.pathParameters['deckId']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (_, state) => NoteEditorPage(
                          deckId: int.parse(state.pathParameters['deckId']!),
                        ),
                      ),
                      GoRoute(
                        path: 'edit/:noteId',
                        builder: (_, state) => NoteEditorPage(
                          deckId: int.parse(state.pathParameters['deckId']!),
                          noteId: int.parse(state.pathParameters['noteId']!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/records', builder: (_, _) => const RecordsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class AppNavigation extends StatelessWidget {
  const AppNavigation({super.key, required this.shell});
  final StatefulNavigationShell shell;
  static const _labels = ['今日', '牌组', '记录', '我的'];
  static const _icons = [
    Icons.today_outlined,
    Icons.layers_outlined,
    Icons.insights_outlined,
    Icons.person_outline,
  ];
  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 840) {
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    4,
                    (i) => NavigationRailDestination(
                      icon: Icon(_icons[i]),
                      label: Text(_labels[i]),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: shell),
              ],
            ),
          ),
        );
      }
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _select,
          destinations: List.generate(
            4,
            (i) =>
                NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
          ),
        ),
      );
    },
  );
}
