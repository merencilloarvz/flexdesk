import 'package:flexdesk/core/api/api_exception.dart';
import 'package:flexdesk/features/community/data/community_api.dart';
import 'package:flexdesk/features/community/data/community_repository.dart';
import 'package:flexdesk/features/community/providers/community_providers.dart';
import 'package:flexdesk/features/community/screens/member/announcement_detail_screen.dart';
import 'package:flexdesk/features/community/screens/member/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _announcement(
  String id,
  String title,
  String body, {
  int likes = 0,
  bool liked = false,
  int comments = 0,
  bool pinned = false,
}) => {
  'id': id,
  'title': title,
  'body': body,
  'is_pinned': pinned,
  'like_count': likes,
  'liked_by_me': liked,
  'comment_count': comments,
  'created_at': '2026-09-10T02:00:00Z',
};

final _longBody = List.filled(60, 'The gym will close early for maintenance.')
    .join(' ');

class _FakeApi implements CommunityApi {
  _FakeApi(this.announcements);

  final List<Map<String, dynamic>> announcements;
  ApiException? detailFailure;
  int listFetches = 0;
  final detailFetches = <String>[];
  final likeToggles = <String>[];

  @override
  Future<List<Map<String, dynamic>>> fetchAnnouncements() async {
    listFetches++;
    return announcements;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEvents() async => [];

  @override
  Future<Map<String, dynamic>> fetchAnnouncement(String id) async {
    detailFetches.add(id);
    if (detailFailure != null) throw detailFailure!;
    return announcements.firstWhere((a) => a['id'] == id);
  }

  @override
  Future<Map<String, dynamic>> fetchCommentsPage(
    String itemPath,
    String itemId,
    int page,
  ) async => {'count': 0, 'next': null, 'results': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> toggleLike(
    String itemPath,
    String itemId,
  ) async {
    likeToggles.add('$itemPath/$itemId');
    return {'like_count': 1, 'liked_by_me': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpFeed(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communityRepositoryProvider.overrideWithValue(CommunityRepository(api)),
      ],
      child: const MaterialApp(home: CommunityScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping an announcement card opens its detail screen', (
    tester,
  ) async {
    final api = _FakeApi([
      _announcement('a1', 'Holiday hours', 'Closed on Sunday.', comments: 2),
    ]);
    await _pumpFeed(tester, api);
    expect(find.byType(AnnouncementDetailScreen), findsNothing);

    await tester.tap(find.text('Holiday hours'));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementDetailScreen), findsOneWidget);
    expect(api.detailFetches, ['a1']); // the id was passed through
    expect(find.text('Announcement'), findsOneWidget); // app bar title
    expect(find.text('Closed on Sunday.'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget); // the inline section

    // Back returns to the feed, which refreshes so counts are current.
    final before = api.listFetches;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementDetailScreen), findsNothing);
    expect(find.text('Holiday hours'), findsOneWidget);
    expect(api.listFetches, before + 1);
  });

  testWidgets('the comment chip goes to the same detail screen', (
    tester,
  ) async {
    final api = _FakeApi([_announcement('a1', 'Holiday hours', 'Closed.')]);
    await _pumpFeed(tester, api);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementDetailScreen), findsOneWidget);
    // No bottom sheet any more — it's a real route.
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('liking a card toggles the like without opening the post', (
    tester,
  ) async {
    final api = _FakeApi([
      _announcement('a1', 'Holiday hours', 'Closed.', likes: 0),
    ]);
    await _pumpFeed(tester, api);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(api.likeToggles, ['announcements/a1']);
    expect(find.byType(AnnouncementDetailScreen), findsNothing);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('long bodies are clipped with Read more; short ones are not', (
    tester,
  ) async {
    final api = _FakeApi([
      _announcement('long', 'Long one', _longBody),
      _announcement('short', 'Short one', 'Back at 9am.'),
    ]);
    await _pumpFeed(tester, api);

    // The full wall of text is not shown inline...
    expect(find.text(_longBody), findsOneWidget); // present but clamped
    final clamped = tester.widget<Text>(find.text(_longBody));
    expect(clamped.maxLines, 3);
    // ...and exactly one card (the long one) advertises the rest.
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('pinned announcements are marked', (tester) async {
    final api = _FakeApi([
      _announcement('p', 'Important', 'Read this.', pinned: true),
      _announcement('n', 'Ordinary', 'Whatever.'),
    ]);
    await _pumpFeed(tester, api);
    expect(find.text('Pinned'), findsOneWidget);
  });

  testWidgets('search shows a count, and a friendly empty state', (
    tester,
  ) async {
    final api = _FakeApi([
      _announcement('a1', 'Holiday hours', 'Closed on Sunday.'),
      _announcement('a2', 'New towels', 'Fresh stock arrived.'),
    ]);
    await _pumpFeed(tester, api);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'towels');
    await tester.pumpAndSettle();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Holiday hours'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('0 results'), findsOneWidget);
    expect(find.text('No matches found'), findsOneWidget);

    // The clear button empties the search and brings the feed back.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Holiday hours'), findsOneWidget);
    expect(find.text('New towels'), findsOneWidget);
  });

  testWidgets('an empty feed explains itself', (tester) async {
    await _pumpFeed(tester, _FakeApi([]));
    expect(find.text('No updates yet'), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
  });

  testWidgets('detail screen shows the full text and the like state', (
    tester,
  ) async {
    final api = _FakeApi([
      _announcement('a1', 'Holiday hours', _longBody, likes: 3, liked: true),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityRepositoryProvider.overrideWithValue(
            CommunityRepository(api),
          ),
        ],
        child: const MaterialApp(
          home: AnnouncementDetailScreen(announcementId: 'a1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Full body, unclamped.
    final body = tester.widget<Text>(find.text(_longBody));
    expect(body.maxLines, isNull);
    expect(find.byIcon(Icons.favorite), findsOneWidget); // liked by me
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a removed announcement shows a message and can retry', (
    tester,
  ) async {
    final api = _FakeApi([_announcement('a1', 'Gone', 'Body.')])
      ..detailFailure = ApiException(
        kind: ApiExceptionKind.notFound,
        message: 'Not found.',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityRepositoryProvider.overrideWithValue(
            CommunityRepository(api),
          ),
        ],
        child: const MaterialApp(
          home: AnnouncementDetailScreen(announcementId: 'a1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This announcement is no longer available.'), findsOneWidget);

    api.detailFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Body.'), findsOneWidget);
  });
}
