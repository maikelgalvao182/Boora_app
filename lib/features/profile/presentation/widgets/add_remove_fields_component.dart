import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

/// Componente para adicionar/remover campos de texto com validação de máximo
/// Cada campo é exibido com ícone de check verde e botão de remoção
class AddRemoveFieldsComponent extends StatefulWidget {

  const AddRemoveFieldsComponent({
    required this.items, required this.hintText, required this.onChanged, super.key,
    this.maxItems = 4,
    this.labelStyle,
    this.maxLines = 1,
    this.accentColor,
  });
  final List<String> items;
  final int maxItems;
  final String hintText;
  final ValueChanged<List<String>> onChanged;
  final TextStyle? labelStyle;
  final int? maxLines;
  final Color? accentColor;

  @override
  State<AddRemoveFieldsComponent> createState() => _AddRemoveFieldsComponentState();
}

class _AddRemoveFieldsComponentState extends State<AddRemoveFieldsComponent> {
  late List<TextEditingController> _controllers;
  late List<String> _currentItems;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.items);
    _controllers = _currentItems.map((item) => TextEditingController(text: item)).toList();
    
    // Adiciona listeners para atualizar em tempo real
    for (final controller in _controllers) {
      controller.addListener(_notifyChange);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _notifyChange() {
    final items = _controllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    widget.onChanged(items);
  }

  void _addField() {
    if (_controllers.length < widget.maxItems) {
      setState(() {
        final controller = TextEditingController();
        controller.addListener(_notifyChange);
        _controllers.add(controller);
      });
    }
  }

  void _removeField(int index) {
    if (_controllers.isNotEmpty) {
      setState(() {
        _controllers[index].dispose();
        _controllers.removeAt(index);
        _notifyChange();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lista de campos existentes
          ..._controllers.asMap().entries.map((entry) {
            final index = entry.key;
            final controller = entry.value;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FieldItem(
                controller: controller,
                hintText: widget.hintText,
                onRemove: () => _removeField(index),
                maxLines: widget.maxLines,
              ),
            );
          }),

        // Botão de adicionar novo campo
        if (_controllers.length < widget.maxItems)
          GestureDetector(
            onTap: _addField,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GlimpseColors.borderColorLight.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Iconsax.add,
                    size: 18,
                    color: widget.accentColor ?? Colors.black,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add item',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: widget.accentColor ?? Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Indicador de limite
          if (_controllers.length >= widget.maxItems)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                AppLocalizations.of(context).translate('max_items_reached').replaceAll('{count}', '${widget.maxItems}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.accentColor ?? Colors.grey[500],
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Item individual com botão de remoção
class _FieldItem extends StatelessWidget {

  const _FieldItem({
    required this.controller,
    required this.hintText,
    required this.onRemove,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onRemove;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    // Para maxLines > 1, usa altura dinâmica, senão 56px fixo
    final isMultiline = maxLines != null && maxLines! > 1;
    
    return Container(
      height: isMultiline ? null : 56, // Altura padrão 56px para linha única
      constraints: isMultiline ? const BoxConstraints(minHeight: 56) : null,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GlimpseColors.borderColorLight.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        children: [
          // Campo de texto
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.sentences,
              maxLines: maxLines,
              maxLength: 34, // Limite de 34 caracteres
              textAlignVertical: isMultiline ? TextAlignVertical.top : TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: GlimpseColors.textSubTitle,
                  fontWeight: FontWeight.w300,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: isMultiline 
                    ? const EdgeInsets.symmetric(vertical: 16)
                    : EdgeInsets.zero,
                counterText: '', // Remove o contador visual
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Botão de remover
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(
                  Iconsax.close_circle,
                  color: Colors.red,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
