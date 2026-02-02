import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsAndPrivacyLinks extends StatefulWidget {
  const TermsAndPrivacyLinks({
    super.key,
    this.prefixText,
    this.suffixText,
    this.trailingSpan,
    this.termsTextKey,
    this.privacyTextKey,
    this.textAlign = TextAlign.center,
    this.baseStyle,
    this.linkStyle,
  });

  final String? prefixText;
  final String? suffixText;
  final InlineSpan? trailingSpan;
  final String? termsTextKey;
  final String? privacyTextKey;
  final TextAlign textAlign;
  final TextStyle? baseStyle;
  final TextStyle? linkStyle;

  @override
  State<TermsAndPrivacyLinks> createState() => _TermsAndPrivacyLinksState();
}

class _TermsAndPrivacyLinksState extends State<TermsAndPrivacyLinks> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchUrl(BOORA_TERMS_OF_SERVICE_URL);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchUrl(BOORA_PRIVACY_POLICY_URL);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final baseStyle = widget.baseStyle ??
        const TextStyle(
          fontFamily: FONT_PLUS_JAKARTA_SANS,
          fontSize: 12,
          color: Colors.black87,
        );
    final linkStyle = widget.linkStyle ??
        baseStyle.copyWith(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        );

    return Text.rich(
      textAlign: widget.textAlign,
      TextSpan(
        style: baseStyle,
        children: [
          if (widget.prefixText != null)
            TextSpan(text: widget.prefixText),
          TextSpan(
            text: i18n.translate(widget.termsTextKey ?? 'terms'),
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          TextSpan(text: i18n.translate('and_separator')),
          TextSpan(
            text: i18n.translate(widget.privacyTextKey ?? 'privacy'),
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
          if (widget.suffixText != null)
            TextSpan(text: widget.suffixText),
          if (widget.trailingSpan != null) widget.trailingSpan!,
        ],
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
