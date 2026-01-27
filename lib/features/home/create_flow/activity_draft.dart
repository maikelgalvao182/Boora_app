import 'package:partiu/plugins/locationpicker/entities/location_result.dart';
import 'package:partiu/features/home/presentation/widgets/schedule/time_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/participants/privacy_type_selector.dart';
import 'package:partiu/features/home/presentation/widgets/category/activity_category.dart';

/// Rascunho da atividade durante o fluxo de criação
class ActivityDraft {
  // Informações básicas
  String? activityText;
  String? emoji;
  ActivityCategory? category;

  // Localização
  LocationResult? location;
  List<String>? photoReferences; // URLs reais do Google Places (não photo_reference)

  // Agendamento
  DateTime? selectedDate;
  TimeType? timeType;
  DateTime? selectedTime;

  // Participantes
  int? minAge;
  int? maxAge;
  PrivacyType? privacyType;
  int? maxParticipants; // 0 = Aberto, 1-20 = específico
  String? gender; // Gênero específico ou null para todos

  ActivityDraft({
    this.activityText,
    this.emoji,
    this.category,
    this.location,
    this.photoReferences,
    this.selectedDate,
    this.timeType,
    this.selectedTime,
    this.minAge,
    this.maxAge,
    this.privacyType,
    this.maxParticipants,
    this.gender,
  });

  /// Verifica se o rascunho está completo para ser salvo
  bool get isComplete =>
      activityText != null &&
      activityText!.trim().isNotEmpty &&
      emoji != null &&
      location != null &&
      location!.latLng != null &&
      selectedDate != null &&
      timeType != null &&
      minAge != null &&
      maxAge != null &&
      privacyType != null;

  /// Valida se o horário específico foi preenchido quando necessário
  bool get hasValidTime =>
      timeType == TimeType.flexible ||
      (timeType == TimeType.specific && selectedTime != null);

  /// Retorna uma cópia do draft
  ActivityDraft copyWith({
    String? activityText,
    String? emoji,
    ActivityCategory? category,
    LocationResult? location,
    List<String>? photoReferences,
    DateTime? selectedDate,
    TimeType? timeType,
    DateTime? selectedTime,
    int? minAge,
    int? maxAge,
    PrivacyType? privacyType,
    int? maxParticipants,
  }) {
    return ActivityDraft(
      activityText: activityText ?? this.activityText,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      location: location ?? this.location,
      photoReferences: photoReferences ?? this.photoReferences,
      selectedDate: selectedDate ?? this.selectedDate,
      timeType: timeType ?? this.timeType,
      selectedTime: selectedTime ?? this.selectedTime,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      privacyType: privacyType ?? this.privacyType,
      maxParticipants: maxParticipants ?? this.maxParticipants,
    );
  }

  /// Limpa o rascunho
  void clear() {
    activityText = null;
    emoji = null;
    category = null;
    location = null;
    photoReferences = null;
    selectedDate = null;
    timeType = null;
    selectedTime = null;
    minAge = null;
    maxAge = null;
    privacyType = null;
    maxParticipants = null;
    gender = null;
  }

  @override
  String toString() {
    return 'ActivityDraft('
        'activityText: $activityText, '
        'emoji: $emoji, '
        'category: $category, '
        'location: ${location?.formattedAddress}, '
        'date: $selectedDate, '
        'timeType: $timeType, '
        'privacyType: $privacyType'
        ')';
  }
}
