// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'logto_user_info_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LogtoUserInfoResponse _$LogtoUserInfoResponseFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    requiredKeys: const ['sub'],
    disallowNullValues: const ['sub'],
  );
  return LogtoUserInfoResponse(
    sub: json['sub'] as String,
    username: json['username'] as String?,
    name: json['name'] as String?,
    avatar: json['avatar'] as String?,
    customData: json['custom_data'] as Map<String, dynamic>?,
    roleNames: (json['role_names'] as List<dynamic>?)?.map((e) => e as String).toList(),
    identities: json['identities'] as Map<String, dynamic>?,
  );
}

Map<String, dynamic> _$LogtoUserInfoResponseToJson(LogtoUserInfoResponse instance) => <String, dynamic>{
      'sub': instance.sub,
      'username': instance.username,
      'name': instance.name,
      'avatar': instance.avatar,
      'role_names': instance.roleNames,
      'custom_data': instance.customData,
      'identities': instance.identities,
    };
