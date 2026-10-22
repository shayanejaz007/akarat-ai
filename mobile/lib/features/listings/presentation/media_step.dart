import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/listing_image.dart';
import '../../../core/widgets/state_views.dart';
import '../../../shared/models/listing.dart';
import '../../../shared/repositories/media_repository.dart';
import '../application/listing_wizard_controller.dart';
import '../domain/listing_draft.dart';

class MediaStep extends ConsumerStatefulWidget {
  const MediaStep({super.key, required this.editId});
  final String? editId;

  @override
  ConsumerState<MediaStep> createState() => _MediaStepState();
}

class _MediaStepState extends ConsumerState<MediaStep> {
  final _picker = ImagePicker();
  String? _error;
  bool _picking = false;

  ListingWizardController get _ctrl => ref.read(listingWizardProvider(widget.editId).notifier);
  List<DraftMedia> get _media => ref.read(listingWizardProvider(widget.editId)).draft.media;

  String _name(String path) => path.split(RegExp(r'[/\\]')).last;

  /// Checks a picked file against the same limits the bucket enforces.
  Future<String?> _reject(XFile f, {required bool video}) async {
    final l = context.l10n;
    if (MediaLimits.contentTypeFor(f.path, video: video) == null) return l.mediaUnsupported(_name(f.path));
    final size = await f.length();
    final cap = video ? MediaLimits.maxVideoBytes : MediaLimits.maxImageBytes;
    if (size > cap) return l.mediaTooLarge(_name(f.path), video ? 50 : 6);
    return null;
  }

  Future<void> _addPhotos() async {
    final l = context.l10n;
    final room = MediaLimits.maxFiles - _media.length;
    if (room <= 0) return setState(() => _error = l.mediaTooMany);
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      // Resized and re-encoded natively before the app sees them — the same
      // 1600 px / quality 85 the website applies in the browser — so a 12 MB
      // phone photo arrives at a few hundred kilobytes.
      final picked = await _picker.pickMultiImage(
        maxWidth: MediaLimits.maxEdge,
        maxHeight: MediaLimits.maxEdge,
        imageQuality: MediaLimits.jpegQuality,
        limit: room > 1 ? room : null,
      );
      final accepted = <DraftMedia>[];
      String? problem;
      for (final f in picked.take(room)) {
        final why = await _reject(f, video: false);
        if (why != null) {
          problem = why;
          continue;
        }
        accepted.add(DraftMedia(localPath: f.path, kind: MediaKind.image));
      }
      if (picked.length > room) problem = l.mediaTooMany;
      _ctrl.update((d) => d.copyWith(media: [...d.media, ...accepted]));
      setState(() => _error = problem);
    } on Object catch (e) {
      if (mounted) setState(() => _error = context.failureMessage(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addVideo() async {
    final l = context.l10n;
    if (_media.length >= MediaLimits.maxFiles) return setState(() => _error = l.mediaTooMany);
    if (_media.where((m) => m.isVideo).length >= MediaLimits.maxVideos) {
      return setState(() => _error = l.mediaTooManyVideos);
    }
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final f = await _picker.pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      final why = await _reject(f, video: true);
      if (why != null) return setState(() => _error = why);
      _ctrl.update(
        (d) => d.copyWith(
          media: [
            ...d.media,
            DraftMedia(localPath: f.path, kind: MediaKind.video),
          ],
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = context.failureMessage(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final media = ref.watch(listingWizardProvider(widget.editId).select((s) => s.draft.media));
    final full = media.length >= MediaLimits.maxFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.mediaHelp, style: context.text.bodySmall),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _picking || full ? null : _addPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(l.mediaAddPhotos),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _picking || full ? null : _addVideo,
                icon: const Icon(Icons.video_call_outlined),
                label: Text(l.mediaAddVideo),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          NoticeLine(icon: Icons.error_outline_rounded, text: _error!, tone: c.danger),
        ],
        const SizedBox(height: Space.md),
        if (media.isNotEmpty)
          SizedBox(
            height: 132,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              buildDefaultDragHandles: true,
              onReorderItem: (from, to) {
                final list = [...media];
                final item = list.removeAt(from);
                list.insert(to, item);
                _ctrl.update((d) => d.copyWith(media: list));
              },
              itemBuilder: (context, i) => Padding(
                key: ValueKey(media[i].localPath ?? media[i].stored?.url ?? i),
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: _Thumb(media: media[i], cover: i == 0, onRemove: () => _ctrl.removeMedia(i)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.media, required this.cover, required this.onRemove});
  final DraftMedia media;
  final bool cover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final Widget image;
    if (media.isVideo) {
      image = Container(
        color: const Color(0xFF101614),
        child: const Center(child: Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 36)),
      );
    } else if (media.stored != null) {
      image = ListingImage(url: media.stored!.url, decodeWidth: 120);
    } else {
      image = Image.file(File(media.localPath!), fit: BoxFit.cover, cacheWidth: 360);
    }
    return SizedBox(
      width: 120,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(borderRadius: Radii.field, child: image),
          ),
          if (cover)
            PositionedDirectional(
              bottom: 6,
              start: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: c.forest, borderRadius: Radii.chip),
                child: Text(l.mediaCover, style: context.text.labelSmall?.copyWith(color: c.onForest)),
              ),
            ),
          PositionedDirectional(
            top: 2,
            end: 2,
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: l.mediaRemove,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
