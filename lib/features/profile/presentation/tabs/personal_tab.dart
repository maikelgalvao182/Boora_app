import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/utils/date_formatter_helper.dart';
import 'package:partiu/features/profile/presentation/widgets/field_preview_card.dart';
import 'package:partiu/features/profile/presentation/models/personal_field_type.dart';
import 'package:partiu/features/profile/presentation/screens/personal_field_editor_screen.dart';
import 'package:flutter/cupertino.dart';

class PersonalTab extends StatelessWidget {

  const PersonalTab({
    required this.fullnameController,
    required this.jobController,
    required this.bioController,
    required this.genderController,
    required this.sexualOrientationController,
    required this.lookingForController,
    required this.maritalStatusController,
    required this.birthDayController,
    required this.birthMonthController,
    required this.birthYearController,
    required this.localityController,
    required this.countryController,
    required this.languagesController,
    required this.instagramController,
    required this.validateBio,
    required this.validateJob,
    required this.labelStyle,
    required this.bioLabel,
    required this.bioHint,
    required this.jobLabel,
    required this.jobHint,
    super.key,
    this.brideMode = false,
  });
  final TextEditingController fullnameController;
  final TextEditingController jobController;
  final TextEditingController bioController;
  final TextEditingController genderController;
  final TextEditingController sexualOrientationController;
  final TextEditingController lookingForController;
  final TextEditingController maritalStatusController;
  final TextEditingController birthDayController;
  final TextEditingController birthMonthController;
  final TextEditingController birthYearController;
  final TextEditingController localityController;
  final TextEditingController countryController;
  final TextEditingController languagesController;
  final TextEditingController instagramController;
  final String? Function(String?) validateBio;
  final String? Function(String?) validateJob;
  final TextStyle labelStyle;
  final String bioLabel;
  final String bioHint;
  final String jobLabel;
  final String jobHint;
  // Bride mode: show only Full name, Bio, Gender, Birth date, Phone, Email, Locality
  final bool brideMode;

  /// Navega para o editor de campo específico
  void _openFieldEditor(
    BuildContext context,
    PersonalFieldType fieldType,
  ) {
    final controllers = {
      'fullname': fullnameController,
      'job': jobController,
      'bio': bioController,
      'gender': genderController,
      'sexualOrientation': sexualOrientationController,
      'lookingFor': lookingForController,
      'maritalStatus': maritalStatusController,
      'birthDay': birthDayController,
      'birthMonth': birthMonthController,
      'birthYear': birthYearController,
      'locality': localityController,
      'country': countryController,
      'languages': languagesController,
      'instagram': instagramController,
    };

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => PersonalFieldEditorScreen(
          fieldType: fieldType,
          controllers: controllers,
          validateBio: validateBio,
          bioHint: bioHint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Full Name
        FieldPreviewCard(
          fieldType: PersonalFieldType.fullName,
          preview: fullnameController.text,
          onTap: () => _openFieldEditor(context, PersonalFieldType.fullName),
        ),

        // Vendor-only fields
        if (!brideMode) ...[
          // Job Title
          FieldPreviewCard(
            fieldType: PersonalFieldType.jobTitle,
            preview: _buildJobTitlePreview(context),
            onTap: () => _openFieldEditor(context, PersonalFieldType.jobTitle),
          ),
        ],

        // Bio
        FieldPreviewCard(
          fieldType: PersonalFieldType.bio,
          preview: bioController.text,
          onTap: () => _openFieldEditor(context, PersonalFieldType.bio),
        ),

        // Gender
        FieldPreviewCard(
          fieldType: PersonalFieldType.gender,
          preview: _formatGenderPreview(context),
          onTap: () => _openFieldEditor(context, PersonalFieldType.gender),
        ),

        // Sexual Orientation
        FieldPreviewCard(
          fieldType: PersonalFieldType.sexualOrientation,
          preview: sexualOrientationController.text.isEmpty 
              ? 'Não informado' 
              : sexualOrientationController.text,
          onTap: () => _openFieldEditor(context, PersonalFieldType.sexualOrientation),
        ),

        // Looking For
        FieldPreviewCard(
          fieldType: PersonalFieldType.lookingFor,
          preview: _formatLookingForPreview(context),
          onTap: () => _openFieldEditor(context, PersonalFieldType.lookingFor),
        ),

        // Marital Status
        FieldPreviewCard(
          fieldType: PersonalFieldType.maritalStatus,
          preview: _formatMaritalStatusPreview(context),
          onTap: () => _openFieldEditor(context, PersonalFieldType.maritalStatus),
        ),

        // Birth Date (Read-only - não pode ser alterado)
        ValueListenableBuilder(
          valueListenable: birthDayController,
          builder: (context, dayValue, _) {
            return ValueListenableBuilder(
              valueListenable: birthMonthController,
              builder: (context, monthValue, _) {
                return ValueListenableBuilder(
                  valueListenable: birthYearController,
                  builder: (context, yearValue, _) {
                    return FieldPreviewCard(
                      fieldType: PersonalFieldType.birthDate,
                      preview: _formatBirthDatePreview(context),
                      onTap: () {}, // Bloqueado - sem ação
                      isDisabled: true, // Campo desabilitado
                    );
                  },
                );
              },
            );
          },
        ),

        // Locality (Read-only - atualizado automaticamente pelo LocationBackgroundUpdater)
        FieldPreviewCard(
          fieldType: PersonalFieldType.locality,
          preview: localityController.text,
          onTap: () {}, // Read-only - sem ação
        ),

        // Origem (from) - read-only
        FieldPreviewCard(
          fieldType: PersonalFieldType.from,
          preview: countryController.text,
          onTap: () {}, // Read-only - sem ação
          isDisabled: true,
        ),

        // Languages
        FieldPreviewCard(
          fieldType: PersonalFieldType.languages,
          preview: _formatLanguagesPreview(context),
          onTap: () => _openFieldEditor(context, PersonalFieldType.languages),
        ),

        // Instagram
        FieldPreviewCard(
          fieldType: PersonalFieldType.instagram,
          preview: instagramController.text,
          onTap: () => _openFieldEditor(context, PersonalFieldType.instagram),
        ),
      ],
    );
  }

  String _buildJobTitlePreview(BuildContext context) {
    if (jobController.text.isEmpty) return '';
    return jobController.text;
  }

  String _formatGenderPreview(BuildContext context) {
    final genderValue = genderController.text.trim();
    final i18n = AppLocalizations.of(context);
    
    // Se for 'not_specified' ou valores não especificados, retorna string vazia para mostrar "Adicionar"
    if (genderValue.isEmpty || 
        genderValue == 'not_specified' ||
        genderValue == i18n.translate('not_specified_with_space')) {
      return '';
    }
    
    // Para outros valores, usa tradução se necessário
    switch (genderValue) {
      case 'Male':
        return i18n.translate('male');
      case 'Female':
        return i18n.translate('female');
      case 'Other':
        return i18n.translate('other');
      default:
        return genderValue; // Valor personalizado
    }
  }

  String _formatBirthDatePreview(BuildContext context) {
    final day = birthDayController.text.trim();
    final month = birthMonthController.text.trim();
    final year = birthYearController.text.trim();
    
    if (day.isEmpty && month.isEmpty && year.isEmpty) return '';
    
    final dayInt = int.tryParse(day);
    final monthInt = int.tryParse(month);
    final yearInt = int.tryParse(year);
    
    if (dayInt == null || monthInt == null || yearInt == null) return '';
    
    final date = DateTime(yearInt, monthInt, dayInt);
    final i18n = AppLocalizations.of(context);
    return DateFormatterHelper.formatBirthday(date, i18n.locale.toString());
  }

  String _formatLanguagesPreview(BuildContext context) {
    final text = languagesController.text.trim();
    if (text.isEmpty) return '';
    
    final i18n = AppLocalizations.of(context);
    final languages = text.split(',').map((lang) => lang.trim()).where((lang) => lang.isNotEmpty).toList();
    
    if (languages.isEmpty) return '';
    
    // Traduz cada idioma
    final translatedLanguages = languages.map((lang) {
      final key = 'language_${lang.toLowerCase()}';
      return i18n.translate(key);
    }).toList();
    
    // Retorna lista com vírgulas
    return translatedLanguages.join(', ');
  }

  String _formatLookingForPreview(BuildContext context) {
    final text = lookingForController.text.trim();
    if (text.isEmpty) return '';
    
    final i18n = AppLocalizations.of(context);
    final options = text.split(',').map((opt) => opt.trim()).where((opt) => opt.isNotEmpty).toList();
    
    if (options.isEmpty) return '';
    
    // Traduz cada opção (friendship, networking, serious_relationship, casual)
    final translatedOptions = options.map((opt) {
      final key = 'looking_for_${opt.toLowerCase()}';
      return i18n.translate(key);
    }).toList();
    
    // Retorna lista com vírgulas
    return translatedOptions.join(', ');
  }

  String _formatMaritalStatusPreview(BuildContext context) {
    final text = maritalStatusController.text.trim();
    if (text.isEmpty) return '';
    
    final i18n = AppLocalizations.of(context);
    // Traduz o status (single, dating, married, divorced)
    final key = 'marital_status_${text.toLowerCase()}';
    return i18n.translate(key);
  }
}

