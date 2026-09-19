from core.models import Announcement
from core.tests.test_events import EngagementTestsMixin, EventsTestBase


class AnnouncementLikeCommentTests(EngagementTestsMixin, EventsTestBase):
    """
    Likes and comments on announcements. Every case lives in
    EngagementTestsMixin (shared with the event tests); announcement
    access-control and notification tests are in test_events.py and
    test_notifications.py.
    """
    kind = "announcements"

    def make_item(self, gym):
        return Announcement.objects.create(gym=gym, title="Closed Sunday",
                                           body="Deep cleaning day.")
