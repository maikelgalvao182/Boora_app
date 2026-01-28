import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/widgets/edit_profile_app_bar.dart';
import 'package:partiu/features/profile/presentation/editors/bio_editor.dart';
import 'package:partiu/features/profile/presentation/editors/full_name_editor.dart';
import 'package:partiu/features/profile/presentation/editors/gender_editor.dart';
import 'package:partiu/features/profile/presentation/editors/job_title_editor.dart';
import 'package:partiu/features/profile/presentation/editors/birth_date_widget.dart';
import 'package:partiu/features/profile/presentation/editors/languages_editor.dart';
import 'package:partiu/features/profile/presentation/editors/social/instagram_editor.dart';
import 'package:partiu/features/profile/presentation/editors/sexual_orientation_editor.dart';
import 'package:partiu/features/profile/presentation/editors/looking_for_editor.dart';
import 'package:partiu/features/profile/presentation/editors/marital_status_editor.dart';
import 'package:partiu/features/profile/presentation/models/personal_field_type.dart';
import 'package:flutter/material.dart';

/// Tela genérica de edição de campo pessoal no formato Instagram/TikTok
/// Header com botões "Cancelar" e "Salvar", corpo com o editor específico
class PersonalFieldEditorScreen extends StatefulWidget {
  const PersonalFieldEditorScreen({
    required this.fieldType,
    required this.controllers,
    this.validateSchool,
    this.validateBio,
    this.bioHint,
    super.key,
  });

  final PersonalFieldType fieldType;
  final Map<String, TextEditingController> controllers;
  final String? Function(String?)? validateSchool;
  final String? Function(String?)? validateBio;
  final String? bioHint;

  @override
  State<PersonalFieldEditorScreen> createState() => _PersonalFieldEditorScreenState();
}

class _PersonalFieldEditorScreenState extends State<PersonalFieldEditorScreen> {
  bool _isFieldValid = true;
  DateTime? _selectedBirthDate;

  @override
  void initState() {
    super.initState();
    _initializeBirthDate();
    _validateField();
    _addListeners();
  }

  void _initializeBirthDate() {
    // Inicializa data de nascimento a partir dos controllers
    final day = int.tryParse(widget.controllers['birthDay']!.text.trim());
    final month = int.tryParse(widget.controllers['birthMonth']!.text.trim());
    final year = int.tryParse(widget.controllers['birthYear']!.text.trim());
    
    if (day != null && month != null && year != null) {
      try {
        _selectedBirthDate = DateTime(year, month, day);
      } catch (e) {
        _selectedBirthDate = null;
      }
    }
  }

  @override
  void dispose() {
    _removeListeners();
    super.dispose();
  }

  void _addListeners() {
    switch (widget.fieldType) {
      case PersonalFieldType.fullName:
        widget.controllers['fullname']!.addListener(_validateField);
        break;
      case PersonalFieldType.jobTitle:
        widget.controllers['job']!.addListener(_validateField);
        break;
      case PersonalFieldType.school:
        widget.controllers['school']!.addListener(_validateField);
        break;
      case PersonalFieldType.bio:
        widget.controllers['bio']!.addListener(_validateField);
        break;
      case PersonalFieldType.gender:
        widget.controllers['gender']!.addListener(_validateField);
        break;
      case PersonalFieldType.sexualOrientation:
        widget.controllers['sexualOrientation']!.addListener(_validateField);
        break;
      case PersonalFieldType.lookingFor:
      case PersonalFieldType.maritalStatus:
        // Campos opcionais
        break;
      case PersonalFieldType.birthDate:
        // BirthDateEditor usa callback direto, não precisa de listeners
        break;
      case PersonalFieldType.locality:
        widget.controllers['locality']!.addListener(_validateField);
        break;
      case PersonalFieldType.state:
      case PersonalFieldType.from:
      case PersonalFieldType.languages:
      case PersonalFieldType.instagram:
        // State, from, languages e instagram são opcionais, não precisam de listeners de validação
        break;
    }
  }

  void _removeListeners() {
    switch (widget.fieldType) {
      case PersonalFieldType.fullName:
        widget.controllers['fullname']!.removeListener(_validateField);
        break;
      case PersonalFieldType.jobTitle:
        widget.controllers['job']!.removeListener(_validateField);
        break;
      case PersonalFieldType.school:
        widget.controllers['school']!.removeListener(_validateField);
        break;
      case PersonalFieldType.bio:
        widget.controllers['bio']!.removeListener(_validateField);
        break;
      case PersonalFieldType.gender:
        widget.controllers['gender']!.removeListener(_validateField);
        break;
      case PersonalFieldType.sexualOrientation:
        widget.controllers['sexualOrientation']!.removeListener(_validateField);
        break;
      case PersonalFieldType.lookingFor:
      case PersonalFieldType.maritalStatus:
        // Campos opcionais
        break;
      case PersonalFieldType.birthDate:
        // BirthDateEditor usa callback direto, não precisa remover listeners
        break;
      case PersonalFieldType.locality:
        widget.controllers['locality']!.removeListener(_validateField);
        break;
      case PersonalFieldType.state:
      case PersonalFieldType.from:
      case PersonalFieldType.languages:
      case PersonalFieldType.instagram:
        // State, from, languages e instagram são opcionais, não precisam remover listeners
        break;
    }
  }

  void _validateField() {
    bool isValid = true;

    switch (widget.fieldType) {
      case PersonalFieldType.fullName:
        isValid = widget.controllers['fullname']!.text.trim().isNotEmpty;
        break;
      case PersonalFieldType.bio:
        isValid = widget.controllers['bio']!.text.trim().isNotEmpty;
        break;
      case PersonalFieldType.gender:
        isValid = widget.controllers['gender']!.text.trim().isNotEmpty;
        break;
      case PersonalFieldType.sexualOrientation:
        isValid = widget.controllers['sexualOrientation']!.text.trim().isNotEmpty;
        break;
      case PersonalFieldType.birthDate:
        isValid = _selectedBirthDate != null;
        break;
      // Campos não obrigatórios sempre válidos
      case PersonalFieldType.jobTitle:
      case PersonalFieldType.school:
      case PersonalFieldType.lookingFor:
      case PersonalFieldType.maritalStatus:
      case PersonalFieldType.locality:
      case PersonalFieldType.state:
      case PersonalFieldType.from:
      case PersonalFieldType.languages:
      case PersonalFieldType.instagram:
        isValid = true;
        break;
    }

    if (_isFieldValid != isValid) {
      setState(() {
        _isFieldValid = isValid;
      });
    }
  }

  /// Sincroniza controllers de data de nascimento quando muda
  void _syncBirthDateControllers() {
    if (_selectedBirthDate != null) {
      widget.controllers['birthDay']!.text = _selectedBirthDate!.day.toString();
      widget.controllers['birthMonth']!.text = _selectedBirthDate!.month.toString();
      widget.controllers['birthYear']!.text = _selectedBirthDate!.year.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Sincroniza controllers de data antes de sair
          _syncBirthDateControllers();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: EditProfileAppBar(
          onBack: () {
            _syncBirthDateControllers();
            Navigator.of(context).pop();
          },
          title: localizations.translate('edit_profile'),
          onSave: null,
          isSaving: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildEditor(context),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    switch (widget.fieldType) {
      case PersonalFieldType.fullName:
        return FullNameEditor(
          controller: widget.controllers['fullname']!,
        );

      case PersonalFieldType.jobTitle:
        return JobTitleEditor(
          controller: widget.controllers['job']!,
        );

      case PersonalFieldType.school:
        return JobTitleEditor(
          controller: widget.controllers['school']!,
        );

      case PersonalFieldType.bio:
        return BioEditor(
          controller: widget.controllers['bio']!,
          validator: widget.validateBio,
          hintText: widget.bioHint ?? '',
        );

      case PersonalFieldType.gender:
        return GenderEditor(
          controller: widget.controllers['gender']!,
        );

      case PersonalFieldType.sexualOrientation:
        return SexualOrientationEditor(
          controller: widget.controllers['sexualOrientation']!,
        );

      case PersonalFieldType.lookingFor:
        return LookingForEditor(
          controller: widget.controllers['lookingFor']!,
        );

      case PersonalFieldType.maritalStatus:
        return MaritalStatusEditor(
          controller: widget.controllers['maritalStatus']!,
        );

      case PersonalFieldType.birthDate:
        return BirthDateWidget(
          initialDate: _selectedBirthDate,
          onDateChanged: (DateTime? date) {
            setState(() {
              _selectedBirthDate = date;
              _validateField();
            });
          },
        );

      case PersonalFieldType.locality:
      case PersonalFieldType.state:
      case PersonalFieldType.from:
        // Locality, state e from são read-only
        // Locality/State atualizados automaticamente pelo LocationBackgroundUpdater
        // From é definido no signup e não pode ser editado posteriormente
        return const SizedBox.shrink();

      case PersonalFieldType.languages:
        return LanguagesEditor(
          controller: widget.controllers['languages']!,
        );

      case PersonalFieldType.instagram:
        return InstagramEditor(
          controller: widget.controllers['instagram']!,
        );
    }
  }
}