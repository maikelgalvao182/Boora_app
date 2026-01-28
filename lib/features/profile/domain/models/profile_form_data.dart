/// Modelo imutável para dados do formulário de edição de perfil
/// 
/// Segue boas práticas:
/// - Imutabilidade (usando copyWith)
/// - Campos nulos permitidos (nem todos são obrigatórios)
/// - camelCase para consistência
/// - Separação clara entre dados básicos e dados de vendor
class ProfileFormData {
  // ==================== DADOS BÁSICOS ====================
  
  final String? fullname;
  final String? bio;
  final String? jobTitle;
  final String? gender;
  final String? sexualOrientation;
  final String? lookingFor; // O que procura (comma-separated)
  final String? maritalStatus; // Estado civil
  
  // Data de nascimento
  final int? birthDay;
  final int? birthMonth;
  final int? birthYear;
  
  // Localização
  final String? locality;
  final String? state;
  final String? country;
  final Map<String, dynamic>? geoPoint;
  
  // ==================== REDES SOCIAIS ====================
  
  final String? instagram;
  
  // ==================== IDIOMAS ====================
  
  final String? languages;
  
  // ==================== DADOS DE VENDOR ====================
  
  // Preços
  final double? startingPrice;
  final double? averagePrice;
  
  // Experiência
  final int? yearsOfExperience;
  
  // Serviços
  final String? servicesOffered;
  
  // Categorias de ofertas
  final List<String>? offerCategories;
  
  // ==================== MÍDIA ====================
  
  final String? photoUrl;
  final List<String>? photoUrls;

  // ==================== INTERESSES ====================

  final List<String>? interests;
  
  const ProfileFormData({
    this.fullname,
    this.bio,
    this.jobTitle,
    this.gender,
    this.sexualOrientation,
    this.lookingFor,
    this.maritalStatus,
    this.birthDay,
    this.birthMonth,
    this.birthYear,
    this.locality,
    this.state,
    this.country,
    this.geoPoint,
    this.instagram,
    this.languages,
    this.startingPrice,
    this.averagePrice,
    this.yearsOfExperience,
    this.servicesOffered,
    this.offerCategories,
    this.photoUrl,
    this.photoUrls,
    this.interests,
  });
  
  /// Cria uma cópia com campos atualizados
  ProfileFormData copyWith({
    String? fullname,
    String? bio,
    String? jobTitle,
    String? gender,
    String? sexualOrientation,
    String? lookingFor,
    String? maritalStatus,
    int? birthDay,
    int? birthMonth,
    int? birthYear,
    String? locality,
    String? state,
    String? country,
    Map<String, dynamic>? geoPoint,
    String? instagram,
    String? languages,
    double? startingPrice,
    double? averagePrice,
    int? yearsOfExperience,
    String? servicesOffered,
    List<String>? offerCategories,
    String? photoUrl,
    List<String>? photoUrls,
    List<String>? interests,
  }) {
    return ProfileFormData(
      fullname: fullname ?? this.fullname,
      bio: bio ?? this.bio,
      jobTitle: jobTitle ?? this.jobTitle,
      gender: gender ?? this.gender,
      sexualOrientation: sexualOrientation ?? this.sexualOrientation,
      lookingFor: lookingFor ?? this.lookingFor,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      birthDay: birthDay ?? this.birthDay,
      birthMonth: birthMonth ?? this.birthMonth,
      birthYear: birthYear ?? this.birthYear,
      locality: locality ?? this.locality,
      state: state ?? this.state,
      country: country ?? this.country,
      geoPoint: geoPoint ?? this.geoPoint,
      instagram: instagram ?? this.instagram,
      languages: languages ?? this.languages,
      startingPrice: startingPrice ?? this.startingPrice,
      averagePrice: averagePrice ?? this.averagePrice,
      yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
      servicesOffered: servicesOffered ?? this.servicesOffered,
      offerCategories: offerCategories ?? this.offerCategories,
      photoUrl: photoUrl ?? this.photoUrl,
      photoUrls: photoUrls ?? this.photoUrls,
      interests: interests ?? this.interests,
    );
  }
  
  /// Factory para criar a partir de dados do Firestore
  factory ProfileFormData.fromFirestore(Map<String, dynamic> data) {
    // ⚠️ FILTRAR URLs do Google OAuth (dados legados)
    var rawPhotoUrl = data['photoUrl'] as String?;
    if (rawPhotoUrl != null && 
        (rawPhotoUrl.contains('googleusercontent.com') || 
         rawPhotoUrl.contains('lh3.google'))) {
      rawPhotoUrl = null;
    }
    
    return ProfileFormData(
      fullname: data['userFullname'] as String?,
      bio: data['userBio'] as String?,
      jobTitle: data['userJobTitle'] as String?,
      gender: data['userGender'] as String?,
      sexualOrientation: data['sexualOrientation'] as String?,
      lookingFor: data['lookingFor'] as String?,
      maritalStatus: data['maritalStatus'] as String?,
      birthDay: data['userBirthDay'] as int?,
      birthMonth: data['userBirthMonth'] as int?,
      birthYear: data['userBirthYear'] as int?,
      locality: data['locality'] as String?,
      state: data['state'] as String?,
      country: data['country'] as String?,
      geoPoint: data['userGeoPoint'] as Map<String, dynamic>?,
      instagram: data['instagram'] as String?,
      languages: data['languages'] as String?,
      startingPrice: (data['startingPrice'] as num?)?.toDouble(),
      averagePrice: (data['averagePrice'] as num?)?.toDouble(),
      yearsOfExperience: data['yearsOfExperience'] as int?,
      servicesOffered: data['servicesOffered'] as String?,
      offerCategories: (data['offerCategories'] as List?)?.cast<String>(),
      photoUrl: rawPhotoUrl,
      photoUrls: (data['userPhotos'] as List?)?.cast<String>(),
      interests: (data['interests'] as List?)?.cast<String>(),
    );
  }
  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{};
    
    // Adiciona apenas campos não-nulos
    if (fullname != null) map['userFullname'] = fullname;
    if (bio != null) map['userBio'] = bio;
    if (jobTitle != null) map['userJobTitle'] = jobTitle;
    if (gender != null) map['userGender'] = gender;
    if (sexualOrientation != null) map['sexualOrientation'] = sexualOrientation;
    if (lookingFor != null) map['lookingFor'] = lookingFor;
    if (maritalStatus != null) map['maritalStatus'] = maritalStatus;
    if (birthDay != null) map['userBirthDay'] = birthDay;
    if (birthMonth != null) map['userBirthMonth'] = birthMonth;
    if (birthYear != null) map['userBirthYear'] = birthYear;
    if (locality != null) map['locality'] = locality;
    if (state != null) map['state'] = state;
    if (country != null) map['country'] = country;
    if (geoPoint != null) map['userGeoPoint'] = geoPoint;
    if (instagram != null) map['instagram'] = instagram;
    if (languages != null) map['languages'] = languages;
    if (startingPrice != null) map['startingPrice'] = startingPrice;
    if (averagePrice != null) map['averagePrice'] = averagePrice;
    if (yearsOfExperience != null) map['yearsOfExperience'] = yearsOfExperience;
    if (servicesOffered != null) map['servicesOffered'] = servicesOffered;
    if (offerCategories != null) map['offerCategories'] = offerCategories;
    if (photoUrl != null) map['photoUrl'] = photoUrl;
    if (photoUrls != null) map['userPhotos'] = photoUrls;
    if (interests != null) map['interests'] = interests;
    
    return map;
  }
}
