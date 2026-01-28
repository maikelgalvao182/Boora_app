import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/utils/app_localizations.dart';
import 'package:flutter/material.dart';

/// Helper centralizado para formatação de "time ago" (tempo relativo)
/// 
/// Usa as chaves de internacionalização do projeto para garantir consistência.
/// Suporta:
/// - Timestamp do Firestore e DateTime
/// - Múltiplos locales via AppLocalizations
/// - Formatação consistente em toda a aplicação
/// 
/// Exemplos:
/// ```dart
/// TimeAgoHelper.format(context, timestamp: myTimestamp) // "agora mesmo", "há 5 minutos"
/// ```
class TimeAgoHelper {
  
  /// Formata timestamp em texto "time ago" (tempo relativo) usando chaves de i18n
  /// 
  /// [context] - BuildContext para acessar AppLocalizations
  /// [timestamp] - Timestamp do Firestore ou DateTime
  ///
  /// [short] - Se true, retorna formato abreviado (5m, 2h, 3d, 1s)
  /// 
  /// Retorna:
  /// - String localizada (ex: "agora mesmo", "há 5 minutos", "há 2 horas")
  /// - String vazia se timestamp for inválido
  static String format(BuildContext context, {required dynamic timestamp, bool short = false}) {
    // Converter timestamp para DateTime
    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp == null) {
      return '';
    } else {
      // Tipo não suportado
      return '';
    }
    
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final i18n = AppLocalizations.of(context);

    // Formato abreviado (solicitado: h, d, s)
    if (short) {
      // Menos de 1 minuto
      if (difference.inMinutes < 1) {
        return 'agora'; 
      }
      
      // Minutos (1-59)
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}min';
      }
      
      // Horas (1-23)
      if (difference.inHours < 24) {
        return '${difference.inHours}h';
      }
      
      // Dias (1-6) - até completar 1 semana
      if (difference.inDays < 7) {
        return '${difference.inDays}d';
      }

      // Semanas (1-4) - até completar ~1 mês (30 dias)
      if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '${weeks}s';
      }
      
      // Meses (1-11)
      final months = (difference.inDays / 30).floor();
      if (months < 12) {
        return '${months}mês';
      }
      
      // Anos
      final years = (difference.inDays / 365).floor();
      return '${years}a';
    }
    
    // Menos de 1 minuto
    if (difference.inMinutes < 1) {
      return i18n.translate('just_now');
    }
    
    // Minutos (1-59)
    if (difference.inMinutes < 60) {
      final count = difference.inMinutes;
      if (count == 1) {
        return 'há 1 min';
      }
      return i18n.translate('minutes_ago').replaceAll('{count}', count.toString());
    }
    
    // Horas (1-23)
    if (difference.inHours < 24) {
      final count = difference.inHours;
      if (count == 1) {
        return 'há 1 hora';
      }
      return i18n.translate('hours_ago').replaceAll('{count}', count.toString());
    }
    
    // Dias (1-29)
    if (difference.inDays < 30) {
      final count = difference.inDays;
      if (count == 1) {
        return 'há 1 dia';
      }
      return i18n.translate('days_ago').replaceAll('{count}', count.toString());
    }
    
    // Meses (aproximado - 1-11)
    final months = (difference.inDays / 30).floor();
    if (months < 12) {
      if (months == 1) {
        return 'há 1 mês';
      }
      return i18n.translate('months_ago').replaceAll('{count}', months.toString());
    }
    
    // Anos
    final years = (difference.inDays / 365).floor();
    if (years == 1) {
      return 'há 1 ano';
    }
    return i18n.translate('years_ago').replaceAll('{count}', years.toString());
  }
  
  /// Formata timestamp com contexto (método legado - mantém compatibilidade)
  /// 
  /// @deprecated Use format(context, timestamp: timestamp) instead
  static String formatAbbreviated(dynamic timestamp, {String? locale}) {
    // Retorna formato básico sem internacionalização para compatibilidade
    // Recomendado migrar para o novo método format(context, timestamp: timestamp)
    if (timestamp == null) return '';
    
    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return '';
    }
    
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} h ago';
    if (difference.inDays < 30) return '${difference.inDays} d ago';
    
    final months = (difference.inDays / 30).floor();
    if (months < 12) return '$months mo ago';
    
    final years = (difference.inDays / 365).floor();
    return '$years y ago';
  }
  
  /// Formata timestamp sem abreviações (método legado - mantém compatibilidade)
  /// 
  /// @deprecated Use format(context, timestamp: timestamp) instead
  static String formatFull(dynamic timestamp, {String? locale}) {
    return formatAbbreviated(timestamp, locale: locale);
  }
}
