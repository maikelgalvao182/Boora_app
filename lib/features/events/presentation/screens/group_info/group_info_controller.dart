import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/screens/chat/services/event_application_removal_service.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';
import 'package:partiu/core/services/toast_service.dart';
import 'package:partiu/core/services/block_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import 'package:partiu/core/services/global_cache_service.dart';

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
  String? _error;
  Map<String, dynamic>? _eventData;
  List<Map<String, dynamic>> _participants = [];
  bool _isMuted = false;
  
  /// Notifier exclusivo para a lista de participantes (evita rebuilds desnecessários)
  final ValueNotifier<List<String>> participantsNotifier = ValueNotifier([]);

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get eventName => _eventData?['activityText'] as String? ?? 'Event';
  String get eventEmoji => _eventData?['emoji'] as String? ?? '🎉';
  String? get eventLocation => _eventData?['locationText'] as String?;
  String? get eventDescription => _eventData?['description'] as String?;
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
      // Participantes não veem bloqueados
      final currentUserId = AppState.currentUserId;
      if (currentUserId == null) {
        filteredList = allUserIds;
      } else {
        filteredList = allUserIds
            .where((userId) => !BlockService().isBlockedCached(currentUserId, userId))
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

    final lat = _eventData?['latitude'] as double?;
    final lng = _eventData?['longitude'] as double?;

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
      // Tenta carregar do cache primeiro
      final cacheKey = 'event_data_$eventId';
      final cachedData = GlobalCacheService.instance.get<Map<String, dynamic>>(cacheKey);
      
      if (cachedData != null) {
        _eventData = cachedData;
        debugPrint('✅ Event data loaded from cache for $eventId');
        return;
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
      
      // Salva no cache (TTL 5 min)
      if (_eventData != null) {
        GlobalCacheService.instance.set(cacheKey, _eventData, ttl: const Duration(minutes: 5));
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

  void showDeleteEventDialog(BuildContext context) {
    if (!isCreator) return;

    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    final deletionService = EventDeletionService();

    deletionService.handleDeleteEvent(
      context: context,
      eventId: eventId,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: () {
        // Navega até a raiz (DiscoverTab/HomeScreen)
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              // Força a navegação para a tab 0 (Discover)
              context.go(Uri(path: AppRoutes.home, queryParameters: {'tab': '0'}).toString());
            }
          });
        }
      },
    );
  }

  void showLeaveEventDialog(BuildContext context) {
    if (isCreator) return; // Criador não pode sair, só deletar

    final i18n = AppLocalizations.of(context);
    final progressDialog = ProgressDialog(context);
    final removalService = EventApplicationRemovalService();

    removalService.handleLeaveEvent(
      context: context,
      eventId: eventId,
      i18n: i18n,
      progressDialog: progressDialog,
      onSuccess: () {
        // Navega até a raiz (DiscoverTab/HomeScreen)
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              // Força a navegação para a tab 0 (Discover)
              context.go(Uri(path: AppRoutes.home, queryParameters: {'tab': '0'}).toString());
            }
          });
        }
      },
    );
  }
}
