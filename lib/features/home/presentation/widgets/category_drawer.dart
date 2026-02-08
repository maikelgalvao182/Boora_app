import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/features/home/create_flow/create_flow_coordinator.dart';
import 'package:partiu/features/home/presentation/widgets/category/activity_category.dart';
import 'package:partiu/features/home/presentation/widgets/category/category_selector.dart';
import 'package:partiu/features/home/presentation/widgets/schedule_drawer.dart';
import 'package:partiu/shared/widgets/glimpse_back_button.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/navigation_buttons.dart';

/// Bottom sheet para seleção de categoria da atividade
class CategoryDrawer extends StatefulWidget {
  const CategoryDrawer({
    super.key,
    this.coordinator,
    this.initialCategory,
    this.editMode = false,
  });

  final CreateFlowCoordinator? coordinator;
  final ActivityCategory? initialCategory;
  final bool editMode;

  @override
  State<CategoryDrawer> createState() => _CategoryDrawerState();
}

class _CategoryDrawerState extends State<CategoryDrawer> {
  ActivityCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    // Preencher com valor do coordinator (se existir) ou valor inicial
    _selectedCategory = widget.initialCategory ?? widget.coordinator?.draft.category;
  }

  bool get _canContinue => _selectedCategory != null;

  void _handleContinue() async {
    if (!_canContinue) return;

    // Se estiver em modo de edição, apenas retornar o valor
    if (widget.editMode) {
      Navigator.of(context).pop({
        'category': categoryToString(_selectedCategory!),
      });
      return;
    }

    // Salvar dados no coordinator
    if (widget.coordinator != null) {
      widget.coordinator!.setCategory(_selectedCategory!);
    }

    // Abre o drawer de agendamento
    final scheduleResult = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleDrawer(
        coordinator: widget.coordinator,
      ),
    );

    if (scheduleResult != null && mounted) {
      // Retornar resultado para que discover_tab gerencie o LocationPicker
      Navigator.of(context).pop({
        'schedule': scheduleResult,
        'action': 'openLocationPicker',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(24.r),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle e header (fixo)
          Padding(
            padding: EdgeInsets.only(
              top: 12.h,
              left: 20.w,
              right: 20.w,
            ),
            child: Column(
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: GlimpseColors.borderColorLight,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),

                SizedBox(height: 16.h),

                // Header: Título + Close
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Título alinhado à esquerda
                    Text(
                      AppLocalizations.of(context).translate('category_drawer_title'),
                      style: GoogleFonts.getFont(
                        FONT_PLUS_JAKARTA_SANS,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        color: GlimpseColors.primaryColorLight,
                      ),
                    ),

                    // Botão fechar
                    GlimpseCloseButton(
                      size: 32.w,
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 24.h),

          // Grid de categorias (scrollável)
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: CategorySelector(
                selectedCategory: _selectedCategory,
                onCategorySelected: (category) {
                  setState(() {
                    _selectedCategory = category;
                  });
                },
              ),
            ),
          ),

          SizedBox(height: 24.h),

          // Botões de navegação (fixo)
          NavigationButtons(
            onBack: () => Navigator.of(context).pop({'action': 'back'}),
            onContinue: _handleContinue,
            canContinue: _canContinue,
          ),

          // Padding bottom para safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16.h),
        ],
      ),
    );
  }
}
