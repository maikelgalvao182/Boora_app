import 'package:partiu/core/models/user.dart';
import 'package:partiu/features/profile/domain/calculators/i_profile_completeness_calculator.dart';
import 'package:partiu/core/utils/app_logger.dart';

/// Calculadora de completude específica para Fornecedores (Vendors)
/// 
/// Avalia completude baseado nos campos que realmente existem na UI:
/// - Tab Personal: fullName, jobTitle, bio, gender, sexualOrientation, lookingFor, maritalStatus, languages, instagram
/// - Tab Interests: lista de interesses selecionados
/// - Tab Gallery: grid de fotos (até 9)
/// - Essenciais: Avatar
/// 
/// ⚠️ Campos REMOVIDOS (não existem mais na UI):
/// - birthDate, locality, from, state, school (ocultos/removidos da PersonalTab)
/// - website, tiktok, pinterest, youtube, vimeo (não existe tab Social)
/// - videos (não existe na GalleryTab)
class VendorProfileCompletenessCalculator implements IProfileCompletenessCalculator {
  static const String _tag = 'VendorCompletenessCalc';
  
  // === PESOS (TOTAL: 100) ===
  // Apenas campos que realmente existem na UI
  
  // ESSENCIAIS (30 pontos)
  static const int _avatarW = 15;
  static const int _interestsWMax = 15;

  // PERSONAL TAB (60 pontos)
  static const int _nameW = 10;
  static const int _bioW = 10;
  static const int _jobTitleW = 8;
  static const int _genderW = 6;
  static const int _sexualOrientationW = 5;
  static const int _lookingForW = 5;
  static const int _maritalStatusW = 5;
  static const int _languagesW = 6;
  static const int _instagramW = 5;
  
  // GALLERY TAB (10 pontos)
  static const int _galleryWMax = 10;

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
    if (user.languages?.isNotEmpty == true) score += _languagesW;
    if (user.userInstagram?.isNotEmpty == true) score += _instagramW;

    // === GALLERY ===
    score += _calculatePhotosScore(user);
    
    return score.clamp(0, 100);
  }

  int _calculateInterestsScore(User user) {
    final interests = user.interests ?? [];
    final count = interests.length;
    // 3 pontos por interesse até max 15 (5 interesses = 100%)
    final val = (count * 3).clamp(0, _interestsWMax);
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
    
    // 2 pontos por foto até max 10 (5 fotos = 100%)
    final score = (photoCount * 2).clamp(0, _galleryWMax);
    return score;
  }

  @override
  Map<String, dynamic> getDetails(User user) {
    final details = <String, dynamic>{};
    
    // Essenciais
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
    details['languages'] = (user.languages?.isNotEmpty == true) ? _languagesW : 0;
    details['instagram'] = (user.userInstagram?.isNotEmpty == true) ? _instagramW : 0;
    
    // Gallery
    details['photos'] = _calculatePhotosScore(user);

    final total = calculate(user);
    details['total'] = total;
    
    return details;
  }
}
