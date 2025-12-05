import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:partiu/common/state/app_state.dart';
import 'package:partiu/core/router/app_router.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/dialogs/common_dialogs.dart';
import 'package:partiu/dialogs/progress_dialog.dart';
import 'package:partiu/features/home/presentation/widgets/create_drawer.dart';
import 'package:partiu/features/home/data/repositories/event_application_repository.dart';
import 'package:partiu/features/home/data/repositories/event_repository.dart';
import 'package:partiu/screens/chat/services/event_application_removal_service.dart';
import 'package:partiu/screens/chat/services/event_deletion_service.dart';
import 'package:partiu/shared/services/toast_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Controller para a tela de informações do grupo/evento
class GroupInfoController extends ChangeNotifier {
  GroupInfoController({required this.eventId}) {
    _init();
  }

  final String eventId;
  final EventRepository _eventRepository = EventRepository();
  final EventApplicationRepository _applicationRepository = EventApplicationRepository();

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _eventData;
  List<Map<String, dynamic>> _participants = [];
  bool _isMuted = false;

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
  List<String> get participantUserIds => _participants
      .map((p) => p['userId'] as String)
      .toList();
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

  Future<void> _init() async {
    await _loadEventData();
    await _loadParticipants();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadEventData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();

      if (!doc.exists) {
        _error = 'Event not found';
        return;
      }

      _eventData = doc.data();
    } catch (e) {
      _error = 'Failed to load event: $e';
      debugPrint('❌ Error loading event: $e');
    }
  }

  Future<void> _loadParticipants() async {
    try {
      debugPrint('🔍 Buscando participantes para evento: $eventId');
      
      // Busca aplicações aprovadas do evento (approved + autoApproved)
      final snapshot = await FirebaseFirestore.instance
          .collection('EventApplications')
          .where('eventId', isEqualTo: eventId)
          .where('status', whereIn: ['approved', 'autoApproved'])
          .get();

      debugPrint('📋 Encontradas ${snapshot.docs.length} aplicações aprovadas');

      // Criar lista com dados de aplicação incluindo timestamp para ordenação
      final participantsWithTimestamp = snapshot.docs.map((doc) {
        final data = doc.data();
        final appliedAt = (data['appliedAt'] as Timestamp?)?.toDate();
        
        debugPrint('  - userId: ${data['userId']}, status: ${data['status']}, appliedAt: $appliedAt');
        
        return {
          'userId': data['userId'] as String,
          'applicationId': doc.id,
          'appliedAt': appliedAt,
        };
      }).toList();
      
      // Ordenar por data de aplicação (do mais antigo para o mais recente)
      participantsWithTimestamp.sort((a, b) {
        final aTime = a['appliedAt'] as DateTime? ?? DateTime.now();
        final bTime = b['appliedAt'] as DateTime? ?? DateTime.now();
        return aTime.compareTo(bTime);
      });

      // Remover timestamp da lista final
      _participants = participantsWithTimestamp.map((p) => {
        'userId': p['userId'] as String,
        'applicationId': p['applicationId'] as String,
      }).toList();
      
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
    await _init();
  }

  void toggleMute(bool value) {
    _isMuted = value;
    notifyListeners();
    // TODO: Salvar preferência no Firestore
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
          context: context,
          title: i18n.translate('success'),
          subtitle: i18n.translate('event_name_updated'),
        );
      }
    } catch (e) {
      await progressDialog.hide();
      debugPrint('❌ Error updating event name: $e');

      if (context.mounted) {
        ToastService.showError(
          context: context,
          title: i18n.translate('error'),
          subtitle: i18n.translate('failed_to_update_event_name'),
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
              context.go(AppRoutes.home);
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
              context.go(AppRoutes.home);
            }
          });
        }
      },
    );
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
}
