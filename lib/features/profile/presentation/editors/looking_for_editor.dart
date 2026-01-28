import 'package:flutter/material.dart';
import 'package:partiu/features/auth/presentation/widgets/looking_for_selector_widget.dart';

/// Editor reutilizável de "O que busco" para Edit Profile
/// Usa o mesmo widget do signup wizard
class LookingForEditor extends StatefulWidget {
  const LookingForEditor({
    required this.controller,
    super.key,
  });

  final TextEditingController controller;

  @override
  State<LookingForEditor> createState() => _LookingForEditorState();
}

class _LookingForEditorState extends State<LookingForEditor> {
  @override
  Widget build(BuildContext context) {
    return LookingForSelectorWidget(
      initialSelection: widget.controller.text,
      onSelectionChanged: (value) {
        widget.controller.text = value ?? '';
      },
    );
  }
}
