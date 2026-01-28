import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/profile/presentation/models/personal_field_type.dart';
import 'package:partiu/features/profile/presentation/models/social_field_type.dart';
import 'package:partiu/features/profile/presentation/models/midia_field_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

/// Widget que exibe um card de preview de campo no formato Instagram/TikTok
/// Mostra label à esquerda e preview do valor à direita
/// 
/// 🎯 Widget "burro": Apenas exibe dados, delega navegação via callback
/// Aceita qualquer enum que tenha titleKey e isRequired via extension
/// 
/// ⚠️ Campo "from" (país): Bloqueado para edição se já preenchido
class FieldPreviewCard extends StatelessWidget {
  const FieldPreviewCard({
    required this.fieldType,
    required this.preview,
    required this.onTap,
    super.key,
    this.isComplete = false,
    this.isDisabled = false,
  });

  final dynamic fieldType; // PersonalFieldType, SocialFieldType ou MidiaFieldType
  final String preview;
  final VoidCallback onTap;
  final bool isComplete;
  final bool isDisabled;

  /// Helper para obter title de forma polimórfica
  String _getTitle(BuildContext context) {
    if (fieldType is PersonalFieldType) {
      return (fieldType as PersonalFieldType).title(context);
    } else if (fieldType is SocialFieldType) {
      return (fieldType as SocialFieldType).title;
    } else if (fieldType is MidiaFieldType) {
      return (fieldType as MidiaFieldType).title;
    }
    throw UnsupportedError('Unsupported field type: ${fieldType.runtimeType}');
  }

  /// Helper para obter isRequired de forma polimórfica
  bool _getIsRequired() {
    if (fieldType is PersonalFieldType) {
      return (fieldType as PersonalFieldType).isRequired;
    } else if (fieldType is SocialFieldType) {
      return false; // Social fields are optional
    } else if (fieldType is MidiaFieldType) {
      return false; // Midia fields are optional
    }
    throw UnsupportedError('Unsupported field type: ${fieldType.runtimeType}');
  }

  /// Helper para obter a largura da coluna de label baseada no tipo
  double _getLabelColumnWidth() {
    if (fieldType is PersonalFieldType) {
      return 170.0;
    } else if (fieldType is SocialFieldType) {
      return 170.0;
    } else if (fieldType is MidiaFieldType) {
      return 100.0;
    }
    return 140.0; // fallback
  }

  /// Helper para obter texto de "adicionar" baseado no tipo
  String _getAddText(BuildContext context) {
    if (fieldType is PersonalFieldType) {
      return (fieldType as PersonalFieldType).addText(context);
    }

    final i18n = AppLocalizations.of(context);
    return i18n.translate('add');
  }

  String _formatPreview(BuildContext context) {
    if (preview.trim().isEmpty) return '';

    if (fieldType is! PersonalFieldType) return preview;

    final i18n = AppLocalizations.of(context);
    final personalFieldType = fieldType as PersonalFieldType;

    switch (personalFieldType) {
      case PersonalFieldType.lookingFor:
        final options = preview
            .split(',')
            .map((opt) => opt.trim())
            .where((opt) => opt.isNotEmpty)
            .toList();
        if (options.isEmpty) return preview;

        final translated = options.map((opt) {
          final key = 'looking_for_${opt.toLowerCase()}';
          final value = i18n.translate(key);
          return value.trim().isNotEmpty && value != key ? value : opt;
        }).toList();

        return translated.join(', ');

      case PersonalFieldType.maritalStatus:
        final key = 'marital_status_${preview.toLowerCase()}';
        final value = i18n.translate(key);
        return value.trim().isNotEmpty && value != key ? value : preview;

      case PersonalFieldType.fullName:
      case PersonalFieldType.bio:
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
        return preview;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Desativar da UI os campos: Nascimento, Localização e Origem
    if (fieldType is PersonalFieldType) {
      if (fieldType == PersonalFieldType.birthDate ||
          fieldType == PersonalFieldType.locality ||
          fieldType == PersonalFieldType.from) {
        return const SizedBox.shrink();
      }
    }

    final i18n = AppLocalizations.of(context);
    final label = _getTitle(context);
    final formattedPreview = _formatPreview(context);
    
    // Campo "from" bloqueado se já preenchido
    final isFromFieldLocked = fieldType is PersonalFieldType && 
        fieldType == PersonalFieldType.from && 
        preview.isNotEmpty;
    
    final effectivelyDisabled = isDisabled || isFromFieldLocked;

    return InkWell(
      onTap: effectivelyDisabled ? null : () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label à esquerda com largura fixa
            SizedBox(
              width: _getLabelColumnWidth(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_getIsRequired()) ...[
                    const SizedBox(width: 2),
                    Text(
                      i18n.translate('required_field_marker'),
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Preview à direita com expansão
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      formattedPreview.isEmpty ? _getAddText(context) : formattedPreview,
                      style: TextStyle(
                        fontSize: 14,
                        color: effectivelyDisabled
                          ? const Color(0xFF999999)
                          : (formattedPreview.isEmpty 
                            ? const Color(0xFF999999)
                            : Colors.black),
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!effectivelyDisabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Iconsax.arrow_right_3,
                        color: const Color(0xFFCCCCCC),
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}