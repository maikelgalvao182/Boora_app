import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:partiu/core/services/app_initializer_service.dart';
import 'package:partiu/features/home/presentation/screens/home_screen_refactored.dart';
import 'package:partiu/features/home/presentation/viewmodels/map_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/people_ranking_viewmodel.dart';
import 'package:partiu/features/home/presentation/viewmodels/ranking_viewmodel.dart';
import 'package:partiu/features/conversations/state/conversations_viewmodel.dart';
import 'package:partiu/features/home/presentation/screens/find_people/find_people_controller.dart';
import 'package:provider/provider.dart';

/// Tela de Splash que carrega todos os dados do mapa antes de entrar no app
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    
    // Precache IMEDIATO - Fire and Forget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheImages();
    });
  }

  void _precacheImages() {
    try {
      precacheImage(const AssetImage('assets/images/capa.jpg'), context);
      precacheImage(const AssetImage('assets/images/logo.png'), context);
    } catch (e) {
      debugPrint('Erro no precache: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 120,
          height: 120,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
