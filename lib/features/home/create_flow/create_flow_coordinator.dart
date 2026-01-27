import 'package:flutter/foundation.dart';
import 'package:partiu/features/home/create_flow/activity_draft.dart';
import 'package:partiu/features/home/data/repositories/event_map_repository.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/plugins/locationpicker/entities/location_result.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/category/activity_category.dart';

/// Coordenador do fluxo de criação de atividade
/// Gerencia o estado do rascunho conforme o usuário navega pelos drawers
class CreateFlowCoordinator extends ChangeNotifier {
  final ActivityDraft _draft = ActivityDraft();
  final MapViewModel? mapViewModel;

  CreateFlowCoordinator({this.mapViewModel});

  /// Getter para o rascunho atual
  ActivityDraft get draft => _draft;

  /// Define as informações básicas da atividade
  void setActivityInfo(String activityText, String emoji) {
    _draft.activityText = activityText;
    _draft.emoji = emoji;
    notifyListeners();
    debugPrint('📝 [CreateFlow] Activity info set: $activityText ($emoji)');
  }

  /// Define a categoria da atividade
  void setCategory(ActivityCategory category) {
    _draft.category = category;
    notifyListeners();
    debugPrint('🏷️ [CreateFlow] Category set: $category');
  }

  /// Define a localização selecionada
  /// [photoReferences] deve conter URLs reais do Google Places, não photo_reference
  void setLocation(LocationResult location, {List<String>? photoReferences}) {
    _draft.location = location;
    _draft.photoReferences = photoReferences;
    notifyListeners();
    debugPrint('📍 [CreateFlow] Location set: ${location.formattedAddress}');
  }

  /// Define a data e horário
  void setSchedule({
    required DateTime date,
    required TimeType timeType,
    DateTime? time,
  }) {
    _draft.selectedDate = date;
    _draft.timeType = timeType;
    
    // Combinar data selecionada + horário selecionado
    if (time != null && timeType == TimeType.specific) {
      _draft.selectedTime = DateTime(
        date.year,
        date.month, 
        date.day,
        time.hour,
        time.minute,
      );
    } else {
      _draft.selectedTime = null;
    }
    
    notifyListeners();
    debugPrint('📅 [CreateFlow] Schedule set: $date ($timeType)');
    if (_draft.selectedTime != null) {
      debugPrint('🕒 [CreateFlow] Combined datetime: ${_draft.selectedTime}');
    }
  }

  /// Define as configurações de participantes
  void setParticipants({
    required int minAge,
    required int maxAge,
    required PrivacyType privacyType,
    int? maxParticipants,
    String? gender,
  }) {
    _draft.minAge = minAge;
    _draft.maxAge = maxAge;
    _draft.privacyType = privacyType;
    _draft.maxParticipants = maxParticipants;
    _draft.gender = gender;
    notifyListeners();
    debugPrint('👥 [CreateFlow] Participants set: $minAge-$maxAge ($privacyType) gender: $gender max: $maxParticipants');
  }

  /// Verifica se o draft está pronto para ser salvo
  bool get canSave => _draft.isComplete && _draft.hasValidTime;

  /// Limpa o rascunho (usado após salvar ou cancelar)
  void clearDraft() {
    _draft.clear();
    notifyListeners();
    debugPrint('🗑️ [CreateFlow] Draft cleared');
  }

  /// Retorna um resumo do draft para debug
  String get summary {
    if (!_draft.isComplete) {
      return 'Draft incompleto';
    }

    final buffer = StringBuffer();
    buffer.writeln('📋 Activity Draft Summary:');
    buffer.writeln('  • Activity: ${_draft.activityText} ${_draft.emoji}');
    buffer.writeln('  • Category: ${_draft.category}');
    buffer.writeln('  • Location: ${_draft.location?.formattedAddress}');
    buffer.writeln('  • Date: ${_draft.selectedDate}');
    buffer.writeln('  • Time Type: ${_draft.timeType}');
    if (_draft.selectedTime != null) {
      buffer.writeln('  • Time: ${_draft.selectedTime}');
    }
    buffer.writeln('  • Age Range: ${_draft.minAge}-${_draft.maxAge}');
    buffer.writeln('  • Privacy: ${_draft.privacyType}');
    if (_draft.maxParticipants != null) {
      buffer.writeln('  • Max Participants: ${_draft.maxParticipants == 0 ? "Aberto" : _draft.maxParticipants}');
    }
    
    return buffer.toString();
  }

  /// Injeta o evento recém-criado diretamente no ViewModel do mapa
  /// Isso garante que a navegação funcione imediatamente, mesmo se o evento
  /// estiver fora do raio de busca ou ainda não indexado.
  Future<void> loadDraftEventIntoViewModel(String eventId) async {
    try {
      if (mapViewModel == null) {
        return;
      }
      
      // Buscar evento completo no repositório
      final event = await EventMapRepository().getEventById(eventId);

      if (event != null) {
        // Inserir manualmente na lista de eventos do ViewModel
        await mapViewModel!.injectEvent(event);
      }
    } catch (e) {
      // Ignorar erro de injeção
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
