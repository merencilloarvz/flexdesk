import 'package:flexdesk/features/community/data/community_api.dart';
import 'package:flexdesk/features/community/providers/community_providers.dart';
import 'package:flexdesk/features/community/widgets/comments_section.dart';
import 'package:flexdesk/features/community/data/community_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(
  String id,
  String body, {
  String name = 'Ana Cruz',
  String role = 'member',
  bool mine = false,
  bool canDelete = false,
}) => {
  'id': id,
  'body': body,
  'author_name': name,
  'author_role': role,
  'is_mine': mine,
  'can_delete': canDelete,
  'created_at': DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 5))
      .toIso8601String(),
};

/// Serves canned pages and records what the section asks of the server.
class _FakeApi implements CommunityApi {
  _FakeApi(this.pages);

  final List<List<Map<String, dynamic>>> pages;
  final requestedPages = <int>[];
  final posted = <String>[];
  final deleted = <String>[];

  @override
  Future<Map<String, dynamic>> fetchCommentsPage(
    String itemPath,
    String itemId,
    int page,
  ) async {
    requestedPages.add(page);
    return {
      'count': pages.fold<int>(0, (n, p) => n + p.length),
      'next': page < pages.length ? 'more' : null,
      'results': pages[page - 1],
    };
  }

  @override
  Future<Map<String, dynamic>> postComment(
    String itemPath,
    String itemId,
    Map<String, dynamic> body,
  ) async {
    posted.add(body['body'] as String);
    return _json(
      'new-${posted.length}',
      body['body'] as String,
      name: 'Me Myself',
      mine: true,
      canDelete: true,
    );
  }

  @override
  Future<void> deleteComment(
    String itemPath,
    String itemId,
    String commentId,
  ) async {
    deleted.add(commentId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api, {
  ValueChanged<int>? onCountChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communityRepositoryProvider.overrideWithValue(CommunityRepository(api)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommentsSection(
              itemType: CommunityItemType.event,
              itemId: 'evt-1',
              onCountChanged: onCountChanged,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists comments with role tags; delete only where allowed', (
    tester,
  ) async {
    final counts = <int>[];
    final api = _FakeApi([
      [
        _json('1', 'See you there!', name: 'Coach Rey', role: 'staff'),
        _json('2', 'Count me in', name: 'Boss Lita', role: 'owner'),
        _json('3', 'Bringing a friend', mine: true, canDelete: true),
        _json('4', 'Nice one'),
      ],
    ]);
    await _pump(tester, api, onCountChanged: counts.add);

    expect(find.text('(4)'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('See you there!'), findsOneWidget);
    expect(find.text('5m ago'), findsNWidgets(4));
    // Only the one comment the server marked can_delete has a delete icon.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('Load more comments'), findsNothing);
    expect(counts, [4]); // parent learns the real total on first load
  });

  testWidgets('loads further pages on demand and never double-lists', (
    tester,
  ) async {
    final api = _FakeApi([
      [_json('1', 'first page'), _json('2', 'still first')],
      [_json('2', 'still first'), _json('3', 'second page')],
    ]);
    await _pump(tester, api);
    expect(api.requestedPages, [1]); // not everything at once
    expect(find.text('second page'), findsNothing);

    await tester.tap(find.text('Load more comments'));
    await tester.pumpAndSettle();
    expect(api.requestedPages, [1, 2]);
    expect(find.text('second page'), findsOneWidget);
    expect(find.text('still first'), findsOneWidget); // not duplicated
    expect(find.text('Load more comments'), findsNothing);
  });

  testWidgets('posting adds the comment on top, clears the box, bumps count', (
    tester,
  ) async {
    final counts = <int>[];
    final api = _FakeApi([
      [_json('1', 'older one')],
    ]);
    await _pump(tester, api, onCountChanged: counts.add);

    await tester.enterText(find.byType(TextField), '  Good luck all!  ');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(api.posted, ['  Good luck all!  '.trim()]);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('Good luck all!'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(counts.last, 2);
    // Newest first: the new comment sits above the older one.
    expect(
      tester.getTopLeft(find.text('Good luck all!')).dy,
      lessThan(tester.getTopLeft(find.text('older one')).dy),
    );
  });

  testWidgets('send is disabled for blank input', (tester) async {
    final api = _FakeApi([<Map<String, dynamic>>[]]);
    await _pump(tester, api);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(api.posted, isEmpty);
    expect(find.text('No comments yet. Start the conversation.'), findsOneWidget);
  });

  testWidgets('delete asks first; cancel keeps it, confirm removes it', (
    tester,
  ) async {
    final counts = <int>[];
    final api = _FakeApi([
      [_json('9', 'my comment', mine: true, canDelete: true)],
    ]);
    await _pump(tester, api, onCountChanged: counts.add);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete comment?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.deleted, isEmpty);
    expect(find.text('my comment'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.deleted, ['9']);
    expect(find.text('my comment'), findsNothing);
    expect(find.text('(0)'), findsOneWidget);
    expect(counts.last, 0);
  });
}
