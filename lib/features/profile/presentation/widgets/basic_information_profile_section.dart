import 'package:flutter/material.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/shared/widgets/basic_information_section.dart';

/// Seção de informações básicas independente
/// 
/// - Espaçamento inferior: 36px
/// - Padding horizontal: 20px
/// 
/// Auto-gerenciada:
/// - Carrega dados reativamente do UserStore
/// - Auto-oculta se não houver dados
/// - Exibe gender, jobTitle, city/state/country
class BasicInformationProfileSection extends StatelessWidget {

  const BasicInformationProfileSection({
    required this.userId, 
    super.key,
  });
  
  final String userId;

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    // Precisa acessar entry completa para gender e jobTitle
    final user = UserStore.instance.getUser(userId);
    if (user == null) return const SizedBox.shrink();

    final entries = _buildBasicInfoEntries(i18n, user: user);

    // 🎯 AUTO-OCULTA: Se não tem dados, não renderiza
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: GlimpseStyles.profileSectionPadding,
      child: BasicInformationSection(
        title: i18n.translate('basic_information_profile'),
        entries: entries,
      ),
    );
  }

  List<BasicInfoEntry> _buildBasicInfoEntries(
    AppLocalizations i18n, {
    required UserEntry user,
  }) {
    final entries = <BasicInfoEntry>[];

    // Idade
    if (user.age != null) {
      entries.add(BasicInfoEntry(
        label: _tr(i18n, 'age_label', fallback: 'Idade'),
        value: _formatYearsOld(i18n, user.age!),
      ));
    }

    // Gênero
    if (user.gender != null && user.gender!.trim().isNotEmpty) {
      entries.add(BasicInfoEntry(
        label: i18n.translate('gender_label'),
        value: _translateGender(i18n, user.gender!),
      ));
    }

    // Orientação Sexual
    if (user.sexualOrientation != null && user.sexualOrientation!.trim().isNotEmpty) {
      entries.add(BasicInfoEntry(
        label: _tr(i18n, 'sexual_orientation_label', fallback: 'Orientação'),
        value: _translateSexualOrientation(i18n, user.sexualOrientation!),
      ));
    }

    // Profissão/Job Title
    if (user.jobTitle != null && user.jobTitle!.trim().isNotEmpty) {
      entries.add(BasicInfoEntry(
        label: i18n.translate('job_title_label'),
        value: user.jobTitle!,
      ));
    }

    // País de origem (from) - DESABILITADO
    // TODO: Reativar quando necessário
    // if (user.from != null && user.from!.trim().isNotEmpty) {
    //   entries.add(BasicInfoEntry(
    //     label: i18n.translate('from_label'),
    //     value: user.from!,
    //   ));
    // }

    return entries;
  }

  String _formatYearsOld(AppLocalizations i18n, int age) {
    final template = i18n.translate('years_old');
    if (template.trim().isEmpty) return '$age anos';
    return template.replaceAll('{age}', '$age');
  }

  String _tr(AppLocalizations i18n, String key, {required String fallback}) {
    final translated = i18n.translate(key);
    return translated.trim().isNotEmpty ? translated : fallback;
  }

  /// Traduz valor de gênero do banco (inglês) para o idioma atual
  String _translateGender(AppLocalizations i18n, String gender) {
    switch (gender) {
      case 'Male':
        return i18n.translate('gender_male');
      case 'Female':
        return i18n.translate('gender_female');
      case 'Other':
        return i18n.translate('gender_non_binary');
      default:
        return gender; // Retorna o valor original se não encontrar tradução
    }
  }

  /// Traduz valor de orientação sexual do banco (português) para o idioma atual
  String _translateSexualOrientation(AppLocalizations i18n, String orientation) {
    switch (orientation) {
      case 'Heterossexual':
        return i18n.translate('sexual_orientation_heterosexual');
      case 'Homossexual':
        return i18n.translate('sexual_orientation_homosexual');
      case 'Bissexual':
        return i18n.translate('sexual_orientation_bisexual');
      case 'Outro':
        return i18n.translate('sexual_orientation_other');
      case 'Prefiro não informar':
        return i18n.translate('sexual_orientation_prefer_not_to_say');
      default:
        return orientation; // Retorna o valor original se não encontrar tradução
    }
  }
}
