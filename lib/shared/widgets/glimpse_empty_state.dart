import 'package:partiu/shared/widgets/no_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget compartilhado para empty states em toda a aplicação
/// Encapsula as configurações padrão de svgName, fontSize e svgSize
/// que são repetidas em múltiplas telas
class GlimpseEmptyState extends StatefulWidget {

  const GlimpseEmptyState({
    required this.text, super.key,
    this.svgName = 'empty',
    this.fontSize,
    this.svgSize,
  });

  /// Factory para empty state padrão (mais comum) - usa 'empty' icon
  factory GlimpseEmptyState.standard({
    required String text,
  }) {
    return GlimpseEmptyState(
      text: text,
    );
  }

  /// Factory para empty state alternativo - usa 'empty3' icon
  /// Usado em conversas, notificações e visitas de perfil
  factory GlimpseEmptyState.conversations({
    required String text,
  }) {
    return GlimpseEmptyState(
      text: text,
      svgName: 'empty3',
    );
  }

  /// Factory para empty state de anúncios - usa 'empty2' icon
  /// Usado na tela de anúncios de casamento
  factory GlimpseEmptyState.announcements({
    required String text,
  }) {
    return GlimpseEmptyState(
      text: text,
      svgName: 'empty2',
    );
  }

  factory GlimpseEmptyState.large({
    required String text,
  }) {
    return GlimpseEmptyState(
      text: text,
      svgSize: 140,
    );
  }
  final String text;
  final String svgName;
  final double? fontSize;
  final double? svgSize;

  @override
  State<GlimpseEmptyState> createState() => _GlimpseEmptyStateState();
}

class _GlimpseEmptyStateState extends State<GlimpseEmptyState> {
  late Future<void> _loadingFuture;

  @override
  void initState() {
    super.initState();
    _loadingFuture = _loadResources();
  }

  Future<void> _loadResources() async {
    final isIcon = widget.svgName.endsWith('_icon');
    final path = isIcon
        ? 'assets/icons/${widget.svgName}.svg'
        : 'assets/svg/${widget.svgName}.svg';
    
    // Carrega o SVG e aguarda um pequeno delay para garantir sincronia
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 50)),
      rootBundle.loadString(path).catchError((_) => ''),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Garante que SVG e texto apareçam juntos usando FutureBuilder
    return FutureBuilder<void>(
      future: _loadingFuture,
      builder: (context, snapshot) {
        // Mostra espaço vazio durante o carregamento para evitar flash
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return NoData(
          svgName: widget.svgName,
          text: widget.text,
          fontSize: widget.fontSize ?? 14.sp,
          svgSize: widget.svgSize ?? 120.w,
        );
      },
    );
  }
}
