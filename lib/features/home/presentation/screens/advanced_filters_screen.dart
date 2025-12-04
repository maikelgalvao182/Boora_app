import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/glimpse_close_button.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/filters/radius_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/age_range_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/gender_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/interests_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/verified_filter_widget.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/services/location/radius_controller.dart';
import 'package:partiu/services/location/location_query_service.dart';

/// Advanced Filters Screen (filtros avançados para descoberta de atividades)
class AdvancedFiltersScreen extends StatefulWidget {
  const AdvancedFiltersScreen({super.key});

  @override
  State<AdvancedFiltersScreen> createState() => _AdvancedFiltersScreenState();
}

class _AdvancedFiltersScreenState extends State<AdvancedFiltersScreen> {
  // Controllers
  late final RadiusController _radiusController;
  
  // Filtros
  String? _selectedGender = 'all';
  RangeValues _ageRange = const RangeValues(18, 100);
  bool _isVerified = false;
  Set<String> _selectedInterests = {};
  
  // User data
  String? _currentUserId;
  List<String> _userInterests = [];

  @override
  void initState() {
    super.initState();
    _radiusController = RadiusController();
    _loadUserInterests();
  }
  
  void _loadUserInterests() {
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_currentUserId != null) {
      final interestsNotifier = UserStore.instance.getInterestsNotifier(_currentUserId!);
      interestsNotifier.addListener(_onInterestsChanged);
      _onInterestsChanged(); // Load initial value
    }
  }
  
  void _onInterestsChanged() {
    if (_currentUserId != null) {
      final interestsNotifier = UserStore.instance.getInterestsNotifier(_currentUserId!);
      setState(() {
        _userInterests = interestsNotifier.value ?? [];
      });
    }
  }

  @override
  void dispose() {
    // Remove listener dos interesses
    if (_currentUserId != null) {
      final interestsNotifier = UserStore.instance.getInterestsNotifier(_currentUserId!);
      interestsNotifier.removeListener(_onInterestsChanged);
    }
    // Não fazer dispose do controller - ele é singleton
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return HeroMode(
      enabled: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(i18n),
        body: Column(
          children: [
            Expanded(
              child: _buildBody(i18n),
            ),
            _buildApplyButton(i18n),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(AppLocalizations i18n) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      automaticallyImplyLeading: false,
      title: Text(
        i18n.translate('advanced_filters'),
        style: GoogleFonts.getFont(
          FONT_PLUS_JAKARTA_SANS,
          fontWeight: FontWeight.w700,
          color: GlimpseColors.primaryColorLight,
          fontSize: 18,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GlimpseCloseButton(
            color: GlimpseColors.primaryColorLight,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AppLocalizations i18n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadiusFilterWidget(controller: _radiusController),
          const SizedBox(height: 20),
          
          AgeRangeFilterWidget(
            ageRange: _ageRange,
            onChanged: (values) => setState(() => _ageRange = values),
          ),
          const SizedBox(height: 20),
          
          GenderFilterWidget(
            selectedGender: _selectedGender,
            onChanged: (value) => setState(() => _selectedGender = value),
          ),
          const SizedBox(height: 20),
          
          InterestsFilterWidget(
            selectedInterests: _selectedInterests,
            onChanged: (interests) => setState(() => _selectedInterests = interests),
            availableInterests: _userInterests,
            showCount: false,
          ),
          const SizedBox(height: 20),
          
          VerifiedFilterWidget(
            isVerified: _isVerified,
            onChanged: (value) => setState(() => _isVerified = value),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildApplyButton(AppLocalizations i18n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      color: Colors.white,
      child: SafeArea(
        child: GlimpseButton(
          text: i18n.translate('apply_filters'),
          height: 55,
          onTap: _applyFilters,
        ),
      ),
    );
  }

  void _applyFilters() {
    // 1. Criar objeto de filtros unificado
    final filters = EventFilterOptions(
      gender: _selectedGender,
      minAge: _ageRange.start.round(),
      maxAge: _ageRange.end.round(),
      isVerified: _isVerified,
      interests: _selectedInterests.toList(),
    );

    // 2. Atualizar serviço orquestrador (LocationQueryService)
    // Isso dispara o fluxo: Bounding Box -> Fetch Creators -> Filter -> Isolate
    LocationQueryService().updateFilters(filters);
    
    // 3. Salvar raio imediatamente
    _radiusController.saveImmediately();
    
    // 4. Fechar
    Navigator.pop(context, true);
  }
}
