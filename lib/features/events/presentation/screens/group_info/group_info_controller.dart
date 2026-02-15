import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/schedule_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/category_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/category/activity_category.dart';
import 'package:partiu/features/home/presentation/widgets/participants_drawer.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/features/home/presentation/screens/location_picker/location_picker_page_refactored.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/screens/chat/services/event_application_removal_service.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:partiu/core/services/user_status_service.dart';
import 'package:partiu/shared/widgets/dialogs/cupertino_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import 'package:partiu/core/services/global_cache_service.dart';
import 'package:partiu/features/events/state/event_store.dart';

/// Controller para a tela de informações do grupo/evento
class GroupInfoController extends ChangeNotifier {
  // Singleton/Multiton pattern
  static final Map<String, GroupInfoController> _instances = {};

  factory GroupInfoController({required String eventId}) {
    if (!_instances.containsKey(eventId)) {
      _instances[eventId] = GroupInfoController._internal(eventId: eventId);
    }
    return _instances[eventId]!;
  }

  GroupInfoController._internal({required this.eventId}) {
    _init();
    _initBlockListener();
  }

  final String eventId;
  final EventRepository _eventRepository = EventRepository();
  final EventApplicationRepository _applicationRepository = EventApplicationRepository();

  bool _isLoading = true;
  bool _isLeaving = false;
  String? _error;
  Map<String, dynamic>? _eventData;
  List<Map<String, dynamic>> _participants = [];
  bool _isMuted = false;
  
  Map<String, dynamic>? get _eventMapLocation {
    final raw = _eventData?['mapLocation'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  Map<String, dynamic>? get _eventLocation {
    final raw = _eventData?['location'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String? _toNonEmptyString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String? _pickFirstString(List<dynamic> values) {
    for (final value in values) {
      final normalized = _toNonEmptyString(value);
      if (normalized != null) return normalized;
    }
    return null;
  }

  double? _extractLatitude() {
    final mapLocation = _eventMapLocation;
    final location = _eventLocation;
    final locationGeoPoint = _eventData?['locationGeoPoint'];

    return _toDouble(mapLocation?['latitude']) ??
        _toDouble(mapLocation?['lat']) ??
        _toDouble(location?['latitude']) ??
        _toDouble(location?['lat']) ??
        (location?['geoPoint'] is GeoPoint ? (location?['geoPoint'] as GeoPoint).latitude : null) ??
        (locationGeoPoint is GeoPoint ? locationGeoPoint.latitude : null) ??
        _toDouble(_eventData?['latitude']) ??
        _toDouble(_eventData?['lat']);
  }

  double? _extractLongitude() {
    final mapLocation = _eventMapLocation;
    final location = _eventLocation;
    final locationGeoPoint = _eventData?['locationGeoPoint'];

    return _toDouble(mapLocation?['longitude']) ??
        _toDouble(mapLocation?['lng']) ??
        _toDouble(location?['longitude']) ??
        _toDouble(location?['lng']) ??
        (location?['geoPoint'] is GeoPoint ? (location?['geoPoint'] as GeoPoint).longitude : null) ??
        (locationGeoPoint is GeoPoint ? locationGeoPoint.longitude : null) ??
        _toDouble(_eventData?['longitude']) ??
        _toDouble(_eventData?['lng']);
  }

  /// Notifier exclusivo para a lista de participantes (evita rebuilds desnecessários)
  final ValueNotifier<List<String>> participantsNotifier = ValueNotifier([]);

  bool get isLoading => _isLoading;
  bool get isLeaving => _isLeaving;
  String? get error => _error;
  String get eventName => _eventData?['activityText'] as String? ?? 'Event';
  String get eventEmoji => _eventData?['emoji'] as String? ?? '🎉';
  String? get eventLocation {
    final mapLocation = _eventMapLocation;
    final location = _eventLocation;
    return _pickFirstString([
      mapLocation?['locationName'],
      mapLocation?['name'],
      mapLocation?['formattedAddress'],
      mapLocation?['address'],
      location?['locationName'],
      location?['name'],
      location?['formattedAddress'],
      location?['address'],
      _eventData?['mapLocation.locationName'],
      _eventData?['mapLocation.formattedAddress'],
      _eventData?['locationName'],
      _eventData?['formattedAddress'],
      _eventData?['locationText'],
    ]);
  }

  String? get eventLocationName {
    final mapLocation = _eventMapLocation;
    final location = _eventLocation;
    return _pickFirstString([
      mapLocation?['locationName'],
      mapLocation?['name'],
      location?['locationName'],
      location?['name'],
      _eventData?['mapLocation.locationName'],
      _eventData?['locationName'],
      _eventData?['locationText'],
    ]);
  }

  String? get eventFormattedAddress {
    final mapLocation = _eventMapLocation;
    final location = _eventLocation;
    return _pickFirstString([
      mapLocation?['formattedAddress'],
      mapLocation?['address'],
      location?['formattedAddress'],
      location?['address'],
      _eventData?['mapLocation.formattedAddress'],
      _eventData?['formattedAddress'],
      _eventData?['locationText'],
    ]);
  }
  String? get eventDescription => _eventData?['description'] as String?;
  
  // Categoria do evento
  String? get eventCategory => _eventData?['category'] as String?;
  
  // Dados de participantes/filtros
  int? get eventMinAge => _eventData?['minAge'] as int?;
  int? get eventMaxAge => _eventData?['maxAge'] as int?;
  String? get eventGender => _eventData?['gender'] as String?;
  String? get eventPrivacyType => _eventData?['privacyType'] as String?;
  
  // Localização
  double? get eventLatitude => _extractLatitude();

  double? get eventLongitude => _extractLongitude();
  
  DateTime? get eventDate {
    final schedule = _eventData?['schedule'];
    if (schedule == null || schedule is! Map) return null;
    final date = schedule['date'];
    if (date is Timestamp) return date.toDate();
    if (date is DateTime) return date;
    return null;
  }
  String? get eventTime {
    final schedule = _eventData?['schedule'];
    if (schedule == null || schedule is! Map) return null;
    return schedule['time'] as String?;
  }
  int? get maxParticipants => _eventData?['maxParticipants'] as int?;
  int get participantCount => _participants.length;
  List<Map<String, dynamic>> get participants => _participants;
  
  /// Retorna lista de IDs de participantes (usa o valor cacheado no Notifier)
  List<String> get participantUserIds => participantsNotifier.value;

  /// Atualiza a lista filtrada de participantes e notifica listeners
  void _updateParticipantsList() {
    final allUserIds = _participants
        .map((p) => p['userId'] as String)
        .toList();
    
    List<String> filteredList;
    
    // Criador vê todos os participantes
    if (isCreator) {
      filteredList = allUserIds;
    } else {
      // Participantes não veem bloqueados nem inativos
      final currentUserId = AppState.currentUserId;
      if (currentUserId == null) {
        filteredList = allUserIds;
      } else {
        filteredList = allUserIds
            .where((userId) {
              // Filtrar usuários bloqueados
              if (BlockService().isBlockedCached(currentUserId, userId)) {
                return false;
              }
              // Filtrar usuários inativos
              if (UserStatusService().isUserInactive(userId)) {
                debugPrint('👤 [GroupInfo] Ocultando participante inativo: $userId');
                return false;
              }
              return true;
            })
            .toList();
      }
    }

    // Só atualiza se houver mudança real (ValueNotifier faz check de igualdade, 
    // mas como é lista nova, sempre notificaria. Aqui poderíamos otimizar mais se necessário)
    participantsNotifier.value = filteredList;
  }

  bool get isMuted => _isMuted;
  bool get isPrivate => _eventData?['privacyType'] == 'private';
  bool get isCreator => _eventData?['createdBy'] == AppState.currentUserId;
  String? get creatorId => _eventData?['createdBy'] as String?;
  
  /// Retorna a data formatada do evento (lógica movida do build)
  String? get formattedEventDate {
    final date = eventDate;
    if (date == null) return null;
    
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year às $hour:$minute';
  }

  void _initBlockListener() {
    BlockService.instance.addListener(_onBlockedUsersChanged);
  }

  void _onBlockedUsersChanged() {
    _updateParticipantsList();
  }

  @override
  void dispose() {
    // Ignora dispose para manter o estado vivo (Singleton/Multiton)
    debugPrint('⚠️ GroupInfoController dispose ignored to keep state alive for event $eventId');
  }

  /// Força o dispose do controller e remove da lista de instâncias
  void forceDispose() {
    _instances.remove(eventId);
    super.dispose();
  }

  Future<void> openInMaps() async {
    if (eventLocation == null) return;

    final lat = eventLatitude;
    final lng = eventLongitude;

    if (lat == null || lng == null) return;

    final url = 'https://maps.apple.com/?q=$lat,$lng';
    final uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('❌ Error opening maps: $e');
    }
  }

  Future<void> _init() async {
    await _loadEventData();
    await _loadParticipants();
    await _loadUserPreferences();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadUserPreferences() async {
    final userId = AppState.currentUserId;
    if (userId == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final advancedSettings = data?['advancedSettings'] as Map<String, dynamic>?;
        final pushPrefs = advancedSettings?['push_preferences'] as Map<String, dynamic>?;
        final groups = pushPrefs?['groups'] as Map<String, dynamic>?;
        final groupPrefs = groups?[eventId] as Map<String, dynamic>?;

        if (groupPrefs != null) {
          _isMuted = groupPrefs['muted'] == true;
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading user preferences: $e');
    }
  }

  Future<void> _loadEventData() async {
    try {
      var loadedFromCache = false;

      // Tenta carregar do cache primeiro
      final cacheKey = 'event_data_$eventId';
      final cachedData = GlobalCacheService.instance.get<Map<String, dynamic>>(cacheKey);
      
      if (cachedData != null) {
        _eventData = cachedData;
        loadedFromCache = true;
        debugPrint('✅ Event data loaded from cache for $eventId');
      }

      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();

      if (!doc.exists) {
        _error = 'Event not found';
        return;
      }

      _eventData = doc.data();
      if (loadedFromCache) {
        debugPrint('🔄 Event data refreshed from Firestore for $eventId');
      }
      
      // Salva no cache (TTL 5 min)
      if (_eventData != null) {
        GlobalCacheService.instance.set(cacheKey, _eventData, ttl: const Duration(minutes: 5));
        
        // Atualiza EventStore
        EventStore.instance.setEventData(
          eventId,
          eventName,
          eventEmoji,
        );
      }
    } catch (e) {
      _error = 'Failed to load event: $e';
      debugPrint('❌ Error loading event: $e');
    }
  }

  Future<void> _loadParticipants() async {
    try {
      // Tenta carregar do cache primeiro
      final cacheKey = 'event_participants_$eventId';
      final cachedParticipants = GlobalCacheService.instance.get<List<dynamic>>(cacheKey);
      
      if (cachedParticipants != null) {
        _participants = List<Map<String, dynamic>>.from(cachedParticipants);
        _updateParticipantsList(); // Garante que o notifier seja atualizado com dados do cache
        debugPrint('✅ Participants loaded from cache for $eventId');
        return;
      }

      debugPrint('🔍 Buscando participantes para evento: $eventId');
      
      // Busca via repositório
      _participants = await _applicationRepository.getParticipantsForEvent(eventId);
      
      // Salva no cache (TTL 5 min)
      GlobalCacheService.instance.set(cacheKey, _participants, ttl: const Duration(minutes: 5));
      
      // Atualiza lista filtrada
      _updateParticipantsList();
      
      debugPrint('✅ ${_participants.length} participantes carregados para evento $eventId');
      debugPrint('📝 UserIds: ${_participants.map((p) => p['userId']).join(', ')}');
    } catch (e) {
      debugPrint('❌ Erro ao carregar participantes: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    // Invalida cache ao forçar refresh
    GlobalCacheService.instance.remove('event_data_$eventId');
    GlobalCacheService.instance.remove('event_participants_$eventId');
    
    await _init();
  }

  Future<void> toggleMute(bool value) async {
    _isMuted = value;
    notifyListeners();
    
    final userId = AppState.currentUserId;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .set({
            'advancedSettings': {
              'push_preferences': {
                'groups': {
                  eventId: {
                    'muted': value
                  }
                }
              }
            }
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Error saving mute preference: $e');
      // Revert on error
      _isMuted = !value;
      notifyListeners();
    }
  }

  Future<void> togglePrivacy(bool value) async {
    if (!isCreator) return;

    try {
      final newPrivacyType = value ? 'private' : 'open';
      
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update({'privacyType': newPrivacyType});

      _eventData?['privacyType'] = newPrivacyType;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error updating privacy: $e');
    }
  }

  void showEditNameDialog(BuildContext context) async {
    if (!isCreator) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateDrawer(
        coordinator: CreateFlowCoordinator(), // Coordinator vazio para modo edição
        initialName: eventName,
        initialEmoji: eventEmoji,
        editMode: true,
      ),
    );

    if (result != null) {
      final newName = result['name'] as String?;
      final newEmoji = result['emoji'] as String?;
      
      if (newName != null && newName.trim().isNotEmpty) {
        await _updateEventName(context, newName, newEmoji);
      }
    }
  }

  Future<void> _updateEventName(BuildContext context, String newName, String? newEmoji) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);

    try {
      progressDialog.show(i18n.translate('updating'));

      final updates = <String, dynamic>{
        'activityText': newName,
      };
      
      if (newEmoji != null && newEmoji.isNotEmpty) {
        updates['emoji'] = newEmoji;
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update(updates);

      _eventData?['activityText'] = newName;
      if (newEmoji != null) {
        _eventData?['emoji'] = newEmoji;
      }
      
      // Atualiza EventStore para refletir mudanças em toda a app
      EventStore.instance.updateEvent(
        eventId,
        name: newName,
        emoji: newEmoji,
      );

      notifyListeners();

      await progressDialog.hide();

      if (context.mounted) {
        ToastService.showSuccess(
          message: i18n.translate('event_name_updated'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error updating event name: $e');

      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_update_event_name'),
        );
      }
    }
  }

  void showEditScheduleDialog(BuildContext context) async {
    if (!isCreator) return;

    // Determine initial values from _eventData
    final date = eventDate;
    final timeStr = eventTime;
    
    TimeType initialTimeType = TimeType.flexible;
    DateTime? initialTime;
    
    if (timeStr != null && timeStr.isNotEmpty) {
      initialTimeType = TimeType.specific;
      // Parse time string "HH:mm" to DateTime
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final now = DateTime.now();
        initialTime = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      }
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleDrawer(
        coordinator: null,
        initialDate: date,
        initialTimeType: initialTimeType,
        initialTime: initialTime,
        editMode: true,
      ),
    );

    if (result != null) {
      final newDate = result['date'] as DateTime;
      final newTimeType = result['timeType'] as TimeType;
      final newTime = result['time'] as DateTime?;
      
      if (context.mounted) {
        await _updateEventSchedule(context, newDate, newTimeType, newTime);
      }
    }
  }

  Future<void> _updateEventSchedule(BuildContext context, DateTime date, TimeType timeType, DateTime? time) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);

    try {
      progressDialog.show(i18n.translate('updating'));

      final schedule = <String, dynamic>{
        'date': Timestamp.fromDate(date),
      };
      
      if (timeType == TimeType.specific && time != null) {
        final hour = time.hour.toString().padLeft(2, '0');
        final minute = time.minute.toString().padLeft(2, '0');
        schedule['time'] = '$hour:$minute';
      } else {
        schedule['time'] = null;
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update({'schedule': schedule});

      // Update local data
      if (_eventData != null) {
        _eventData!['schedule'] = schedule;
        // Convert Timestamp back to DateTime for local usage if needed, 
        // but getters handle Timestamp/DateTime/Map correctly
      }
      notifyListeners();

      await progressDialog.hide();

      if (context.mounted) {
        ToastService.showSuccess(
          message: i18n.translate('event_schedule_updated'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error updating event schedule: $e');

      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_update_event_schedule'),
        );
      }
    }
  }

  /// Abre drawer de edição de categoria
  void showEditCategoryDialog(BuildContext context) async {
    if (!isCreator) return;

    // Parse categoria atual
    ActivityCategory? currentCategory;
    if (eventCategory != null) {
      currentCategory = categoryFromString(eventCategory!);
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CategoryDrawer(
        coordinator: null,
        initialCategory: currentCategory,
        editMode: true,
      ),
    );

    if (result != null && context.mounted) {
      final newCategory = result['category'] as String?;
      if (newCategory != null) {
        await _updateEventCategory(context, newCategory);
      }
    }
  }

  Future<void> _updateEventCategory(BuildContext context, String category) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);

    try {
      progressDialog.show(i18n.translate('updating'));

      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update({'category': category});

      _eventData?['category'] = category;
      notifyListeners();

      await progressDialog.hide();

      if (context.mounted) {
        ToastService.showSuccess(
          message: i18n.translate('event_category_updated'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error updating event category: $e');

      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_update_event_category'),
        );
      }
    }
  }

  /// Abre drawer de edição de filtros/participantes
  void showEditParticipantsDialog(BuildContext context) async {
    if (!isCreator) return;

    // Parse PrivacyType atual
    PrivacyType? currentPrivacyType;
    if (eventPrivacyType == 'private') {
      currentPrivacyType = PrivacyType.private;
    } else if (eventGender != null && eventGender!.isNotEmpty && eventGender != 'all') {
      currentPrivacyType = PrivacyType.specificGender;
    } else {
      currentPrivacyType = PrivacyType.open;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ParticipantsDrawer(
        coordinator: null,
        editMode: true,
        initialMinAge: eventMinAge,
        initialMaxAge: eventMaxAge,
        initialPrivacyType: currentPrivacyType,
        initialGender: eventGender,
      ),
    );

    if (result != null && context.mounted) {
      await _updateEventParticipants(context, result);
    }
  }

  Future<void> _updateEventParticipants(BuildContext context, Map<String, dynamic> data) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);

    try {
      progressDialog.show(i18n.translate('updating'));

      final updates = <String, dynamic>{
        'minAge': data['minAge'],
        'maxAge': data['maxAge'],
        'gender': data['gender'],
      };

      // Mapear PrivacyType
      final privacyType = data['privacyType'];
      if (privacyType == PrivacyType.private) {
        updates['privacyType'] = 'private';
      } else {
        updates['privacyType'] = 'open';
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update(updates);

      // Atualizar dados locais
      _eventData?['minAge'] = data['minAge'];
      _eventData?['maxAge'] = data['maxAge'];
      _eventData?['gender'] = data['gender'];
      _eventData?['privacyType'] = updates['privacyType'];
      notifyListeners();

      await progressDialog.hide();

      if (context.mounted) {
        ToastService.showSuccess(
          message: i18n.translate('event_filters_updated'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error updating event participants: $e');

      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_update_event_filters'),
        );
      }
    }
  }

  /// Abre tela de edição de localização
  void showEditLocationDialog(BuildContext context) async {
    if (!isCreator) return;

    // Localização atual
    LatLng? currentLocation;
    if (eventLatitude != null && eventLongitude != null) {
      currentLocation = LatLng(eventLatitude!, eventLongitude!);
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => LocationPickerPageRefactored(
          displayLocation: currentLocation,
          coordinator: null,
          editMode: true,
        ),
      ),
    );

    if (result != null && context.mounted) {
      final lat = result['latitude'] as double?;
      final lng = result['longitude'] as double?;
      final locationText = result['locationText'] as String?;
      
      if (lat != null && lng != null) {
        await _updateEventLocation(context, lat, lng, locationText);
      }
    }
  }

  Future<void> _updateEventLocation(BuildContext context, double lat, double lng, String? locationText) async {
    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);

    try {
      progressDialog.show(i18n.translate('updating'));

      final updates = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'mapLocation.latitude': lat,
        'mapLocation.longitude': lng,
      };
      
      if (locationText != null) {
        updates['locationText'] = locationText;
        updates['mapLocation.locationName'] = locationText;
        updates['mapLocation.formattedAddress'] = locationText;
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .update(updates);

      _eventData?['latitude'] = lat;
      _eventData?['longitude'] = lng;
      final currentMapLocation = (_eventData?['mapLocation'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      currentMapLocation['latitude'] = lat;
      currentMapLocation['longitude'] = lng;
      if (locationText != null) {
        _eventData?['locationText'] = locationText;
        currentMapLocation['locationName'] = locationText;
        currentMapLocation['formattedAddress'] = locationText;
      }
      _eventData?['mapLocation'] = currentMapLocation;
      notifyListeners();

      await progressDialog.hide();

      if (context.mounted) {
        ToastService.showSuccess(
          message: i18n.translate('event_location_updated'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error updating event location: $e');

      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_update_event_location'),
        );
      }
    }
  }

  void showRemoveParticipantDialog(
    BuildContext context,
    String userId,
    String userName,
  ) {
    if (!isCreator) return;

    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    final removalService = EventApplicationRemovalService();

    removalService.handleRemoveParticipant(
      context: context,
      eventId: eventId,
      participantUserId: userId,
      participantName: userName,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: () {
        // Atualiza lista local
        _participants.removeWhere((p) => p['userId'] == userId);
        _updateParticipantsList();
        notifyListeners();
      },
    );
  }

  Future<bool> deleteEvent(BuildContext context) async {
    if (!isCreator) return false;

    final i18n = AppLocalizations.of(context);
    
    final progressDialog = ProgressDialog(context);
    final deletionService = EventDeletionService();

    try {
      progressDialog.show(i18n.translate('deleting_event'));
      
      final success = await deletionService.deleteEvent(eventId);
      
      await progressDialog.hide();
      
      // 🔍 DIAGNÓSTICO: Verificar se o CF realmente setou hidden/eventDeleted no Firestore
      if (success) {
        try {
          final userId = AppState.currentUserId;
          if (userId != null) {
            final convDoc = await FirebaseFirestore.instance
                .collection('Connections')
                .doc(userId)
                .collection('Conversations')
                .doc('event_$eventId')
                .get(const GetOptions(source: Source.server));
            
            if (convDoc.exists) {
              final data = convDoc.data();
              debugPrint('🔍 [DIAG] Conversation doc APÓS CF:');
              debugPrint('🔍 [DIAG]   hidden = ${data?['hidden']}');
              debugPrint('🔍 [DIAG]   eventDeleted = ${data?['eventDeleted']}');
              debugPrint('🔍 [DIAG]   deletedAt = ${data?['deletedAt']}');
              debugPrint('🔍 [DIAG]   timestamp = ${data?['timestamp']}');
              debugPrint('🔍 [DIAG]   All keys: ${data?.keys.toList()}');
            } else {
              debugPrint('🔍 [DIAG] Conversation doc NÃO EXISTE no Firestore');
            }
          }
        } catch (e) {
          debugPrint('🔍 [DIAG] Erro ao verificar doc: $e');
        }
      }
      
      if (success && context.mounted) {
        ToastService.showSuccess(
          message: i18n.translate('event_deleted_successfully'),
        );
        
        // 🗑️ Remoção otimista: ocultar conversation tile imediatamente
        try {
          final viewModel = Provider.of<ConversationsViewModel>(context, listen: false);
          viewModel.optimisticRemoveByConversationId('event_$eventId');
          debugPrint('🗑️ Conversa event_$eventId removida otimisticamente');
        } catch (e) {
          debugPrint('⚠️ Não foi possível remover conversa otimisticamente: $e');
        }
        
        // 🗺️ Remover marker do mapa
        MapViewModel.instance?.removeEvent(eventId);
        debugPrint('🗺️ Marker removido do mapa');
        
        // 🗑️ Remover instância do controller (evento não existe mais)
        _instances.remove(eventId);
        
        // ⚠️ IMPORTANTE: Fechar TODAS as telas e ir para home
        // Primeiro, pop até a raiz (remove Chat e GroupInfo da pilha)
        debugPrint('🏠 ============================================= ');
        debugPrint('🏠 Evento deletado! Navegando para home...');
        debugPrint('🏠 ============================================= ');
        
        // Usar Navigator para pop até a raiz e depois go para home
        if (context.mounted) {
          // Pop todas as rotas até a raiz
          Navigator.of(context).popUntil((route) => route.isFirst);
          
          // Agora navegar para home com tab 0
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              debugPrint('🏠 ============================================= ');
              debugPrint('🏠 Executando context.go para home...');
              debugPrint('🏠 ============================================= ');
              context.go('${AppRoutes.home}?tab=0');
            }
          });
        }
        
        return true;
      } else if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_delete_event'),
        );
        return false;
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error deleting event: $e');
      
      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('failed_to_delete_event'),
        );
      }
      return false;
    }
    return false;
  }

  Future<void> showLeaveEventDialog(BuildContext context) async {
    if (isCreator) return; // Criador não pode sair, só deletar

    final i18n = AppLocalizations.of(context);
    
    debugPrint('🚪 [GroupInfo] showLeaveEventDialog iniciado');
    debugPrint('   - eventId: $eventId');
    
    final confirmed = await GlimpseCupertinoDialog.showDestructive(
      context: context,
      title: i18n.translate('leave_event'),
      message: i18n.translate('leave_event_confirmation')
          .replaceAll('{event}', eventName),
      destructiveText: i18n.translate('leave'),
      cancelText: i18n.translate('cancel'),
    );

    debugPrint('🚪 [GroupInfo] Usuário confirmou sair? $confirmed');
    
    if (confirmed != true || !context.mounted) {
      debugPrint('🚪 [GroupInfo] Ação cancelada ou context não montado');
      return;
    }

    // Captura o router ANTES de qualquer operação assíncrona
    final router = GoRouter.of(context);
    debugPrint('🚪 [GroupInfo] Router capturado: ${router.hashCode}');

    // Ativa loading no botão
    _isLeaving = true;
    notifyListeners();
    debugPrint('🚪 [GroupInfo] Loading ativado (_isLeaving = true)');

    try {
      final currentUserId = AppState.currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      debugPrint('🚪 [GroupInfo] Removendo aplicação do evento...');
      debugPrint('   - userId: $currentUserId');
      debugPrint('   - eventId: $eventId');

      // Remove a aplicação do evento
      try {
        await _applicationRepository.removeUserApplication(
          eventId: eventId,
          userId: currentUserId,
        );
        debugPrint('✅ [GroupInfo] Aplicação removida com sucesso');
      } on FirebaseFunctionsException catch (e) {
        // Se a aplicação não existe (evento deletado ou já saiu), trata como sucesso
        if (e.code == 'not-found') {
          debugPrint('⚠️ [GroupInfo] Aplicação não encontrada (evento já deletado ou já saiu). Tratando como sucesso.');
        } else {
          rethrow;
        }
      }

      // 🗑️ Remoção otimista: ocultar conversation tile imediatamente
      try {
        final viewModel = Provider.of<ConversationsViewModel>(context, listen: false);
        viewModel.optimisticRemoveByConversationId('event_$eventId');
        debugPrint('🗑️ Conversa event_$eventId removida otimisticamente');
      } catch (e) {
        debugPrint('⚠️ Não foi possível remover conversa otimisticamente: $e');
      }

      // Desativa loading ANTES de navegar para evitar rebuilds
      _isLeaving = false;
      notifyListeners();
      debugPrint('🚪 [GroupInfo] Loading desativado (_isLeaving = false)');

      if (!context.mounted) {
        debugPrint('⚠️ [GroupInfo] Context não está mais montado após remoção');
        return;
      }

      // Navega para ConversationsTab (tab 3) usando pushReplacement
      final targetRoute = Uri(path: AppRoutes.home, queryParameters: {'tab': '3'}).toString();
      debugPrint('🚪 [GroupInfo] Navegando para: $targetRoute');
      debugPrint('   - AppRoutes.home: ${AppRoutes.home}');
      
      // Usa pushReplacement para substituir toda a pilha de navegação
      router.pushReplacement(targetRoute);
      debugPrint('✅ [GroupInfo] Navegação executada (pushReplacement)');

      ToastService.showSuccess(
        message: i18n.translate('left_event_success'),
      );
      debugPrint('✅ [GroupInfo] Toast de sucesso exibido');
    } catch (e, stackTrace) {
      debugPrint('❌ [GroupInfo] Erro ao sair do evento: $e');
      debugPrint('❌ [GroupInfo] Stack trace: $stackTrace');
      
      _isLeaving = false;
      notifyListeners();
      
      if (context.mounted) {
        ToastService.showError(
          message: i18n.translate('leave_event_error'),
        );
      }
    }
  }
}
