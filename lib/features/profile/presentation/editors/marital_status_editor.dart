import 'package:flutter/material.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/shared/widgets/glimpse_dropdown.dart';

/// Editor de estado civil para Edit Profile
/// Usa GlimpseDropdown com opções pré-definidas
class MaritalStatusEditor extends StatefulWidget {
  const MaritalStatusEditor({
    required this.controller,
    super.key,
  });

  final TextEditingController controller;

  @override
  State<MaritalStatusEditor> createState() => _MaritalStatusEditorState();
}

class _MaritalStatusEditorState extends State<MaritalStatusEditor> {
  static const List<String> _keys = <String>[
    'single',
    'dating',
    'married',
    'divorced',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // nothing to do
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return GlimpseDropdown(
      labelText: '',
      hintText: i18n.translate('placeholder_marital_status'),
      items: _keys,
      selectedValue: widget.controller.text.isEmpty ? null : widget.controller.text,
      itemBuilder: (key) => i18n.translate('marital_status_${key.toLowerCase()}'),
      onChanged: (value) {
        setState(() {
          widget.controller.text = value ?? '';
        });
      },
    );
  }
}
