import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/shared/widgets/glimpse_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget de profissão/cargo
/// Extraído para reutilização no wizard
class JobTitleWidget extends StatefulWidget {
  const JobTitleWidget({
    required this.initialJobTitle,
    required this.onJobTitleChanged,
    super.key,
  });

  final String initialJobTitle;
  final ValueChanged<String> onJobTitleChanged;

  @override
  State<JobTitleWidget> createState() => _JobTitleWidgetState();
}

class _JobTitleWidgetState extends State<JobTitleWidget> {
  late TextEditingController _jobTitleController;

  @override
  void initState() {
    super.initState();
    _jobTitleController = TextEditingController(text: widget.initialJobTitle);
  }

  @override
  void dispose() {
    _jobTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return GlimpseTextField(
      labelText: i18n.translate('job_title_label'),
      hintText: i18n.translate('job_title_placeholder'),
      controller: _jobTitleController,
      textCapitalization: TextCapitalization.words,
      onChanged: widget.onJobTitleChanged,
      labelStyle: GlimpseStyles.fieldLabelStyle(
        color: Theme.of(context).textTheme.titleMedium?.color,
      ).copyWith(fontSize: 14.sp),
    );
  }
}
