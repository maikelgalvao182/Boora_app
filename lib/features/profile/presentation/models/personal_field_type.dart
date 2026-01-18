import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';

/// Tipos de campos disponíveis na tab Personal do EditProfile
enum PersonalFieldType {
  fullName,
  bio,
  jobTitle,
  school,
  gender,
  sexualOrientation,
  birthDate,
  locality,
  state,
  from,
  languages,
  instagram,
}

extension PersonalFieldTypeExtension on PersonalFieldType {
  /// Título do campo para exibição na UI
  String title(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    switch (this) {
      case PersonalFieldType.fullName:
        return i18n.translate('field_full_name');
      case PersonalFieldType.bio:
        return i18n.translate('field_bio');
      case PersonalFieldType.jobTitle:
        return i18n.translate('field_job_title');
      case PersonalFieldType.school:
        return i18n.translate('field_school');
      case PersonalFieldType.gender:
        return i18n.translate('field_gender');
      case PersonalFieldType.sexualOrientation:
        return 'Orientação Sexual';
      case PersonalFieldType.birthDate:
        return i18n.translate('field_birth_date');
      case PersonalFieldType.locality:
        return i18n.translate('field_locality');
      case PersonalFieldType.state:
        return i18n.translate('field_state');
      case PersonalFieldType.from:
        return i18n.translate('field_from');
      case PersonalFieldType.languages:
        return i18n.translate('field_languages');
      case PersonalFieldType.instagram:
        return i18n.translate('field_instagram');
    }
  }

  /// Placeholder/hint do campo
  String placeholder(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    switch (this) {
      case PersonalFieldType.fullName:
        return i18n.translate('placeholder_full_name');
      case PersonalFieldType.bio:
        return i18n.translate('placeholder_bio');
      case PersonalFieldType.jobTitle:
        return i18n.translate('placeholder_job_title');
      case PersonalFieldType.school:
        return i18n.translate('placeholder_school');
      case PersonalFieldType.gender:
        return i18n.translate('placeholder_gender');
      case PersonalFieldType.sexualOrientation:
        return 'Selecione sua orientação sexual';
      case PersonalFieldType.birthDate:
        return i18n.translate('placeholder_birth_date');
      case PersonalFieldType.locality:
        return i18n.translate('placeholder_locality');
      case PersonalFieldType.state:
        return i18n.translate('placeholder_state');
      case PersonalFieldType.from:
        return i18n.translate('placeholder_from');
      case PersonalFieldType.languages:
        return i18n.translate('placeholder_languages');
      case PersonalFieldType.instagram:
        return i18n.translate('placeholder_instagram');
    }
  }

  /// Texto de adicionar quando o campo está vazio
  String addText(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    switch (this) {
      case PersonalFieldType.fullName:
        return i18n.translate('add_full_name');
      case PersonalFieldType.bio:
        return i18n.translate('add_bio');
      case PersonalFieldType.jobTitle:
        return i18n.translate('add_job_title');
      case PersonalFieldType.school:
        return i18n.translate('add_school');
      case PersonalFieldType.gender:
        return i18n.translate('add_gender');
      case PersonalFieldType.sexualOrientation:
        return 'Adicionar orientação sexual';
      case PersonalFieldType.birthDate:
        return i18n.translate('add_birth_date');
      case PersonalFieldType.locality:
        return i18n.translate('add_locality');
      case PersonalFieldType.state:
        return i18n.translate('add_state');
      case PersonalFieldType.from:
        return i18n.translate('add_from');
      case PersonalFieldType.languages:
        return i18n.translate('add_languages');
      case PersonalFieldType.instagram:
        return i18n.translate('add_instagram');
    }
  }

  /// Se o campo é obrigatório
  bool get isRequired {
    switch (this) {
      case PersonalFieldType.bio:
        return true;
      case PersonalFieldType.fullName:
      case PersonalFieldType.jobTitle:
      case PersonalFieldType.school:
      case PersonalFieldType.gender:
      case PersonalFieldType.sexualOrientation:
      case PersonalFieldType.birthDate:
      case PersonalFieldType.locality:
      case PersonalFieldType.state:
      case PersonalFieldType.from:
      case PersonalFieldType.languages:
      case PersonalFieldType.instagram:
        return false;
    }
  }
}