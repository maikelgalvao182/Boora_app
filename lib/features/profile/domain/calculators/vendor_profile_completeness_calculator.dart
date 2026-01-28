import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/profile/domain/calculators/i_profile_completeness_calculator.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Calculadora de completude específica para Fornecedores (Vendors)
/// 
/// Avalia completude baseado nos Enums de preview:
/// - PersonalFieldType
/// - SocialFieldType
/// - MidiaFieldType
/// 
/// E campos essenciais (Avatar, Interesses).
class VendorProfileCompletenessCalculator implements IProfileCompletenessCalculator {
  static const String _tag = 'VendorCompletenessCalc';
  
  // === PESOS (TOTAL: 100) ===
  
  // ESSENCIAIS (20 pontos)
  static const int _avatarW = 10;
  static const int _interestsWMax = 10;

  // PERSONAL TAB (50 pontos)
  static const int _nameW = 5;
  static const int _bioW = 5;
  static const int _jobTitleW = 5;
  static const int _genderW = 3;
  static const int _sexualOrientationW = 2;
  static const int _lookingForW = 2;
  static const int _maritalStatusW = 2;
  static const int _birthDateW = 4;
  static const int _localityW = 4;
  static const int _stateW = 3;
  static const int _fromW = 3;
  static const int _schoolW = 3;
  static const int _languagesW = 5;
  static const int _instagramW = 4; // Contado no Personal

  // SOCIAL TAB (10 pontos - exceto Instagram)
  static const int _websiteW = 2;
  static const int _tiktokW = 2;
  static const int _pinterestW = 2;
  static const int _youtubeW = 2;
  static const int _vimeoW = 2;
  
  // MIDIA TAB (20 pontos)
  static const int _galleryWMax = 10;
  static const int _videosW = 10;

  @override
  int calculate(User user) {
    int score = 0;
    
    // === ESSENCIAIS ===
    if (user.photoUrl.isNotEmpty) score += _avatarW;
    score += _calculateInterestsScore(user);

    // === PERSONAL FIELDS ===
    if (user.userFullname.isNotEmpty) score += _nameW;
    if (user.userBio.isNotEmpty) score += _bioW;
    if (user.userJobTitle.isNotEmpty) score += _jobTitleW;
    if (user.userGender.isNotEmpty) score += _genderW;
    if (user.userSexualOrientation.isNotEmpty) score += _sexualOrientationW;
    if (user.lookingFor?.isNotEmpty == true) score += _lookingForW;
    if (user.maritalStatus?.isNotEmpty == true) score += _maritalStatusW;
    if (user.userBirthDay > 0 && user.userBirthMonth > 0 && user.userBirthYear > 0) score += _birthDateW;
    if (user.userLocality.isNotEmpty) score += _localityW;
    if (user.userState?.isNotEmpty == true) score += _stateW;
    if (user.from?.isNotEmpty == true) score += _fromW;
    if (user.languages?.isNotEmpty == true) score += _languagesW;
    if (user.userInstagram?.isNotEmpty == true) score += _instagramW;

    // School (Armazenado em settings ou futuro)
    if (_hasSettingsField(user, 'school')) score += _schoolW;

    // === SOCIAL FIELDS (Armazenados em settings ou userInstagram) ===
    // Nota: Instagram já contado acima
    if (_hasSocialField(user, 'website')) score += _websiteW;
    if (_hasSocialField(user, 'tiktok')) score += _tiktokW;
    if (_hasSocialField(user, 'pinterest')) score += _pinterestW;
    if (_hasSocialField(user, 'youtube')) score += _youtubeW;
    if (_hasSocialField(user, 'vimeo')) score += _vimeoW;

    // === MIDIA FIELDS ===
    score += _calculatePhotosScore(user);
    // Videos
    // Verificamos 'videos' se é uma string não vazia ou lista não vazia
    if (_hasSettingsField(user, 'videos') || _hasCollectionField(user, 'videos')) {
      score += _videosW;
    }
    
    return score.clamp(0, 100);
  }

  // Helpers
  bool _hasSettingsField(User user, String key) {
    if (user.userSettings == null) return false;
    final val = user.userSettings![key];
    if (val == null) return false;
    if (val is String) return val.trim().isNotEmpty;
    if (val is List) return val.isNotEmpty;
    if (val is Map) return val.isNotEmpty;
    return true; // defined but not null
  }

  bool _hasSocialField(User user, String provider) {
    // 1. Tentar estrutura aninhada: settings['social']['website']
    final social = user.userSettings?['social'];
    if (social is Map) {
      final val = social[provider] ?? social[provider.toLowerCase()];
      if (val is String && val.trim().isNotEmpty) return true;
    }
    // 2. Tentar flat settings: settings['website'] if applicable
    if (_hasSettingsField(user, provider)) return true; // generic check
    
    return false; 
  }

  bool _hasCollectionField(User user, String key) {
      // Stub para lista se necessário
      return false; 
  }

  int _calculateInterestsScore(User user) {
    final interests = user.interests ?? [];
    final count = interests.length;
    // Escala linear simples: 2 pontos por interesse até 5?
    final val = (count * 2).clamp(0, _interestsWMax);
    return val;
  }
  
  int _calculatePhotosScore(User user) {
    final gallery = user.userGallery ?? <String, dynamic>{};
    final photoCount = gallery.values.where((v) {
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is Map<String, dynamic>) {
        final url = v['url'] as String?;
        return url != null && url.trim().isNotEmpty;
      }
      return false;
    }).length;
    
    // Max 10 pontos. Digamos 2 pontos por foto até 5 fotos.
    final score = (photoCount * 2).clamp(0, _galleryWMax);
    return score;
  }

  @override
  Map<String, dynamic> getDetails(User user) {
    // Retorna detalhes de DEBUG e UI se necessário
    final details = <String, dynamic>{};
    
    details['avatar'] = user.photoUrl.isNotEmpty ? _avatarW : 0;
    details['interests'] = _calculateInterestsScore(user);
    
    // Personal
    details['name'] = user.userFullname.isNotEmpty ? _nameW : 0;
    details['bio'] = user.userBio.isNotEmpty ? _bioW : 0;
    details['jobTitle'] = user.userJobTitle.isNotEmpty ? _jobTitleW : 0;
    details['gender'] = user.userGender.isNotEmpty ? _genderW : 0;
    details['sexualOrientation'] = user.userSexualOrientation.isNotEmpty ? _sexualOrientationW : 0;
    details['lookingFor'] = (user.lookingFor?.isNotEmpty == true) ? _lookingForW : 0;
    details['maritalStatus'] = (user.maritalStatus?.isNotEmpty == true) ? _maritalStatusW : 0;
    details['birthDate'] = (user.userBirthDay > 0) ? _birthDateW : 0;
    details['locality'] = user.userLocality.isNotEmpty ? _localityW : 0;
    details['state'] = (user.userState?.isNotEmpty == true) ? _stateW : 0;
    details['from'] = (user.from?.isNotEmpty == true) ? _fromW : 0;
    details['languages'] = (user.languages?.isNotEmpty == true) ? _languagesW : 0;
    details['instagram'] = (user.userInstagram?.isNotEmpty == true) ? _instagramW : 0;
    
    details['school'] = _hasSettingsField(user, 'school') ? _schoolW : 0;

    // Social
    details['website'] = _hasSocialField(user, 'website') ? _websiteW : 0;
    // ... others implies just sum or detailed breakdown
    
    // Midia
    details['photos'] = _calculatePhotosScore(user);
    details['videos'] = (_hasSettingsField(user, 'videos')) ? _videosW : 0;

    final total = calculate(user);
    details['total'] = total;
    
    return details;
  }
}
