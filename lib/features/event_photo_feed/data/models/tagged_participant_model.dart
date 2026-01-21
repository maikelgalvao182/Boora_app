/// Modelo de participante marcado em uma foto do feed
class TaggedParticipantModel {
  const TaggedParticipantModel({
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
  });

  final String userId;
  final String userName;
  final String? userPhotoUrl;

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
    };
  }

  factory TaggedParticipantModel.fromMap(Map<String, dynamic> map) {
    return TaggedParticipantModel(
      userId: (map['userId'] as String?) ?? '',
      userName: (map['userName'] as String?) ?? '',
      userPhotoUrl: map['userPhotoUrl'] as String?,
    );
  }
}
