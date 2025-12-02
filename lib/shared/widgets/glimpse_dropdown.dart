import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';

class GlimpseDropdown extends StatefulWidget {

  const GlimpseDropdown({
    required this.labelText, required this.hintText, required this.items, required this.onChanged, super.key,
    this.selectedValue,
    this.labelStyle,
    this.searchEnabled = false,
    this.suffixIconPath,
    this.enabled = true,
  });
  final String labelText;
  final String hintText;
  final List<String> items;
  final String? selectedValue;
  final void Function(String?) onChanged;
  final TextStyle? labelStyle;
  final bool searchEnabled;
  final String? suffixIconPath;
  final bool enabled;

  @override
  State<GlimpseDropdown> createState() => _GlimpseDropdownState();
}

class _GlimpseDropdownState extends State<GlimpseDropdown> {
  String? _selectedValue;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.selectedValue;
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = !widget.enabled;
    
    final borderColor = isDisabled
        ? GlimpseColors.borderColorLight.withValues(alpha: 0.5)
        : (_isOpen 
            ? GlimpseColors.primaryColorLight
            : GlimpseColors.borderColorLight);
    final backgroundColor = isDisabled
        ? GlimpseColors.lightTextField.withValues(alpha: 0.5)
        : GlimpseColors.lightTextField;
    final textColor = isDisabled
        ? GlimpseColors.textSubTitle.withValues(alpha: 0.4)
        : GlimpseColors.textSubTitle;
    final descriptionTextColor = isDisabled
        ? GlimpseColors.textSubTitle.withValues(alpha: 0.4)
        : GlimpseColors.textSubTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.labelText,
              style: widget.labelStyle ?? TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        IgnorePointer(
          ignoring: !widget.enabled,
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.6,
            child: widget.searchEnabled 
            ? CustomDropdown<String>.searchRequest(
                itemsListPadding: const EdgeInsets.only(top: 10),
                decoration: _buildDecoration(
                  backgroundColor, textColor, descriptionTextColor, borderColor
                ),
                futureRequest: _getFakeRequestData,
                hintText: widget.hintText,
                items: widget.items,
                onChanged: (value) {
                  setState(() {
                    _selectedValue = value;
                    _isOpen = false;
                  });
                  widget.onChanged(value);
                },
              )
            : CustomDropdown<String>(
                decoration: _buildDecoration(
                  backgroundColor, textColor, descriptionTextColor, borderColor
                ),
                hintText: widget.hintText,
                items: widget.items,
                initialItem: widget.items.contains(_selectedValue) ? _selectedValue : null,
                onChanged: (value) {
                  setState(() {
                    _selectedValue = value;
                    _isOpen = false;
                  });
                  widget.onChanged(value);
                },
              ),
          ),
        ),
      ],
    );
  }

  CustomDropdownDecoration _buildDecoration(
    Color backgroundColor, 
    Color textColor, 
    Color descriptionTextColor, 
    Color borderColor
  ) {
    return CustomDropdownDecoration(
      hintStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        color: descriptionTextColor,
        fontSize: 16,
        fontWeight: FontWeight.w300,
        height: 1,
      ),
      closedSuffixIcon: widget.suffixIconPath != null 
          ? SvgPicture.asset(
              widget.suffixIconPath!,
              colorFilter: ColorFilter.mode(
                textColor, 
                BlendMode.srcIn
              ),
            )
          : Icon(
              Icons.keyboard_arrow_down,
              color: textColor,
            ),
      expandedSuffixIcon: Icon(
        Icons.keyboard_arrow_up,
        color: textColor,
      ),
      expandedBorderRadius: BorderRadius.circular(12),
      expandedFillColor: backgroundColor,
      closedFillColor: backgroundColor,
      closedBorderRadius: BorderRadius.circular(12),
      listItemDecoration: ListItemDecoration(
        selectedColor: backgroundColor,
      ),
      headerStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1,
      ),
      listItemStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1,
      ),
      searchFieldDecoration: widget.searchEnabled ? SearchFieldDecoration(
        prefixIcon: Icon(
          CupertinoIcons.search,
          color: descriptionTextColor,
        ),
        suffixIcon: (onClear) {
          return Icon(Icons.close, color: descriptionTextColor);
        },
        hintStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
          color: descriptionTextColor,
          fontSize: 16,
          fontWeight: FontWeight.w300,
          height: 1,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        textStyle: GoogleFonts.getFont(FONT_PLUS_JAKARTA_SANS, 
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: borderColor,
          ),
        ),
      ) : null,
    );
  }

  Future<List<String>> _getFakeRequestData(String query) async {
    return Future.delayed(const Duration(milliseconds: 500), () {
      return widget.items.where((item) {
        return item.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }
}
