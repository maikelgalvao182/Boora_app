import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

/// Helper para funcionalidades gerais do app
class AppHelper {
  
  /// Verifica e solicita permissão de localização
  Future<void> checkLocationPermission({
    required VoidCallback onGpsDisabled,
    required VoidCallback onDenied,
    required VoidCallback onGranted,
  }) async {
    if (!(await Geolocator.isLocationServiceEnabled())) {
      onGpsDisabled();
      return Future.value();
    } else {
      /// Obtém status da permissão
      var permission = await Geolocator.checkPermission();

      // Estado inicial no Android e iOS
      if (permission == LocationPermission.denied) {
        /// Solicita permissão
        permission = await Geolocator.requestPermission();
        // Verifica o resultado
        if (permission == LocationPermission.denied) {
          onDenied();
          return Future.value();
        }
      }

      // Permissões de localização negadas permanentemente
      if (permission == LocationPermission.deniedForever) {
        onDenied();
        return Future.value();
      }

      // Permissões concedidas
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        onGranted();
        return Future.value();
      }
    }
  }

  /// Obtém localização atual do usuário
  Future<void> getUserCurrentLocation({
    required Function(Position) onSuccess,
    required Function(Object) onFail,
    required Function(TimeoutException) onTimeoutException,
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition();
      onSuccess(position);
    } on TimeoutException catch (e) {
      onTimeoutException(e);
    } catch (e) {
      onFail(e);
    }
  }

  /// Compartilha o app
  Future<void> shareApp({BuildContext? context}) async {
    const String appUrl = 'https://apps.apple.com/br/app/boora/id6755944656';
    final String message = 'Conheça o $APP_NAME! O app para encontros e relacionamentos.';
    
    try {
      await SharePlus.instance.share(ShareParams(text: '$message $appUrl'));
    } catch (e) {
      debugPrint('Erro ao compartilhar: $e');
    }
  }

  /// Abre página de avaliação do app
  Future<void> reviewApp() async {
    try {
      final Uri url;
      if (Platform.isAndroid) {
        url = Uri.parse('https://play.google.com/store/apps/details?id=com.partiu.app');
      } else {
        url = Uri.parse('https://apps.apple.com/app/id6755944656');
      }
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir página de avaliação: $e');
    }
  }

  /// Abre política de privacidade
  Future<void> openPrivacyPage() async {
    try {
      final url = Uri.parse(BOORA_PRIVACY_POLICY_URL);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir política de privacidade: $e');
    }
  }

  /// Abre termos de serviço
  Future<void> openTermsPage() async {
    try {
      final url = Uri.parse(BOORA_TERMS_OF_SERVICE_URL);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir termos de serviço: $e');
    }
  }

  /// Abre página de segurança e etiqueta
  Future<void> openSafetyPage() async {
    try {
      final url = Uri.parse(BOORA_SAFETY_ETIQUETTE_URL);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir página de segurança: $e');
    }
  }

  /// Abre diretrizes da comunidade
  Future<void> openGuidelinesPage() async {
    try {
      final url = Uri.parse(BOORA_COMMUNITY_GUIDELINES_URL);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir diretrizes da comunidade: $e');
    }
  }

  /// Abre página sobre nós
  Future<void> openAboutPage() async {
    try {
      final url = Uri.parse(BOORA_WEBSITE_URL);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir página sobre nós: $e');
    }
  }

  /// Abre WhatsApp para reportar bug
  Future<void> openBugReport() async {
    try {
      final url = Uri.parse('https://wa.me/5511940498184?text=Ol%C3%A1%2C%20preciso%20de%20ajuda...');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp para reportar bug: $e');
    }
  }

  /// Abre URL genérica
  Future<void> openUrl(String urlString) async {
    try {
      final url = Uri.parse(urlString);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir URL ($urlString): $e');
    }
  }
}