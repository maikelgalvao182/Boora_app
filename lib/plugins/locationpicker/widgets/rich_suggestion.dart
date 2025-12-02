import 'package:partiu/plugins/locationpicker/place_picker.dart';
import 'package:flutter/material.dart';

class RichSuggestion extends StatelessWidget {

  const RichSuggestion(this.autoCompleteItem, this.onTap, {super.key});
  final VoidCallback onTap;
  final AutoCompleteItem autoCompleteItem;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: RichText(text: TextSpan(children: getStyledTexts(context))),
        ),
      ),
    );
  }

  List<TextSpan> getStyledTexts(BuildContext context) {
    final result = <TextSpan>[];
    const style = TextStyle(color: Colors.grey, fontSize: 15);

    final startText =
        autoCompleteItem.text?.substring(0, autoCompleteItem.offset);
    if (startText?.isNotEmpty ?? false) {
      result.add(TextSpan(text: startText, style: style));
    }

    final boldText = autoCompleteItem.text?.substring(autoCompleteItem.offset!,
        autoCompleteItem.offset! + autoCompleteItem.length!);
    result.add(
      TextSpan(
          text: boldText,
          style: style.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color)),
    );

    final remainingText = autoCompleteItem.text
        ?.substring(autoCompleteItem.offset! + autoCompleteItem.length!);
    result.add(TextSpan(text: remainingText, style: style));

    return result;
  }
}
