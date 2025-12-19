import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:partiu/core/utils/app_logger.dart';
import 'package:partiu/features/profile/data/services/image_upload_service.dart';

/// ViewModel para gerenciar o fluxo de cadastro
/// TODO: Implementar lógica completa
class CadastroViewModel extends ChangeNotifier {
  // Profile
  dynamic imageFile;
  String fullName = '';
  
  // Birth date
  DateTime? birthDate;
  int? userBirthDay;
  int? userBirthMonth;
  int? userBirthYear;
  int? age; // Idade calculada
  
  // Additional info
  String selectedGender = '';
  String sexualOrientation = '';
  String interests = ''; // Categorias de atividades selecionadas
  String bio = '';
  String instagram = '';
  String jobTitle = '';
  String? country;
  String? from; // Cidade e Estado de origem
  
  // Origin
  String? originSource;
  
  // Terms
  bool agreeTerms = false;
  
  void resetData() {
    imageFile = null;
    fullName = '';
    birthDate = null;
    age = null;
    selectedGender = '';
    sexualOrientation = '';
    interests = '';
    bio = '';
    instagram = '';
    jobTitle = '';
    country = null;
    from = null;
    originSource = null;
    agreeTerms = false;
    notifyListeners();
  }
  
  void setImageFile(dynamic file) {
    imageFile = file;
    notifyListeners();
  }
  
  void setFullName(String name) {
    fullName = name;
    notifyListeners();
  }
  
  void setBirthDate(DateTime date) {
    birthDate = date;
    userBirthDay = date.day;
    userBirthMonth = date.month;
    userBirthYear = date.year;
    age = _calculateAge(date); // Calcula idade automaticamente
    notifyListeners();
  }
  
  /// Calcula a idade baseada na data de nascimento
  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int calculatedAge = now.year - birthDate.year;
    
    // Ajusta se ainda não fez aniversário este ano
    if (now.month < birthDate.month || 
        (now.month == birthDate.month && now.day < birthDate.day)) {
      calculatedAge--;
    }
    
    return calculatedAge;
  }
  
  bool isUserOldEnough() {
    if (birthDate == null) return false;
    return (age ?? 0) >= 18;
  }
  
  void setInterests(String selectedInterests) {
    interests = selectedInterests;
    notifyListeners();
  }
  
  void setBio(String text) {
    bio = text;
    notifyListeners();
  }
  
  void setInstagram(String username) {
    instagram = username;
    notifyListeners();
  }
  
  void setJobTitle(String title) {
    jobTitle = title;
    notifyListeners();
  }
  
  void setGender(String gender) {
    selectedGender = gender;
    notifyListeners();
  }
  
  void setSexualOrientation(String orientation) {
    sexualOrientation = orientation;
    notifyListeners();
  }
  void setCountry(String? countryCode) {
    country = countryCode;
    notifyListeners();
  }
  
  void setFrom(String? cityState) {
    from = cityState;
    notifyListeners();
  }
  
  void setOriginSource(String? source) {
    originSource = source;
    notifyListeners();
  }
  
  void setAgreeTerms(bool value) {
    agreeTerms = value;
    notifyListeners();
  }
  
  void createAccount({
    required Map<String, dynamic> onboardingData,
    required VoidCallback onSuccess,
    required Function(dynamic) onFail,
  }) async {
    const tag = 'CadastroViewModel';
    
    try {
      AppLogger.info('Creating user account...', tag: tag);
      
      // Verifica se o usuário está autenticado
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Usuário não autenticado');
      }
      
      final userId = currentUser.uid;
      final firestore = FirebaseFirestore.instance;
      
      // Processa os interesses (separados por vírgula) em lista
      final interestsString = onboardingData['interests'] as String? ?? '';
      final interestsList = interestsString.isNotEmpty
          ? interestsString.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      
      AppLogger.info('User interests: $interestsList (${interestsList.length} items)', tag: tag);
      
      // Faz upload da foto de perfil se disponível
      String? photoUrl;
      if (imageFile != null && imageFile is File) {
        try {
          AppLogger.info('Uploading compressed profile image to Storage...', tag: tag);
          
          // Usa o serviço de upload de imagem com compressão
          final imageUploadService = ImageUploadService();
          photoUrl = await imageUploadService.uploadAvatarImage(
            userId: userId,
            filePath: (imageFile as File).path,
            onProgress: (progress) {
              if (progress.isFinite && !progress.isNaN) {
                AppLogger.info('Upload progress: ${(progress * 100).toInt()}%', tag: tag);
              }
            },
          );
          
          AppLogger.success('Compressed profile image uploaded successfully', tag: tag);
        } catch (e) {
          AppLogger.error('Failed to upload profile image: $e', tag: tag);
        }
      }
      
      // Prepara os dados do usuário para salvar no Firestore
      final userData = <String, dynamic>{
        'userId': userId,
        'userEmail': currentUser.email, // Captura email do Auth (Google, Apple, Email/Pass)
        'userPhone': currentUser.phoneNumber, // Captura telefone se disponível
        'fullName': onboardingData['fullName'],
        
        // Birth date
        'birthDay': onboardingData['birthDay'],
        'birthMonth': onboardingData['birthMonth'],
        'birthYear': onboardingData['birthYear'],
        'age': onboardingData['age'],
        
        // New fields
        'instagram': onboardingData['instagram'],
        'jobTitle': onboardingData['jobTitle'],
        'gender': onboardingData['gender'],
        'bio': onboardingData['bio'],
        'from': onboardingData['from'], // País de origem
        'originSource': onboardingData['originSource'],
        
        // Avatar
        if (photoUrl != null) 'photoUrl': photoUrl,
        
        // Interests (até 6 atividades como array)
        'interests': interestsList,
        
        // Terms
        'agreeTerms': onboardingData['agreeTerms'],
        
        // VIP Priority (2 = Free, 1 = VIP) - usado para ordenação
        'vip_priority': onboardingData['vip_priority'] ?? 2,
        
        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'isBlocked': false,
      };
      
      AppLogger.info('Saving user data to Firestore...', tag: tag);
      
      // Salva no Firestore
      await firestore
          .collection('Users')
          .doc(userId)
          .set(userData, SetOptions(merge: true));
      
      AppLogger.success('User account created successfully', tag: tag);
      onSuccess();
      
    } catch (e) {
      AppLogger.error('Failed to create account: $e', tag: tag);
      onFail(e.toString());
    }
  }
}
