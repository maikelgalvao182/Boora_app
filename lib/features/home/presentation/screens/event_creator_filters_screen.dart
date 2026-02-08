import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/shared/widgets/glimpse_button.dart';
import 'package:partiu/shared/widgets/filters/age_range_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/gender_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/interests_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/verified_filter_widget.dart';
import 'package:partiu/shared/widgets/filters/sexual_orientation_filter_widget.dart';
import 'package:partiu/shared/stores/user_store.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/services/events/event_creator_filters_controller.dart';

/// Tela de Filtros Avançados para EVENTOS (por atributos do criador)
/// 
/// Permite filtrar eventos cujos criadores atendem aos critérios:
/// - Faixa etária do criador
/// - Gênero do criador
/// - Interesses do criador
/// - Verificação do criador
/// - Orientação sexual do criador
/// 
/// Utilizado em: discover_tab.dart
class EventCreatorFiltersScreen extends StatefulWidget {
  const EventCreatorFiltersScreen({super.key});

  /// Exibe a tela como modal bottom sheet
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return const EventCreatorFiltersScreen();
        },
      ),
    );
  }

  @override
  State<EventCreatorFiltersScreen> createState() =>
      _EventCreatorFiltersScreenState();
}

class _EventCreatorFiltersScreenState extends State<EventCreatorFiltersScreen> {
  // Controller singleton
  final _filtersController = EventCreatorFiltersController();

  // State local dos filtros (sincronizado com controller ao montar)
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

    _filtersController.loadFromFirestore().then((_) {
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
      final interestsNotifier =
          UserStore.instance.getInterestsNotifier(_currentUserId!);
      interestsNotifier.addListener(_onInterestsChanged);
      _onInterestsChanged();
    }
  }

  void _onInterestsChanged() {
    if (_currentUserId != null) {
      final interestsNotifier =
          UserStore.instance.getInterestsNotifier(_currentUserId!);
      setState(() {
        _userInterests = interestsNotifier.value ?? [];
      });
    }
  }

  @override
  void dispose() {
    if (_currentUserId != null) {
      final interestsNotifier =
          UserStore.instance.getInterestsNotifier(_currentUserId!);
      interestsNotifier.removeListener(_onInterestsChanged);
    }
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
          Expanded(
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
            i18n.translate('event_creator_filters_title'),
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
          AgeRangeFilterWidget(
            ageRange: _ageRange,
            onChanged: (values) => setState(() => _ageRange = values),
          ),
          const SizedBox(height: 20),

          GenderFilterWidget(
            selectedGender: _selectedGender ?? 'all',
            onChanged: (value) =>
                setState(() => _selectedGender = value),
          ),
          const SizedBox(height: 20),

          SexualOrientationFilterWidget(
            selectedOrientation: _selectedSexualOrientation,
            onChanged: (value) =>
                setState(() => _selectedSexualOrientation = value),
          ),
          const SizedBox(height: 20),

          InterestsFilterWidget(
            selectedInterests: _selectedInterests,
            onChanged: (interests) =>
                setState(() => _selectedInterests = interests),
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
                text: i18n.translate('clear'),
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
    _filtersController.resetFilters();
    await _filtersController.saveToFirestore();

    if (!mounted) return;
    setState(() {
      _selectedGender = 'all';
      _selectedSexualOrientation = 'all';
      _ageRange = const RangeValues(MIN_AGE, MAX_AGE);
      _isVerified = false;
      _selectedInterests = {};
    });

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _applyFilters() async {
    // Atualizar controller - auto-enable filters when applying
    _filtersController.filtersEnabled = true;
    _filtersController.gender = _selectedGender ?? 'all';
    _filtersController.sexualOrientation = _selectedSexualOrientation ?? 'all';
    _filtersController.setAgeRange(
      _ageRange.start.round(),
      _ageRange.end.round(),
    );
    _filtersController.isVerified = _isVerified;
    _filtersController.interests = _selectedInterests.toList();

    // Salvar no Firestore
    await _filtersController.saveToFirestore();

    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}
