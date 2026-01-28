/// Modelo imutável para uma oferta
/// 
/// Cada oferta contém:
/// - title: Título da oferta
/// - subtitle: Subtítulo da oferta
/// - items: Lista de até 4 itens (benefícios/características)
class Offer {
  const Offer({
    this.title = '',
    this.subtitle = '',
    this.items = const [],
    this.price,
    this.discount,
  });

  final String title;
  final String subtitle;
  final List<String> items;
  final double? price;
  final int? discount;
}

/// Modelo imutável para dados do formulário de perfil
/// 
/// Implementado manualmente para evitar dependência de codegen em tempo de build.
class ProfileFormData {
  const ProfileFormData({
    this.fullname,
    this.bio = '',
    this.jobTitle = '',
    this.school = '',
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
    this.locationCountry,
    this.email,
    this.phoneNumber,
    this.website,
    this.instagram,
    this.tiktok,
    this.youtube,
    this.pinterest,
    this.vimeo,
    this.interests,
    this.languages,
    this.startingPrice,
    this.averagePrice,
    this.servicesOffered,
    this.offers = const [],
  });

  final String? fullname;
  final String bio;
  final String jobTitle;
  final String school;
  final String? gender;
  final String? sexualOrientation;
  final String? lookingFor; // CSV: friendship,networking,serious_relationship,casual
  final String? maritalStatus; // single|dating|married|divorced
  final int? birthDay;
  final int? birthMonth;
  final int? birthYear;
  final String? locality;
  final String? state;
  final String? country; // País de origem (from)
  final String? locationCountry; // País da localização atual (country)
  final String? email;
  final String? phoneNumber;
  final String? website;
  final String? instagram;
  final String? tiktok;
  final String? youtube;
  final String? pinterest;
  final String? vimeo;
  final String? interests;
  final String? languages;
  final double? startingPrice;
  final double? averagePrice;
  final String? servicesOffered;
  final List<Offer> offers;

  ProfileFormData copyWith({
    String? fullname,
    String? bio,
    String? jobTitle,
    String? school,
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
    String? locationCountry,
    String? email,
    String? phoneNumber,
    String? website,
    String? instagram,
    String? tiktok,
    String? youtube,
    String? pinterest,
    String? vimeo,
    String? interests,
    String? languages,
    double? startingPrice,
    double? averagePrice,
    String? servicesOffered,
    List<Offer>? offers,
  }) {
    return ProfileFormData(
      fullname: fullname ?? this.fullname,
      bio: bio ?? this.bio,
      jobTitle: jobTitle ?? this.jobTitle,
      school: school ?? this.school,
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
      locationCountry: locationCountry ?? this.locationCountry,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      website: website ?? this.website,
      instagram: instagram ?? this.instagram,
      tiktok: tiktok ?? this.tiktok,
      youtube: youtube ?? this.youtube,
      pinterest: pinterest ?? this.pinterest,
      vimeo: vimeo ?? this.vimeo,
      interests: interests ?? this.interests,
      languages: languages ?? this.languages,
      startingPrice: startingPrice ?? this.startingPrice,
      averagePrice: averagePrice ?? this.averagePrice,
      servicesOffered: servicesOffered ?? this.servicesOffered,
      offers: offers ?? this.offers,
    );
  }
}

/// Estado da tela de edição de perfil
/// 
/// Seguindo boas práticas:
/// - Imutável
/// - Estados bem definidos
sealed class EditProfileState {
  const EditProfileState();
}

/// Estado inicial (carregando dados)
class EditProfileStateInitial extends EditProfileState {
  const EditProfileStateInitial();
}

/// Estado carregado (pronto para edição)
class EditProfileStateLoaded extends EditProfileState {
  const EditProfileStateLoaded({
    required this.formData,
    this.hasUnsavedChanges = false,
    this.selectedTabIndex = 0,
  });
  
  final ProfileFormData formData;
  final bool hasUnsavedChanges;
  final int selectedTabIndex;
}

/// Estado salvando
class EditProfileStateSaving extends EditProfileState {
  const EditProfileStateSaving({
    required this.formData,
  });
  
  final ProfileFormData formData;
}

/// Estado atualizando foto
class EditProfileStateUpdatingPhoto extends EditProfileState {
  const EditProfileStateUpdatingPhoto({
    required this.formData,
  });
  
  final ProfileFormData formData;
}

/// Estado de erro
class EditProfileStateError extends EditProfileState {
  const EditProfileStateError({
    required this.message,
    required this.formData,
  });
  
  final String message;
  final ProfileFormData formData;
}

/// Resultado da validação do formulário
sealed class ValidationResult {
  const ValidationResult();
}

class ValidationResultValid extends ValidationResult {
  const ValidationResultValid();
}

class ValidationResultInvalid extends ValidationResult {
  const ValidationResultInvalid({
    required this.fieldErrors,
  });
  
  final Map<String, String> fieldErrors;
}

/// Dados de localização parseados
class LocationData {
  const LocationData({
    this.locality,
    this.state,
    this.country,
  });
  
  final String? locality;
  final String? state;
  final String? country;
}

/// Dados de foto para upload
class PhotoUploadData {
  const PhotoUploadData({
    required this.localPath,
    required this.oldPhotoUrl,
    required this.uploadType,
  });
  
  final String localPath;
  final String oldPhotoUrl;
  final PhotoUploadType uploadType;
}

/// Tipo de upload de foto
enum PhotoUploadType {
  profilePicture,
  galleryImage,
  video,
}

/// Resultado de operação de salvamento
sealed class SaveResult {
  const SaveResult();
}

class SaveResultSuccess extends SaveResult {
  const SaveResultSuccess({
    this.messageKey = 'profile_updated_successfully',
  });
  
  final String messageKey;
}

class SaveResultFailure extends SaveResult {
  const SaveResultFailure({
    required this.messageKey,
    this.errorDetails,
  });
  
  final String messageKey;
  final String? errorDetails;
}

/// Resultado de operação de upload de foto
sealed class PhotoUploadResult {
  const PhotoUploadResult();
}

class PhotoUploadResultSuccess extends PhotoUploadResult {
  const PhotoUploadResultSuccess({
    required this.photoUrl,
    this.messageKey = 'photo_updated_successfully',
  });
  
  final String photoUrl;
  final String messageKey;
}

class PhotoUploadResultFailure extends PhotoUploadResult {
  const PhotoUploadResultFailure({
    required this.messageKey,
    this.errorDetails,
  });
  
  final String messageKey;
  final String? errorDetails;
}
