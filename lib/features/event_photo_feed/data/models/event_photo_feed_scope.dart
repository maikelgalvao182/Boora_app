sealed class EventPhotoFeedScope {
  const EventPhotoFeedScope();
}

class EventPhotoFeedScopeCity extends EventPhotoFeedScope {
  const EventPhotoFeedScopeCity({required this.cityId});
  final String? cityId;
}

class EventPhotoFeedScopeGlobal extends EventPhotoFeedScope {
  const EventPhotoFeedScopeGlobal();
}

class EventPhotoFeedScopeEvent extends EventPhotoFeedScope {
  const EventPhotoFeedScopeEvent({required this.eventId});
  final String eventId;
}

class EventPhotoFeedScopeUser extends EventPhotoFeedScope {
  const EventPhotoFeedScopeUser({required this.userId});
  final String userId;
}

class EventPhotoFeedScopeFollowing extends EventPhotoFeedScope {
  const EventPhotoFeedScopeFollowing({required this.userId});
  final String userId;
}
