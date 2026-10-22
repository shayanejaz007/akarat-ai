import 'search_constraints.dart';

/// Text, or null when the column holds anything else.
String? _str(Object? v) => v is String ? v : null;

/// A row of `public.saved_searches` (0001_init.sql). Private to its owner.
class SavedSearch {
  const SavedSearch({required this.id, required this.label, required this.constraints, required this.createdAt});

  final String id;
  final String label;
  final SearchConstraints constraints;
  final DateTime createdAt;

  factory SavedSearch.fromRow(Map<String, Object?> row) {
    final c = row['constraints'];
    return SavedSearch(
      id: row['id']! as String,
      label: _str(row['label']) ?? '',
      constraints: c is Map<String, Object?> ? SearchConstraints.fromJson(c) : SearchConstraints.empty,
      createdAt: DateTime.tryParse(_str(row['created_at']) ?? '') ?? DateTime.now(),
    );
  }
}

/// A row of `public.inquiries`, with the listing's titles joined in when RLS
/// lets the reader see that listing.
class Inquiry {
  const Inquiry({
    required this.id,
    required this.propertyId,
    required this.ownerId,
    required this.name,
    required this.message,
    required this.status,
    required this.createdAt,
    this.senderId,
    this.email,
    this.phone,
    this.propertyTitleEn,
    this.propertyTitleAr,
  });

  final String id;
  final String propertyId;
  final String ownerId;
  final String? senderId;
  final String name;
  final String? email;
  final String? phone;
  final String message;
  final String status;
  final DateTime createdAt;
  final String? propertyTitleEn;
  final String? propertyTitleAr;

  String? propertyTitle(String lang) {
    final ar = propertyTitleAr?.trim() ?? '';
    final en = propertyTitleEn?.trim() ?? '';
    final pick = lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
    return pick.isEmpty ? null : pick;
  }

  factory Inquiry.fromRow(Map<String, Object?> row) {
    final p = row['properties'];
    return Inquiry(
      id: row['id']! as String,
      propertyId: row['property_id']! as String,
      ownerId: row['owner_id']! as String,
      senderId: _str(row['sender_id']),
      name: _str(row['name']) ?? '',
      email: _str(row['email']),
      phone: _str(row['phone']),
      message: _str(row['message']) ?? '',
      status: _str(row['status']) ?? 'new',
      createdAt: DateTime.tryParse(_str(row['created_at']) ?? '') ?? DateTime.now(),
      propertyTitleEn: p is Map ? _str(p['title_en']) : null,
      propertyTitleAr: p is Map ? _str(p['title_ar']) : null,
    );
  }
}

/// `public.profiles`: one row per auth user, created by a trigger on sign-up.
class Profile {
  const Profile({
    required this.id,
    this.fullName = '',
    this.phone,
    this.locale = 'en',
    this.role = 'user',
    this.agency,
    this.verified = false,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String locale;
  final String role;
  final String? agency;
  final bool verified;

  factory Profile.fromRow(Map<String, Object?> row) => Profile(
    id: row['id']! as String,
    fullName: _str(row['full_name']) ?? '',
    phone: _str(row['phone']),
    locale: _str(row['locale']) ?? 'en',
    role: _str(row['role']) ?? 'user',
    agency: _str(row['agency']),
    verified: row['verified'] == true,
  );
}
