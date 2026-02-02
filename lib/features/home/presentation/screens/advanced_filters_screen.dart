import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/filters/radius_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/age_range_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/gender_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/interests_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/verified_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/sexual_orientation_filter_widget.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/services/location/radius_controller.dart';
import 'package:partiu/services/location/location_query_service.dart';
import 'package:partiu/services/location/advanced_filters_controller.dart';

/// Tela de Filtros Avançados para descoberta de PESSOAS
/// 
/// Permite filtrar usuários por:
/// - Raio de busca (km)
/// - Faixa etária
/// - Gênero
/// - Interesses
/// - Verificação
/// 
/// Utilizado em: find_people_screen.dart
class AdvancedFiltersScreen extends StatefulWidget {
  const AdvancedFiltersScreen({super.key});

  @override
  State<AdvancedFiltersScreen> createState() => _AdvancedFiltersScreenState();
}

class _AdvancedFiltersScreenState extends State<AdvancedFiltersScreen> {
  // Controllers
  late final RadiusController _radiusController;
  late final AdvancedFiltersController _filtersController;
  
  // Filtros (agora sincronizados com o controller)
  String? _selectedGender;
  String? _selectedSexualOrientation;
  RangeValues _ageRange = const RangeValues(MIN_AGE, MAX_AGE);
  bool _isVerified = false;
  Set<String> _selectedInterests = {};
  bool _isLoadingFilters = true;
  
  // User data
  String? _currentUserId;
  List<String> _userInterests = [];

  @override
  void initState() {
    super.initState();
    _radiusController = RadiusController();
    _filtersController = AdvancedFiltersController();
    
    // Carregar dados salvos
    _radiusController.loadFromFirestore();
    _filtersController.loadFromFirestore().then((_) {
      // Sincronizar apenas UMA VEZ após carregar
      if (mounted) {
        setState(() {
          _selectedGender = _filtersController.gender;
          _selectedSexualOrientation = _filtersController.sexualOrientation;
          _ageRange = RangeValues(
            _filtersController.minAge.toDouble(),
            _filtersController.maxAge.toDouble(),
          );
          _isVerified = _filtersController.isVerified;
          _selectedInterests = _filtersController.interests.toSet();
          _isLoadingFilters = false;
        });
      }
    });
    
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
    _filtersController.dispose();
    // Não fazer dispose do radiusController - ele é singleton
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildHeader(i18n),
          Flexible(
            child: _buildBody(i18n),
          ),
          _buildApplyButton(i18n),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations i18n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            i18n.translate('advanced_filters'),
            style: GoogleFonts.getFont(
              FONT_PLUS_JAKARTA_SANS,
              fontWeight: FontWeight.w700,
              color: GlimpseColors.primaryColorLight,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations i18n) {
    // Mostrar loading enquanto carrega os filtros do Firestore
    if (_isLoadingFilters) {
      return const Center(
        child: CupertinoActivityIndicator(),
      );
    }
    
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
            selectedGender: _selectedGender ?? 'all',
            onChanged: (value) => setState(() => _selectedGender = value),
          ),
          const SizedBox(height: 20),

          SexualOrientationFilterWidget(
            selectedOrientation: _selectedSexualOrientation,
            onChanged: (value) => setState(() => _selectedSexualOrientation = value),
          ),
          const SizedBox(height: 20),
          
          InterestsFilterWidget(
            selectedInterests: _selectedInterests,
            onChanged: (interests) async {
              // Detectar se foi adição ou remoção
              final added = interests.difference(_selectedInterests);
              final removed = _selectedInterests.difference(interests);
              
              setState(() => _selectedInterests = interests);
              
              // Salvar/remover imediatamente no Firestore
              if (added.isNotEmpty) {
                for (final interest in added) {
                  await _filtersController.addInterest(interest);
                }
              }
              if (removed.isNotEmpty) {
                for (final interest in removed) {
                  await _filtersController.removeInterest(interest);
                }
              }
            },
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
        child: Row(
          children: [
            // Botão Limpar
            Expanded(
              child: GlimpseButton(
                text: 'Limpar',
                backgroundColor: GlimpseColors.primaryLight,
                textColor: GlimpseColors.primary,
                onTap: _clearFilters,
              ),
            ),
            const SizedBox(width: 12),
            // Botão Aplicar Filtros
            Expanded(
              child: GlimpseButton(
                text: i18n.translate('apply_filters'),
                onTap: _applyFilters,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearFilters() async {
    // Limpar todos os filtros
    await _filtersController.clearAllFilters();
    
    // Limpar radiusKm também
    _radiusController.resetToDefault();
    await _radiusController.saveImmediately();
    
    // Resetar UI
    if (!mounted) return;
    setState(() {
      _selectedGender = 'all';
      _selectedSexualOrientation = 'all';
      _ageRange = const RangeValues(MIN_AGE, MAX_AGE);
      _isVerified = false;
      _selectedInterests = {};
    });
    
    // Limpar filtros no LocationQueryService (incluindo radiusKm)
    final filters = UserFilterOptions(
      gender: 'all',
      minAge: MIN_AGE.toInt(),
      maxAge: MAX_AGE.toInt(),
      isVerified: false,
      interests: [],
      radiusKm: _radiusController.radiusKm, // Raio resetado para default
    );
    
    LocationQueryService().updateFilters(filters);
    
    // Fechar
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _applyFilters() async {
    // 🔍 DEBUG: Verificar raio ANTES de salvar
    debugPrint('🔍 _applyFilters: radiusKm DO CONTROLLER = ${_radiusController.radiusKm}');
    
    // 1. Salvar raio imediatamente (Aguardar persistência antes de atualizar filtros)
    await _radiusController.saveImmediately();
    
    // 🔍 DEBUG: Verificar raio DEPOIS de salvar
    debugPrint('🔍 _applyFilters: radiusKm SALVO NO FIRESTORE');
    
    // 2. Atualizar filtros no controller (SEMPRE salvar, incluindo 'all')
    debugPrint('🔍 _applyFilters: Atualizando controller com:');
    debugPrint('   - gender: $_selectedGender (${_selectedGender.runtimeType})');
    debugPrint('   - ageRange: ${_ageRange.start.round()}-${_ageRange.end.round()} (start: ${_ageRange.start.runtimeType}, end: ${_ageRange.end.runtimeType})');
    debugPrint('   - verified: $_isVerified (${_isVerified.runtimeType})');
    
    // ✅ SEMPRE atualizar o controller com o valor selecionado (incluindo 'all')
    _filtersController.gender = _selectedGender ?? 'all';
    _filtersController.sexualOrientation = _selectedSexualOrientation ?? 'all';
    _filtersController.setAgeRange(
      _ageRange.start.round(),
      _ageRange.end.round(),
    );
    _filtersController.isVerified = _isVerified;
    
    debugPrint('🔍 _applyFilters: Valores no controller após atualização:');
    debugPrint('   - gender: ${_filtersController.gender}');
    debugPrint('   - minAge: ${_filtersController.minAge}');
    debugPrint('   - maxAge: ${_filtersController.maxAge}');
    debugPrint('   - isVerified: ${_filtersController.isVerified}');
    
    // 3. Salvar filtros no Firestore (incluindo 'all')
    await _filtersController.saveToFirestore();
    
    // 4. Criar objeto de filtros unificado (SEMPRE usar valor selecionado, incluindo 'all')
    final filters = UserFilterOptions(
      gender: _selectedGender ?? 'all', // ✅ Garantir que sempre passa o valor correto
      sexualOrientation: _selectedSexualOrientation ?? 'all',
      minAge: _ageRange.start.round(),
      maxAge: _ageRange.end.round(),
      isVerified: _isVerified,
      interests: _selectedInterests.toList(),
      radiusKm: _radiusController.radiusKm, // ✅ PASSAR RAIO NOS FILTROS
    );

    debugPrint('🔍 _applyFilters: Objeto filters criado com radiusKm = ${filters.radiusKm}');
    debugPrint('🔍 _applyFilters: gender final no filters = ${filters.gender}');

    // 5. Atualizar serviço de busca de pessoas (LocationQueryService)
    // NOTA: LocationQueryService busca USUÁRIOS (pessoas)
    // Estes filtros serão aplicados na tela de descoberta de pessoas (find_people_screen.dart)
    LocationQueryService().updateFilters(filters);
    
    // 6. Fechar
    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}
