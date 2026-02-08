import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

/// Campo de texto estilo Glimpse para ser reutilizado em todas as telas
class GlimpseTextField extends StatefulWidget {

  const GlimpseTextField({
    required this.hintText, super.key,
    this.labelText,
  this.labelStyle,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.focusNode,
    this.validator,
    this.textInputAction,
    this.onEditingComplete,
    this.icon,
  this.readOnly = false,
  this.onTap,
  this.inputFormatters,
  @Deprecated('Use textCapitalization instead') this.capitalizeFirstLetter = false,
  this.textCapitalization = TextCapitalization.none,
  this.resizable = false,
  this.minResizeHeight = 120,
  this.maxResizeHeight = 500,
  });
  final String hintText;
  final String? labelText;
  final TextStyle? labelStyle;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final void Function(String)? onChanged;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool enabled;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final void Function()? onEditingComplete;
  final IconData? icon;
  final bool readOnly;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final bool capitalizeFirstLetter; // Deprecated - use textCapitalization instead
  final TextCapitalization textCapitalization;
  final bool resizable;
  final double minResizeHeight;
  final double maxResizeHeight;

  @override
  State<GlimpseTextField> createState() => _GlimpseTextFieldState();
}

class _GlimpseTextFieldState extends State<GlimpseTextField> {
  late FocusNode _internalFocusNode;
  String? _errorText;
  double? _currentHeight;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(_onFocusChange);
    if (widget.resizable) {
      _currentHeight = widget.minResizeHeight;
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    } else {
      _internalFocusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    // Trigger rebuild when focus changes (for border color, etc.)
    setState(() {});
  }
  
  String? _validate(String? value) {
    final error = widget.validator?.call(value);
    setState(() {
      _errorText = error;
    });
    return error;
  }
  
  @override
  Widget build(BuildContext context) {
    // Determina se é uma área de texto (múltiplas linhas)
    // Se maxLines for null (ilimitado) ou > 1, é considerado text area
    final isTextArea = widget.maxLines == null || (widget.maxLines != null && widget.maxLines! > 1);
    // Border radius unificado com dropdown de Job Title
    const borderRadius = 12.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Exibe o label se fornecido
        if (widget.labelText != null) ...[  
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Text(
              widget.labelText!,
              style: widget.labelStyle ?? GlimpseStyles.fieldLabelStyle(
                color: GlimpseColors.primaryColorLight,
              ),
            ),
          ),
        ],
        
        // Campo de texto com altura dinâmica
        // ✅ RepaintBoundary isola rebuilds do TextField
        RepaintBoundary(
          child: Stack(
            children: [
              Container(
                height: _currentHeight,
                constraints: BoxConstraints(
                  minHeight: _currentHeight ?? (isTextArea ? 120.h : 56.h),
                  maxHeight: _currentHeight ?? (isTextArea ? double.infinity : 56.h),
                ),
                decoration: BoxDecoration(
                  color: GlimpseColors.lightTextField,
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: widget.resizable
                      ? ClipRect(
                          child: Align(
                            alignment: Alignment.topLeft,
                            widthFactor: 1.0,
                            child: TextFormField(
                              controller: widget.controller,
                              obscureText: widget.obscureText,
                              keyboardType: widget.keyboardType,
                              textCapitalization: widget.capitalizeFirstLetter
                                  ? TextCapitalization.sentences
                                  : widget.textCapitalization,
                              inputFormatters: widget.inputFormatters,
                              onChanged: widget.onChanged,
                              maxLines: null,
                              minLines: null,
                              maxLength: widget.maxLength,
                              enabled: widget.enabled,
                              focusNode: _internalFocusNode,
                              readOnly: widget.readOnly,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onTap?.call();
                              },
                              textInputAction: widget.textInputAction,
                              onEditingComplete: widget.onEditingComplete,
                              validator: _validate,
                              textAlignVertical: TextAlignVertical.center,
                              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                                color: GlimpseColors.primaryColorLight,
                                fontWeight: FontWeight.w400,
                                fontSize: 16.sp,
                                height: 1.4,
                              ),
                              decoration: InputDecoration(
                                hintText: widget.hintText,
                                hintStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                                  color: GlimpseColors.textSubTitle,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14.sp,
                                  height: 1.4,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                prefixIcon: widget.prefixIcon,
                                suffixIcon: widget.suffixIcon,
                                counterText: '',
                                errorStyle: const TextStyle(height: 0, fontSize: 0),
                                errorMaxLines: 1,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 16.h),
                              ),
                            ),
                          ),
                        )
                      : TextFormField(
                          controller: widget.controller,
                          obscureText: widget.obscureText,
                          keyboardType: widget.keyboardType,
                          textCapitalization: widget.capitalizeFirstLetter
                              ? TextCapitalization.sentences
                              : widget.textCapitalization,
                          inputFormatters: widget.inputFormatters,
                          onChanged: widget.onChanged,
                          maxLines: widget.maxLines,
                          minLines: widget.minLines,
                          maxLength: widget.maxLength,
                          enabled: widget.enabled,
                          focusNode: _internalFocusNode,
                          readOnly: widget.readOnly,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onTap?.call();
                          },
                          textInputAction: widget.textInputAction,
                          onEditingComplete: widget.onEditingComplete,
                          validator: _validate,
                          textAlignVertical: TextAlignVertical.center,
                          style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                            color: GlimpseColors.primaryColorLight,
                            fontWeight: FontWeight.w400,
                            fontSize: 14.sp,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            hintStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                              color: GlimpseColors.textSubTitle,
                              fontWeight: FontWeight.w400,
                              fontSize: 14.sp,
                              height: 1.4,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            prefixIcon: widget.prefixIcon,
                            suffixIcon: widget.suffixIcon,
                            counterText: '',
                            errorStyle: const TextStyle(height: 0, fontSize: 0),
                            errorMaxLines: 1,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 16.h),
                          ),
                        ),
                ),
              ),
              if (widget.resizable)
                Positioned(
                  bottom: 4.h,
                  right: 4.w,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        final newHeight = (_currentHeight ?? widget.minResizeHeight) + details.delta.dy;
                        if (newHeight < widget.minResizeHeight) {
                          _currentHeight = widget.minResizeHeight;
                        } else if (newHeight > widget.maxResizeHeight) {
                          _currentHeight = widget.maxResizeHeight;
                        } else {
                          _currentHeight = newHeight;
                        }
                      });
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: Container(
                        width: 24.w,
                        height: 24.h,
                        color: Colors.transparent,
                        child: CustomPaint(
                          painter: _ResizeHandlePainter(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ), // Fecha RepaintBoundary
        
        // [OK] Mensagem de erro FORA do input com padding top 6px e fonte 12px
        if (_errorText != null && _errorText!.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: 6.h, left: 4.w),
            child: Text(
              _errorText!,
              style: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
                color: Colors.red,
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2.w
      ..strokeCap = StrokeCap.round;

    // Draw diagonal lines
    // Line 1 (smallest)
    canvas.drawLine(
      Offset(size.width - 6, size.height - 2),
      Offset(size.width - 2, size.height - 6),
      paint,
    );
    
    // Line 2 (medium)
    canvas.drawLine(
      Offset(size.width - 10, size.height - 2),
      Offset(size.width - 2, size.height - 10),
      paint,
    );
    
    // Line 3 (largest)
    canvas.drawLine(
      Offset(size.width - 14, size.height - 2),
      Offset(size.width - 2, size.height - 14),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
