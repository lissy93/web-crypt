import 'package:web_crypt/crypto/format.dart';

/// the public half of a stored key. private key material never lives here,
/// only in the encrypted vault
class KeyEntry {
  const KeyEntry({
    required this.id,
    required this.format,
    required this.label,
    required this.publicMaterial,
    required this.fingerprint,
    required this.createdAt,
    this.hasPrivate = false,
    this.privateIsProtected = false,
    this.userId = '',
    this.expiresAt,
  });

  factory KeyEntry.fromJson(Map<String, Object?> json) {
    return KeyEntry(
      id: json['id']! as String,
      format: CryptoFormatKind.values.byName(json['format']! as String),
      label: json['label'] as String? ?? '',
      publicMaterial: json['publicMaterial']! as String,
      fingerprint: json['fingerprint']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt']! as int,
        isUtc: true,
      ),
      hasPrivate: json['hasPrivate'] as bool? ?? false,
      privateIsProtected: json['privateIsProtected'] as bool? ?? false,
      userId: json['userId'] as String? ?? '',
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['expiresAt']! as int,
              isUtc: true,
            ),
    );
  }

  final String id;
  final CryptoFormatKind format;
  final String label;
  final String publicMaterial;

  /// age recipients are their own fingerprint, PGP keys use the hex primary
  /// key fingerprint
  final String fingerprint;
  final DateTime createdAt;
  final bool hasPrivate;
  final bool privateIsProtected;
  final String userId;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  String get displayName => label.isNotEmpty
      ? label
      : userId.isNotEmpty
      ? userId
      : fingerprint;

  Recipient get asRecipient =>
      Recipient(format: format, material: publicMaterial, label: displayName);

  KeyEntry copyWith({
    String? label,
    bool? hasPrivate,
    bool? privateIsProtected,
  }) {
    return KeyEntry(
      id: id,
      format: format,
      label: label ?? this.label,
      publicMaterial: publicMaterial,
      fingerprint: fingerprint,
      createdAt: createdAt,
      hasPrivate: hasPrivate ?? this.hasPrivate,
      privateIsProtected: privateIsProtected ?? this.privateIsProtected,
      userId: userId,
      expiresAt: expiresAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'format': format.name,
    'label': label,
    'publicMaterial': publicMaterial,
    'fingerprint': fingerprint,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'hasPrivate': hasPrivate,
    'privateIsProtected': privateIsProtected,
    'userId': userId,
    if (expiresAt != null) 'expiresAt': expiresAt!.millisecondsSinceEpoch,
  };
}
