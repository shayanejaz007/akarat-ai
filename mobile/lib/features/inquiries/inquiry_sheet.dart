import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/buttons.dart';
import '../../shared/models/listing.dart';
import '../../shared/repositories/account_repositories.dart';
import '../../shared/services/supabase_providers.dart';
import 'inquiries_providers.dart';

/// Opens the inquiry form for [listing]. Resolves true when one was sent.
Future<bool> showInquirySheet(BuildContext context, Listing listing) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => InquirySheet(listing: listing),
  );
  return sent ?? false;
}

class InquirySheet extends ConsumerStatefulWidget {
  const InquirySheet({super.key, required this.listing});
  final Listing listing;

  @override
  ConsumerState<InquirySheet> createState() => _InquirySheetState();
}

class _InquirySheetState extends ConsumerState<InquirySheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _phone = TextEditingController();
  late final TextEditingController _message;
  String? _error;
  bool _sent = false;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    final meta = user?.userMetadata;
    _name = TextEditingController(text: (meta?['full_name'] as String?) ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    // An account with a sign-in number can be called back on it.
    _phone.text = Phone.display(user?.phone);
    _message = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_message.text.isEmpty) {
      _message.text = context.l10n.inquiryDefaultMessage(widget.listing.title(context.lang));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_sent) return;
    final l = context.l10n;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_email.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      setState(() => _error = l.inquiryNeedContact);
      return;
    }
    try {
      await ref
          .read(inquiriesRepositoryProvider)
          .send(
            propertyId: widget.listing.id,
            ownerId: widget.listing.ownerId,
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            message: _message.text,
          );
      _sent = true;
      ref.invalidate(sentInquiriesProvider);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = context.failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.inquiryTitle, style: context.text.titleLarge),
              const SizedBox(height: Space.xxs),
              Text(l.inquiryBody, style: context.text.bodySmall),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                maxLength: 120,
                decoration: InputDecoration(labelText: l.inquiryName, counterText: ''),
                validator: (v) => (v ?? '').trim().isEmpty ? l.validationRequired : null,
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                maxLength: 200,
                decoration: InputDecoration(labelText: l.inquiryEmail, counterText: ''),
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty || _emailRe.hasMatch(t) ? null : l.validationEmail;
                },
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                maxLength: 24,
                decoration: InputDecoration(labelText: l.inquiryPhone, counterText: '', hintText: '07X XXX XXXX'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty || Phone.dialable(t) != null ? null : l.validationPhone;
                },
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _message,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(labelText: l.inquiryMessage, alignLabelWithHint: true),
                validator: (v) => (v ?? '').trim().isEmpty ? l.validationRequired : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: context.text.bodySmall?.copyWith(color: c.danger)),
                ),
              ],
              const SizedBox(height: Space.md),
              BusyButton(label: l.inquirySend, busyLabel: l.inquirySending, icon: Icons.send_rounded, onPressed: _send),
            ],
          ),
        ),
      ),
    );
  }
}
