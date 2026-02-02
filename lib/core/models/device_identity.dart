class DeviceIdentityPayload {
  DeviceIdentityPayload({
    required this.deviceIdHash,
    required this.platform,
    this.deviceName,
    this.osName,
    this.osVersion,
    this.appVersion,
    this.buildCode,
    this.applicationName,
  });

  final String deviceIdHash;
  final String platform;
  final String? deviceName;
  final String? osName;
  final String? osVersion;
  final String? appVersion;
  final String? buildCode;
  final String? applicationName;

  Map<String, dynamic> toMap() {
    return {
      'deviceIdHash': deviceIdHash,
      'platform': platform,
      if (deviceName != null) 'deviceName': deviceName,
      if (osName != null) 'osName': osName,
      if (osVersion != null) 'osVersion': osVersion,
      if (appVersion != null) 'appVersion': appVersion,
      if (buildCode != null) 'buildCode': buildCode,
      if (applicationName != null) 'applicationName': applicationName,
    };
  }
}

class DeviceBlacklistCheckResult {
  DeviceBlacklistCheckResult({
    required this.blocked,
    this.reason,
  });

  final bool blocked;
  final String? reason;
}
