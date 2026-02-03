// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_preview_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CachedUserPreviewAdapter extends TypeAdapter<CachedUserPreview> {
  @override
  final int typeId = 24;

  @override
  CachedUserPreview read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CachedUserPreview(
      data: fields[0] as UserPreviewModel,
      cachedAt: fields[1] as DateTime,
      remoteUpdatedAt: fields[2] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, CachedUserPreview obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.data)
      ..writeByte(1)
      ..write(obj.cachedAt)
      ..writeByte(2)
      ..write(obj.remoteUpdatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedUserPreviewAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class UserPreviewModelAdapter extends TypeAdapter<UserPreviewModel> {
  @override
  final int typeId = 23;

  @override
  UserPreviewModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserPreviewModel(
      uid: fields[0] as String,
      fullName: fields[1] as String?,
      avatarUrl: fields[2] as String?,
      isVerified: fields[3] as bool? ?? false,
      isVip: fields[4] as bool? ?? false,
      city: fields[5] as String?,
      state: fields[6] as String?,
      country: fields[7] as String?,
      bio: fields[8] as String?,
      isOnline: fields[9] as bool? ?? false,
      status: fields[10] as String? ?? 'active',
    );
  }

  @override
  void write(BinaryWriter writer, UserPreviewModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.fullName)
      ..writeByte(2)
      ..write(obj.avatarUrl)
      ..writeByte(3)
      ..write(obj.isVerified)
      ..writeByte(4)
      ..write(obj.isVip)
      ..writeByte(5)
      ..write(obj.city)
      ..writeByte(6)
      ..write(obj.state)
      ..writeByte(7)
      ..write(obj.country)
      ..writeByte(8)
      ..write(obj.bio)
      ..writeByte(9)
      ..write(obj.isOnline)
      ..writeByte(10)
      ..write(obj.status);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreviewModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
