import 'package:json_annotation/json_annotation.dart';

part 'logto_user_info_response.g.dart';

@JsonSerializable()
class LogtoUserInfoResponse {
  @JsonKey(name: 'sub', required: true, disallowNullValue: true)
  final String sub;
  @JsonKey(name: 'username')
  final String? username;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'avatar')
  final String? avatar;
  @JsonKey(name: 'role_names')
  final List<String>? roleNames;
  @JsonKey(name: 'custom_data')
  final Map<String, dynamic>? customData;
  @JsonKey(name: 'identities')
  final Map<String, dynamic>? identities;

  LogtoUserInfoResponse({
    required this.sub,
    this.username,
    this.name,
    this.avatar,
    this.roleNames,
    this.customData,
    this.identities,
  });

  factory LogtoUserInfoResponse.fromJson(Map<String, dynamic> json) => _$LogtoUserInfoResponseFromJson(json);

  Map<String, dynamic> toJson() => _$LogtoUserInfoResponseToJson(this);
}
