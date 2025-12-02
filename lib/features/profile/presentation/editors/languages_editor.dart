import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';

/// Editor para o campo "Languages" (múltipla seleção)
class LanguagesEditor extends StatefulWidget {
  const LanguagesEditor({
    required this.controller,
    super.key,
  });

  final TextEditingController controller;

  @override
  State<LanguagesEditor> createState() => _LanguagesEditorState();
}

class _LanguagesEditorState extends State<LanguagesEditor> {
  final List<String> _availableLanguages = [
    'Portuguese',
    'English',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Chinese',
    'Japanese',
    'Korean',
    'Arabic',
    'Russian',
    'Hindi',
    'Dutch',
    'Swedish',
    'Turkish',
  ];

  late Set<String> _selectedLanguages;

  @override
  void initState() {
    super.initState();
    _loadSelectedLanguages();
  }

  void _loadSelectedLanguages() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      _selectedLanguages = {};
    } else {
      _selectedLanguages = text.split(',').map((e) => e.trim()).toSet();
    }
  }

  void _saveSelectedLanguages() {
    widget.controller.text = _selectedLanguages.join(', ');
  }

  String _translateLanguage(BuildContext context, String language) {
    final i18n = AppLocalizations.of(context);
    final key = 'language_${language.toLowerCase()}';
    return i18n.translate(key);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.translate('field_languages'),
                style: GlimpseStyles.fieldLabelStyle(
                  color: Theme.of(context).textTheme.titleMedium?.color,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedLanguages.isEmpty)
                Text(
                  i18n.translate('placeholder_languages'),
                  style: const TextStyle(
                    color: GlimpseColors.textSubTitle,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedLanguages.map((lang) {
                    return Container(
                      decoration: BoxDecoration(
                        color: GlimpseColors.primaryLight,
                        border: Border.all(
                          color: GlimpseColors.primary,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _translateLanguage(context, lang),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedLanguages.remove(lang);
                                _saveSelectedLanguages();
                              });
                            },
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                i18n.translate('select_languages'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ..._availableLanguages.map((lang) {
                final isSelected = _selectedLanguages.contains(lang);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (isSelected) {
                        _selectedLanguages.remove(lang);
                      } else {
                        _selectedLanguages.add(lang);
                      }
                      _saveSelectedLanguages();
                    });
                  },
                  title: Text(_translateLanguage(context, lang)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: GlimpseColors.primary,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
