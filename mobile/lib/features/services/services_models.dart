/// Service requests (supabase/migrations/0024_services.sql), as the website
/// reads them.
library;

/// One kind of work people can ask for. Managed in the admin panel.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.en,
    required this.ar,
    required this.examplesEn,
    required this.examplesAr,
    required this.icon,
    required this.custom,
  });

  factory ServiceCategory.fromRow(Map<String, Object?> r) => ServiceCategory(
    id: '${r['id']}',
    en: '${r['name_en'] ?? ''}',
    ar: '${r['name_ar'] ?? ''}',
    examplesEn: '${r['examples_en'] ?? ''}',
    examplesAr: '${r['examples_ar'] ?? ''}',
    icon: '${r['icon'] ?? 'maintenance'}',
    custom: r['custom'] == true,
  );

  final String id;
  final String en;
  final String ar;
  final String examplesEn;
  final String examplesAr;
  final String icon;

  /// "Custom service": the person names the service themselves.
  final bool custom;

  String name(String lang) => lang == 'ar' && ar.isNotEmpty ? ar : en;
  String examples(String lang) => lang == 'ar' && examplesAr.isNotEmpty ? examplesAr : examplesEn;
}

/// The order a request moves through. Rejected and cancelled sit outside it.
const serviceFlow = ['pending', 'under_review', 'accepted', 'in_progress', 'completed'];

/// An update the customer may see: never the team's internal notes.
class ServiceEvent {
  const ServiceEvent({required this.at, required this.kind, this.status, this.note, this.byCustomer = false});

  factory ServiceEvent.fromRow(Map<String, Object?> r) => ServiceEvent(
    at: DateTime.tryParse('${r['at']}')?.toLocal() ?? DateTime.now(),
    kind: '${r['kind'] ?? ''}',
    status: r['status'] as String?,
    note: (r['note'] as String?)?.trim().isEmpty ?? true ? null : (r['note'] as String).trim(),
    byCustomer: r['by'] == 'customer',
  );

  final DateTime at;

  /// created, status or note.
  final String kind;
  final String? status;
  final String? note;
  final bool byCustomer;
}

/// One of the signed-in person's requests (my_service_requests()).
class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.ref,
    required this.status,
    required this.categoryId,
    required this.categoryEn,
    required this.categoryAr,
    required this.icon,
    required this.description,
    required this.cityId,
    required this.address,
    required this.preferredDate,
    required this.preferredWindow,
    required this.urgency,
    required this.createdAt,
    required this.cancellable,
    required this.events,
    this.customService,
    this.governorateId,
    this.neighborhoodId,
    this.photos = const [],
    this.lat,
    this.lng,
  });

  factory ServiceRequest.fromRow(Map<String, Object?> r) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    return ServiceRequest(
      id: '${r['id']}',
      ref: '${r['ref'] ?? ''}',
      status: '${r['status'] ?? 'pending'}',
      categoryId: '${r['category_id'] ?? ''}',
      categoryEn: '${r['category_en'] ?? ''}',
      categoryAr: '${r['category_ar'] ?? ''}',
      icon: '${r['icon'] ?? 'maintenance'}',
      customService: r['custom_service'] as String?,
      description: '${r['description'] ?? ''}',
      governorateId: r['governorate_id'] as String?,
      cityId: '${r['city_id'] ?? ''}',
      neighborhoodId: r['neighborhood_id'] as String?,
      address: '${r['address'] ?? ''}',
      lat: d(r['lat']),
      lng: d(r['lng']),
      preferredDate: DateTime.tryParse('${r['preferred_date']}') ?? DateTime.now(),
      preferredWindow: '${r['preferred_window'] ?? 'any'}',
      urgency: '${r['urgency'] ?? 'normal'}',
      photos: [for (final p in (r['photos'] as List?) ?? const []) '$p'],
      createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
      cancellable: r['cancellable'] == true,
      events: [
        for (final e in (r['events'] as List?) ?? const [])
          if (e is Map) ServiceEvent.fromRow(Map<String, Object?>.from(e)),
      ],
    );
  }

  final String id;

  /// SR-000123: what people quote on the phone.
  final String ref;
  final String status;
  final String categoryId;
  final String categoryEn;
  final String categoryAr;
  final String icon;
  final String? customService;
  final String description;
  final String? governorateId;
  final String cityId;
  final String? neighborhoodId;
  final String address;
  final double? lat;
  final double? lng;
  final DateTime preferredDate;

  /// morning, afternoon, evening or any.
  final String preferredWindow;

  /// normal, urgent or emergency.
  final String urgency;
  final List<String> photos;
  final DateTime createdAt;

  /// Until work begins: pending, under review or accepted.
  final bool cancellable;
  final List<ServiceEvent> events;

  String title(String lang) => (customService?.trim().isNotEmpty ?? false)
      ? customService!.trim()
      : (lang == 'ar' && categoryAr.isNotEmpty ? categoryAr : categoryEn);

  /// Where it is in [serviceFlow], or -1 when rejected or cancelled.
  int get step => serviceFlow.indexOf(status);

  bool get open => const {'pending', 'under_review', 'accepted', 'in_progress'}.contains(status);

  /// The team's latest note for the customer, if any.
  String? get teamNote {
    for (final e in events.reversed) {
      if (e.note != null && !e.byCustomer) return e.note;
    }
    return null;
  }
}

/// What create_service_request() refused, as a key the form explains next to
/// the field it is about: a field name (description, city_id, …), or
/// sign_in, too_many, not_set_up, photo_type, photo_size, network, other.
class ServiceRefusal implements Exception {
  const ServiceRefusal(this.code);
  final String code;

  /// The field it is about, when it is about one.
  String? get field => code.startsWith('invalid:') ? code.substring(8) : null;

  @override
  String toString() => 'ServiceRefusal($code)';
}

/// The created request: its reference, and whether this was a retry of one
/// already sent.
typedef ServiceCreated = ({String id, String ref, bool duplicate});
