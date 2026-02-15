import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget de bio/descrição pessoal
/// Extraído para reutilização no wizard
class BioWidget extends StatefulWidget {
  const BioWidget({
    required this.initialBio,
    required this.onBioChanged,
    super.key,
  });

  final String initialBio;
  final ValueChanged<String> onBioChanged;

  @override
  State<BioWidget> createState() => _BioWidgetState();
}

class _BioWidgetState extends State<BioWidget> {
  late TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _bioController = TextEditingController(text: widget.initialBio);
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return GlimpseTextField(
      labelText: i18n.translate('bio_label'),
      hintText: i18n.translate('bio_placeholder'),
      controller: _bioController,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onBioChanged,
      maxLines: 5,
      maxLength: 500,
      labelStyle: GlimpseStyles.fieldLabelStyle(
        color: Theme.of(context).textTheme.titleMedium?.color,
      ).copyWith(fontSize: 14.sp),
    );
  }
}
