# 🔥 Comprehensive Firestore Audit Report — Partiu Flutter App

**Date:** Feb 15, 2026  
**Scope:** `/lib/` directory — all direct Firestore reads, writes, streams, and Cloud Function calls  
**Total `FirebaseFirestore.instance` references:** 168  
**Total `.snapshots()` streams:** 50  
**Total `FirebaseFunctions.instance` references:** 10  
**Total `.httpsCallable()` invocations:** 14  
**Total `StreamSubscription` declarations related to Firestore:** 48

---

## 📐 Architecture Overview

The app uses a **hybrid architecture** — partially Clean Architecture (with `data/domain/presentation` layers in newer features) and partially MVVM/Service-based (in older features).

### Folder Structure Summary:

```
lib/
├── app/                        # App-level setup
├── common/                     # Shared mixins, services, state, utils
├── constants/                  # Global constants
├── core/                       # Core infrastructure
│   ├── config/
│   ├── constants/
│   ├── controllers/            # Locale controller
│   ├── helpers/
│   ├── managers/
│   ├── models/
│   ├── repositories/           # ChatRepository
│   ├── router/
│   ├── services/               # Auth, Block, Location, Cache, Verification...
│   ├── utils/
│   └── validators/
├── features/                   # Feature modules (partial Clean Architecture)
│   ├── auth/                   # presentation only (controllers, screens, widgets)
│   ├── conversations/          # models, services, state, widgets
│   ├── event_photo_feed/       # data/domain/presentation (cleanest)
│   ├── events/                 # presentation only (group_info, etc.)
│   ├── feed/                   # data/domain/presentation
│   ├── home/                   # data + presentation (viewmodels, services, widgets)
│   ├── location/               # data/domain/presentation
│   ├── notifications/          # controllers, helpers, repositories, services, triggers
│   ├── profile/                # data (datasources, repos, services) + presentation
│   ├── reviews/                # data/domain/presentation
│   ├── subscription/           # services, providers
│   └── web_dashboard/          # admin screens
├── screens/                    # Legacy screens (chat)
│   └── chat/                   # controllers, services, widgets, viewmodels
├── services/                   # Legacy services
│   ├── events/
│   └── location/
├── shared/                     # Shared across features
│   ├── models/
│   ├── repositories/           # AuthRepository, UserRepository, DeviceRepository
│   ├── services/               # UserDataService, SocialAuth
│   ├── stores/                 # AvatarStore, UserStore
│   ├── utils/
│   └── widgets/                # ReportEventButton
└── widgets/                    # Generic shared widgets
```

---

## 🗄️ Firestore Collections Accessed from Flutter Client

| Collection | Type | Accessed From |
|---|---|---|
| `Users` | Top-level | 30+ files |
| `Users/{id}/private` | Subcollection | location_query_service, geo_service |
| `Users/{id}/following` | Subcollection | event_photo_feed_controller, feed_preloader, event_photo_repository |
| `Users/{id}/followers` | Subcollection | Cloud Functions only (follow system) |
| `users_preview` | Top-level | user_store, user_repository, avatar_service, pending_applications_repository, event_card_controller, user_status_service, event_card_action_warmup_service |
| `events` | Top-level | event_repository, event_map_repository, activity_repository, event_card_controller, list_drawer_controller, chat_app_bar_controller, group_info_controller, review_repository, actions_repository, report_service, notification_targeting_service, web_dashboard, feed_reminder_service |
| `events_card_preview` | Top-level | event_repository, feed_reminder_service |
| `event_tombstones` | Top-level | event_tombstone_service (via map_discovery_service) |
| `EventApplications` | Top-level | event_application_repository, event_card_controller, pending_applications_repository, chat_screen_refactored, notification triggers |
| `EventChats` | Top-level | chat_repository |
| `EventChats/{id}/Messages` | Subcollection | chat_repository |
| `EventPhotos` | Top-level | event_photo_repository, event_photo_composer_controller, event_photo_like_service, event_photo_likes_cache_service, feed_reminder_service |
| `EventPhotos/{id}/likes` | Subcollection | event_photo_like_service, event_photo_likes_cache_service |
| `Connections/{uid}/Conversations` | Subcollection | conversations_viewmodel, conversation_stream_widget, conversation_navigation_service, chat_service, notifications_counter_service, report_event_button, app_notifications, fee_auto_heal_service, event_card_controller, group_info_controller, event_application_removal_service |
| `Notifications` | Top-level | notifications_repository, notifications_counter_service |
| `Reviews` | Top-level | review_repository, review_dialog_controller, review_batch_service |
| `PendingReviews` | Top-level | review_repository, pending_reviews_listener_service, review_dialog_controller, review_batch_service |
| `ProfileVisits` | Top-level | visits_service, profile_visits_service |
| `ProfileViews` | Top-level | profile_visits_service |
| `DeviceTokens` | Top-level | fcm_token_service |
| `ActivityFeed` | Top-level | activity_feed_repository |
| `blockedUsers` | Top-level | block_service |
| `reports` | Top-level | report_service, report_event_button |
| `AppInfo` | Top-level | didit_verification_service, google_maps_config_service |
| `DiditSessions` | Top-level | didit_verification_service |
| `FaceVerifications` | Top-level | face_verification_service, didit_verification_service |
| `ReferralInstalls` | Top-level | referral_debug_screen, invite_drawer |
| `feeds` | Top-level | event_photo_repository |
| `feeds/{uid}/items` | Subcollection | event_photo_repository |

---

## 📁 DETAILED AUDIT BY MODULE

---

### 1. 🏠 HOME / MAP / EVENTS

#### `features/home/data/repositories/event_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | `_eventsCollection` — fetches event docs |
| `events_card_preview` | read/stream | `_previewsCollection` — card preview collection |
| `events` | stream | `.snapshots()` — real-time event updates |

#### `features/home/data/repositories/event_map_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Fetches events by geohash for map rendering |
| `Users` | read | Gets creator data for map markers |

#### `features/home/data/repositories/event_application_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `EventApplications` | read/write/stream | Apply to events, check status, accept/reject, list participants |
| `users_preview` | read | Get applicant preview data |
| `events` | read/write | Update participant counts, get event data |
| — | callable | `removeUserApplication` Cloud Function |

#### `features/home/data/repositories/pending_applications_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `events` | stream | Listen for user's events with pending applications |
| `EventApplications` | stream | Listen for pending applications per event |
| `users_preview` | read | Load applicant preview data |

#### `features/home/create_flow/activity_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `events` | write | Create new event, update event details (title, description, datetime, location) |

#### `features/home/data/services/event_tombstone_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `event_tombstones` | read | Polls for recently deleted events for map cleanup |

#### `features/home/data/services/map_discovery_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| (uses event_tombstone_service) | read | Coordinates map discovery with tombstone polling |

#### `features/home/data/services/avatar_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `users_preview` | read | Fetch avatar URLs for event card display |

#### `features/home/data/services/people_ranking_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read | People ranking queries |

#### `features/home/data/services/locations_ranking_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read | Location ranking queries |

#### `features/home/presentation/services/geo_service.dart`
**Layer:** Presentation/Service  
| Collection | Operation | Context |
|---|---|---|
| `Users/{id}/private` | read | Get private location data |
| `Users` | read | Get user document for geo info |
| `Users` | read | Batch fetch users by geohash |

#### `features/home/presentation/services/onboarding_service.dart`
**Layer:** Presentation/Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Check/update onboarding state fields |

#### `features/home/presentation/services/event_card_action_warmup_service.dart`
**Layer:** Presentation/Service  
| Collection | Operation | Context |
|---|---|---|
| `users_preview` | read | Preload user preview docs for event cards |

#### `features/home/presentation/widgets/event_card/event_card_controller.dart`
**Layer:** Widget/Controller ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `EventApplications` | stream | Listen to application status changes |
| `EventApplications` | stream | Listen for participant list updates |
| `events` | stream | Listen to event document changes |
| `users` | read | Fetch full user data |
| `users_preview` | read | Fetch user preview data |
| `Connections/{uid}/Conversations` | write | Create conversation on match |

#### `features/home/presentation/widgets/list_drawer/list_drawer_controller.dart`
**Layer:** Widget/Controller  
| Collection | Operation | Context |
|---|---|---|
| `events` | stream | Listen for user's own events list |

#### `features/home/presentation/widgets/invite_drawer.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Load user referral code data |
| `ReferralInstalls` | read | Count referral installs |
| `Users` | read | Load invited user names |

#### `features/home/presentation/widgets/referral_debug_screen.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Debug: fetch user referral data |
| `ReferralInstalls` | read | Debug: list referral installs |

#### `features/home/presentation/screens/find_people/find_people_controller.dart`
**Layer:** Controller  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Fetch user docs for the "Find People" feature |

#### `features/home/presentation/viewmodels/map_viewmodel.dart`
**Layer:** ViewModel  
| Collection | Operation | Context |
|---|---|---|
| (indirect via services) | subscription management | Manages StreamSubscriptions for radius, reload, remote deletion, position |

---

### 2. 💬 CHAT / CONVERSATIONS

#### `core/repositories/chat_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `EventChats/{id}/Messages` | stream | Real-time message stream (2 streams: initial + paginated) |
| `EventChats/{id}/Messages` | write | Send messages |
| `Users` | stream | Listen to user doc for chat (typing indicators, etc.) |

#### `screens/chat/services/chat_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | stream | Stream conversation doc for a specific event (3 different stream methods) |
| `Connections/{uid}/Conversations` | read | Get conversation document |

#### `screens/chat/services/chat_message_deletion_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| — | callable | `deleteChatMessage` Cloud Function |

#### `screens/chat/services/event_deletion_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| — | callable | `deleteEvent` Cloud Function |

#### `screens/chat/services/event_application_removal_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `EventChats` | read | Check event chat existence |
| `Connections/{uid}/Conversations` | read/write | Remove conversation entries |
| — | callable | `deleteEvent`, `removeUserApplication`, `removeParticipant` Cloud Functions |

#### `screens/chat/services/application_removal_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read/write | Application removal operations |

#### `screens/chat/services/fee_auto_heal_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | read | Auto-heal fee status in conversations |

#### `screens/chat/chat_screen_refactored.dart`
**Layer:** Screen/Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `EventApplications` | read | Directly queries applications in the chat screen |

#### `screens/chat/widgets/presence_drawer.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `EventApplications` | read | Get event participants for presence confirmation |

#### `screens/chat/widgets/chat_app_bar_widget.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Fetch event data for chat app bar |

#### `screens/chat/widgets/confirm_presence_widget.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `events/{id}/ConfirmedParticipants` | read/write | Check and confirm user presence |

#### `screens/chat/widgets/user_presence_status_widget.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `events/{id}/ConfirmedParticipants` | stream | Real-time listener for presence status IN A WIDGET |

#### `screens/chat/controllers/chat_app_bar_controller.dart`
**Layer:** Controller  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Fetch event data for app bar display |

#### `features/conversations/state/conversations_viewmodel.dart`
**Layer:** ViewModel  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | stream | Real-time conversation list stream |
| `Connections/{uid}/Conversations` | read | Fetch specific conversation and full list |

#### `features/conversations/widgets/conversation_stream_widget.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | read | Fetch conversation data in widget |

#### `features/conversations/services/conversation_navigation_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | read | Navigate to conversation |

---

### 3. 👤 PROFILE

#### `features/profile/data/repositories/profile_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Full user profile CRUD |

#### `features/profile/data/datasources/follow_remote_datasource.dart`
**Layer:** Datasource  
| Collection | Operation | Context |
|---|---|---|
| `Users/{uid}/followers` | stream | Listen to follower status changes |
| — | callable | `followUser`, `unfollowUser` Cloud Functions |

#### `features/profile/data/services/profile_visits_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `ProfileVisits` | read/write/stream | Record visits, listen for visitor updates, query visit history |
| `ProfileViews` | write | Record profile views |

#### `features/profile/data/services/visits_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `ProfileVisits` | read/stream | Recent visitors query with real-time updates |
| — | callable (via _functions) | Visit-related Cloud Function calls |

#### `features/profile/data/services/profile_completeness_prompt_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | stream | Observe user doc for profile completeness checks |

#### `features/profile/presentation/controllers/profile_controller.dart`
**Layer:** Controller  
| Collection | Operation | Context |
|---|---|---|
| `Users` | stream | Listen to profile doc changes |
| `Reviews` | stream | Listen to user's reviews |

#### `features/profile/presentation/controllers/followers_controller.dart`
**Layer:** Controller  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read | Followers/following queries |

#### `features/profile/presentation/viewmodels/image_upload_view_model.dart`
**Layer:** ViewModel  
| Collection | Operation | Context |
|---|---|---|
| `Users` | write | Update user profile images |
| (uses FirebaseStorage) | write | Upload/delete images |

#### `features/profile/presentation/viewmodels/edit_profile_view_model.dart`
**Layer:** ViewModel  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Edit user profile fields |

#### `features/profile/presentation/widgets/app_section_card.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | write | Update user preferences (distance unit, distance filters, age filters) - 6 direct Firestore writes |
| — | callable | `deleteUserAccount` Cloud Function |

#### `features/profile/presentation/widgets/user_images_grid.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Fetch user image data |

#### `features/profile/presentation/widgets/notifications_settings_drawer.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Get and update push notification preferences |

#### `features/profile/presentation/components/profile_header.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Fetch follower/following counts |
| `Users/{uid}/following` | read | Check if user follows another |

#### `features/profile/presentation/screens/blocked_users_screen.dart`
**Layer:** Screen ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Batch fetch blocked user details for display |

---

### 4. ⭐ REVIEWS

#### `features/reviews/data/repositories/review_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `PendingReviews` | read/write/stream/delete | Full lifecycle of pending reviews |
| `Reviews` | read/write/stream | Submit reviews, query review history |
| `events/{id}/ConfirmedParticipants` | read | Check confirmed participants |
| `Users` | read | Get reviewer/reviewee data for review submission |

#### `features/reviews/data/repositories/actions_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `events` | read/write | Fetch event data and update action flags |

#### `features/reviews/presentation/services/pending_reviews_listener_service.dart`
**Layer:** Presentation/Service  
| Collection | Operation | Context |
|---|---|---|
| `PendingReviews` | stream | Real-time listener for pending reviews |

#### `features/reviews/presentation/dialogs/review_dialog_controller.dart`
**Layer:** Presentation/Controller ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `PendingReviews` | write (batch) | Delete pending review after submission |
| `events/{id}/ConfirmedParticipants` | write (batch) | Mark participant as reviewed |
| `Reviews` | write (batch) | Create new review doc |
| `Users` | read | Get reviewer info |

#### `features/reviews/presentation/dialogs/review_dialog.dart`
**Layer:** Presentation/Dialog ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `PendingReviews` | write (batch) | Delete pending review |
| `Reviews` | write (batch) | Create review |

---

### 5. 📸 EVENT PHOTO FEED

#### `features/event_photo_feed/data/repositories/event_photo_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `EventPhotos` | read/write | Photo CRUD operations |
| `feeds` | read/write | Fan-out feed documents |
| `Users/{uid}/following` | read | Get following list for feed distribution |
| (uses FirebaseStorage) | write | Upload event photos |

#### `features/event_photo_feed/domain/services/event_photo_like_service.dart`
**Layer:** Domain/Service  
| Collection | Operation | Context |
|---|---|---|
| `EventPhotos` | stream | Listen to photo doc for like count |
| `EventPhotos/{id}/likes` | stream/write | Listen to like status, toggle likes |

#### `features/event_photo_feed/domain/services/event_photo_likes_cache_service.dart`
**Layer:** Domain/Service  
| Collection | Operation | Context |
|---|---|---|
| `EventPhotos/{id}/likes` | read | Batch prefetch like status |

#### `features/event_photo_feed/domain/services/recent_events_service.dart`
**Layer:** Domain/Service  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read | Query recent events for feed |

#### `features/event_photo_feed/domain/services/feed_preloader.dart`
**Layer:** Domain/Service  
| Collection | Operation | Context |
|---|---|---|
| `Users/{uid}/following` | read | Get following list for feed filtering |

#### `features/event_photo_feed/presentation/controllers/event_photo_composer_controller.dart`
**Layer:** Presentation/Controller ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `EventPhotos` | write | Generate photo ID and upload photo doc directly |

#### `features/event_photo_feed/presentation/controllers/event_photo_feed_controller.dart`
**Layer:** Presentation/Controller  
| Collection | Operation | Context |
|---|---|---|
| `Users/{uid}/following` | read | Check following relationships |

#### `features/event_photo_feed/presentation/services/feed_onboarding_service.dart`
**Layer:** Presentation/Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Check/update feed onboarding flag |

#### `features/event_photo_feed/presentation/services/feed_reminder_service.dart`
**Layer:** Presentation/Service  
| Collection | Operation | Context |
|---|---|---|
| `events_card_preview` | read | Get events for reminder logic |
| `EventPhotos` | read | Check if user has photos for recent events |

#### `features/event_photo_feed/presentation/widgets/event_photo_participant_selector_sheet.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| (via firestore) | read | Query participants for photo tagging |

---

### 6. 🔔 NOTIFICATIONS

#### `features/notifications/repositories/notifications_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `Notifications` | stream/read/write | Full notification lifecycle with real-time streams |

#### `features/notifications/services/fcm_token_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `DeviceTokens` | read/write/delete | Manage FCM device tokens |

#### `features/notifications/services/notification_orchestrator.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read | Orchestrate notification delivery decisions |

#### `features/notifications/services/activity_notification_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| (via _firestore) | read | Query activities for notification targeting |

#### `features/notifications/services/notification_targeting_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Fetch event data for notification targeting |

#### `features/notifications/services/user_affinity_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Compute user affinity scores based on profile data |

#### `features/notifications/helpers/app_notifications.dart`
**Layer:** Helper ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | read | Navigate to conversation from notification tap |
| `Users` | read | Load user data for notification display |
| `Events` | read | Load event data for notification display |

---

### 7. 🔐 AUTH / REGISTRATION / VERIFICATION

#### `shared/repositories/auth_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | User registration, profile updates |
| (uses FirebaseAuth) | auth | Sign in/out, user lifecycle |
| (uses FirebaseStorage) | write | Profile image uploads |

#### `shared/services/auth/social_auth.dart`
**Layer:** Service ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Check if user doc exists during social login (Apple, Google) |

#### `features/auth/presentation/controllers/cadastro_view_model.dart`
**Layer:** ViewModel  
| Collection | Operation | Context |
|---|---|---|
| `Users` | write | Create user profile during registration |

#### `core/services/auth_sync_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | stream | Listen to user document for auth state sync |

#### `core/services/didit_verification_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `AppInfo` | read | Get Didit config (API key, etc.) |
| `DiditSessions` | read/write | Create and check verification sessions |
| `FaceVerifications` | read | Check existing verifications |
| `DiditSessions` | stream | Listen for verification completion |

#### `core/services/face_verification_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `FaceVerifications` | read/write | Store/query face verification status |
| `Users` | read/write | Update user verification flag |
| `Users` | stream | Listen for verification status changes |

---

### 8. 🧊 CORE SERVICES

#### `core/services/block_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `blockedUsers` | read/write/stream/delete | Full block/unblock lifecycle with real-time cache |

#### `core/services/user_status_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `users_preview` | read/write | Update user online/offline status |

#### `core/services/report_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Get event data for report context |
| `reports` | write | Submit user/event reports |

#### `core/services/push_preferences_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | write | Update push notification preferences |

#### `core/services/session_cleanup_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| — | admin | `clearPersistence()` — clears Firestore local cache |

#### `core/services/google_maps_config_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `AppInfo` | read | Fetch Google Maps configuration (style JSON, etc.) |

#### `core/services/geo_index_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Manage geohash indexes for user discovery |

#### `core/services/location_background_updater.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Read user location config, write location updates |

#### `core/services/feature_flags_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `AppInfo` | read | Fetch feature flags |

#### `core/services/cache/user_cache_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Cached user document reads |

---

### 9. 🏪 SHARED STORES

#### `shared/stores/user_store.dart`
**Layer:** Store (global state)  
| Collection | Operation | Context |
|---|---|---|
| `users_preview` | read/stream | Get and listen to user preview docs |
| `Users` | stream | Listen to full user docs for detailed views |

#### `shared/stores/avatar_store.dart`
**Layer:** Store (global state)  
| Collection | Operation | Context |
|---|---|---|
| `Users` | stream | Listen to user doc changes for avatar URL updates |

---

### 10. 📍 LOCATION SERVICES (legacy `services/`)

#### `services/location/location_query_service.dart`
**Layer:** Service (legacy)  
| Collection | Operation | Context |
|---|---|---|
| `Users/{id}/private` | read | Get private location data |
| `Users` | read/write | Fetch user data, update location preferences |

#### `services/location/radius_controller.dart`
**Layer:** Controller (legacy)  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Load and save radius preference |

#### `services/location/advanced_filters_controller.dart`
**Layer:** Controller (legacy)  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Load and save all filter preferences (age, gender, distance, etc.) |

#### `services/location/people_cloud_service.dart`
**Layer:** Service (legacy)  
| Collection | Operation | Context |
|---|---|---|
| — | callable | `queryPeopleByGeohash`, `queryPeopleSmartFiltered` Cloud Functions |

#### `services/events/event_creator_filters_controller.dart`
**Layer:** Controller (legacy)  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write | Load/save event creator filter preferences |

---

### 11. 📊 FEED

#### `features/feed/data/repositories/activity_feed_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `ActivityFeed` | read | Query activity feed items |

---

### 12. 🌐 EVENTS (group_info)

#### `features/events/presentation/screens/group_info/group_info_controller.dart`
**Layer:** Controller ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Fetch user data |
| `EventApplications` | read | Get participant status |
| `events` | write | Update event details (5+ direct writes) |
| `EventApplications` | write | Update application status |
| `Connections/{uid}/Conversations` | read | Check conversation exists |

---

### 13. 💎 SUBSCRIPTION

#### `features/subscription/services/simple_revenue_cat_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `SubscriptionStatus` | read | Check subscription status from Firestore |
| `Users` | read | Get user subscription data |

#### `features/subscription/services/vip_sync_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| — | callable | `syncVipStatus` Cloud Function |

---

### 14. 🗃️ SHARED REPOSITORIES

#### `shared/repositories/user_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read/write/stream | Full user CRUD, real-time listener |
| `users_preview` | read | Preview collection access |

#### `shared/repositories/device_repository.dart`
**Layer:** Repository  
| Collection | Operation | Context |
|---|---|---|
| — | callable | `checkDeviceBlacklist`, `registerDevice` Cloud Functions |

---

### 15. 📌 COMMON SERVICES

#### `common/services/notifications_counter_service.dart`
**Layer:** Service  
| Collection | Operation | Context |
|---|---|---|
| `Connections/{uid}/Conversations` | stream | Count unread conversations in real-time |
| `Notifications` | stream | Count unread notifications in real-time |

---

### 16. 🖥️ WEB DASHBOARD

#### `features/web_dashboard/screens/events_table_screen.dart`
**Layer:** Screen ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Admin: fetch events for table display |

#### `features/web_dashboard/screens/users_table_screen.dart`
**Layer:** Screen ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `Users` | read | Admin: count and fetch users |

#### `features/web_dashboard/screens/reports_table_screen.dart`
**Layer:** Screen ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `reports` | stream | Admin: real-time reports stream |

---

### 17. 📦 SHARED WIDGETS (direct Firestore access)

#### `shared/widgets/report_event_button.dart`
**Layer:** Widget ⚠️  
| Collection | Operation | Context |
|---|---|---|
| `events` | read | Fetch event data for report |
| `reports` | write | Submit report |
| `Connections/{uid}/Conversations` | delete | Remove conversation when blocking |

---

## ☁️ CLOUD FUNCTION CALLS (from Flutter client)

| Function Name | Calling File | Purpose |
|---|---|---|
| `deleteUserAccount` | `app_section_card.dart` (Widget!) | Delete user account and all data |
| `deleteEvent` | `event_deletion_service.dart`, `event_application_removal_service.dart` | Delete event and cleanup |
| `deleteChatMessage` | `chat_message_deletion_service.dart` | Delete a chat message |
| `removeUserApplication` | `event_application_removal_service.dart`, `event_application_repository.dart` | Remove user's event application |
| `removeParticipant` | `event_application_removal_service.dart` | Remove participant from event |
| `followUser` | `follow_remote_datasource.dart` | Follow a user |
| `unfollowUser` | `follow_remote_datasource.dart` | Unfollow a user |
| `queryPeopleByGeohash` | `people_cloud_service.dart` | Geo-based people search |
| `queryPeopleSmartFiltered` | `people_cloud_service.dart` | Smart-filtered people search |
| `syncVipStatus` | `vip_sync_service.dart` | Sync VIP/subscription status |
| `checkDeviceBlacklist` | `device_repository.dart` | Check if device is blacklisted |
| `registerDevice` | `device_repository.dart` | Register new device |

---

## 🔴 CRITICAL FINDINGS & ARCHITECTURAL CONCERNS

### 1. Direct Firestore Access in Widgets/Presentation Layer
The following files access Firestore directly from widgets or presentation-layer code, violating Clean Architecture:

| File | Severity | Issue |
|---|---|---|
| `event_card_controller.dart` | 🔴 HIGH | 6+ Firestore calls, 4 streams, in a per-card controller |
| `group_info_controller.dart` | 🔴 HIGH | 10+ direct Firestore reads/writes |
| `app_section_card.dart` | 🔴 HIGH | 6 direct writes + Cloud Function call in widget |
| `invite_drawer.dart` | 🟡 MEDIUM | 3 direct reads in widget |
| `referral_debug_screen.dart` | 🟡 LOW | Debug screen, acceptable |
| `user_images_grid.dart` | 🟡 MEDIUM | 1 direct read in widget |
| `notifications_settings_drawer.dart` | 🟡 MEDIUM | 1 read + 1 write in widget |
| `profile_header.dart` | 🟡 MEDIUM | 2 reads in widget |
| `blocked_users_screen.dart` | 🟡 MEDIUM | 1 batch read in screen |
| `report_event_button.dart` | 🟡 MEDIUM | 3 operations in shared widget |
| `confirm_presence_widget.dart` | 🟡 MEDIUM | 1 read + 1 write in widget |
| `user_presence_status_widget.dart` | 🔴 HIGH | Stream listener directly in widget |
| `chat_screen_refactored.dart` | 🟡 MEDIUM | 1 query in screen |
| `presence_drawer.dart` | 🟡 MEDIUM | 1 read in widget |
| `chat_app_bar_widget.dart` | 🟡 MEDIUM | 1 read in widget |
| `conversation_stream_widget.dart` | 🟡 MEDIUM | 1 read in widget |
| `event_photo_composer_controller.dart` | 🟡 MEDIUM | 2 direct writes |
| `event_photo_participant_selector_sheet.dart` | 🟡 MEDIUM | Direct firestore instance |
| Web dashboard screens | 🟢 LOW | Admin-only, acceptable |

### 2. Active Real-Time Streams (Cost & Performance)
**~50 `.snapshots()` streams** exist. Major stream consumers:

| Stream Source | Count | Concern |
|---|---|---|
| `event_card_controller.dart` | 4 streams per card | 🔴 Each visible event card opens 4 Firestore listeners |
| `conversations_viewmodel.dart` | 1 master stream | Conversations list — expected |
| `chat_repository.dart` | 3 streams | Messages + user doc — expected |
| `block_service.dart` | 3 streams | Blocked by me + blocked me + unified — expected |
| `user_store.dart` | N streams (per user) | Opens preview + full streams per viewed user |
| `avatar_store.dart` | N streams (per user) | Opens stream per cached avatar |
| `notifications_counter_service.dart` | 2 streams | Conversations + notifications counter |
| `notifications_repository.dart` | Multiple | Notification list streams |
| `review_repository.dart` | 4 streams | Pending reviews and review history |
| `profile_controller.dart` | 2 streams | Profile doc + reviews |
| `profile_visits_service.dart` | 1 stream | Recent visitors |
| `pending_applications_repository.dart` | 2 streams | Events + applications |
| `auth_sync_service.dart` | 1 stream | User doc sync |

### 3. Collection Naming Inconsistency
**Mixed PascalCase and camelCase/snake_case in collection names:**

| Convention | Collections |
|---|---|
| PascalCase ✅ | `Users`, `EventApplications`, `EventChats`, `EventPhotos`, `Connections`, `Conversations`, `Messages`, `Reviews`, `PendingReviews`, `Notifications`, `ProfileVisits`, `ProfileViews`, `DeviceTokens`, `DiditSessions`, `FaceVerifications`, `ReferralInstalls`, `BlockedUsers`, `AppInfo`, `SubscriptionStatus`, `PaymentStatuses` |
| camelCase/snake_case ❌ | `events`, `events_card_preview`, `users_preview`, `blockedUsers`, `reports`, `event_tombstones`, `feeds`, `ranking`, `userRanking`, `locationRanking` |

Per the `.github/instructions`: collections should use **minúsculo + plural** (lowercase + plural). Neither convention is consistently followed.

### 4. Duplicated Firestore Access Patterns
- **`Users` collection** is accessed from 30+ different files without a centralized API
- **`Connections/{uid}/Conversations`** is accessed from 10+ files independently
- **`EventApplications`** is accessed from 7+ files with different query patterns

### 5. Authentication Pattern
- Auth is handled via `FirebaseAuth.instance` directly in 30+ files
- `shared/services/auth/social_auth.dart` handles Apple/Google sign-in
- `shared/repositories/auth_repository.dart` is the main auth repository
- `core/services/auth_sync_service.dart` syncs auth state with Firestore user doc
- No centralized auth state management — scattered `FirebaseAuth.instance.currentUser?.uid` calls

### 6. FirebaseStorage Access
Used in 7 files for image uploads/downloads:
- `image_upload_view_model.dart`
- `image_upload_service.dart`
- `event_photo_composer_service.dart`
- `event_photo_repository.dart`
- `auth_repository.dart`
- `chat_repository.dart`
- `cache_key_utils.dart`

---

## 📊 Summary Statistics

| Metric | Count |
|---|---|
| Files with `FirebaseFirestore.instance` | **65+** |
| Unique Firestore collections accessed | **28+** |
| Active `.snapshots()` streams | **50** |
| Cloud Function calls | **14** |
| `StreamSubscription` declarations | **48** |
| Widgets with direct Firestore access | **18** |
| Repository files | **12** |
| Service files | **35+** |
| ViewModel/Controller files | **15+** |
| Firebase Auth direct access points | **30+** |
| Firebase Storage access points | **7** |

---

## 🎯 Recommendations

1. **Centralize `Users` collection access** — Create a single `UserFirestoreDataSource` used by all services
2. **Move all Firestore calls out of widgets/controllers** — Route through repositories/services
3. **Standardize collection naming** — Pick one convention (lowercase plural per project guidelines)
4. **Audit stream lifecycle** — Especially `event_card_controller.dart` (4 streams per card is very costly)
5. **Consolidate `Connections/Conversations` access** — Single service for all conversation operations
6. **Create auth wrapper** — Replace 30+ `FirebaseAuth.instance.currentUser?.uid` with injected auth service
7. **Complete Clean Architecture migration** — Some features (auth, events) only have presentation layer
