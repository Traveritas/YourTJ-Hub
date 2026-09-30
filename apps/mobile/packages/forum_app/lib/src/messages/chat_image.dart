import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../asset_url.dart';
import '../images/image_save.dart';
import '../providers.dart';
import '../server_messages.dart';

void _dismissExpiredImageRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
  });
}

/// Image messages contain a URL, never Markdown or arbitrary executable schemes.
bool isChatImageUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || value.contains('\\') || value.contains(RegExp(r'\s'))) {
    return false;
  }
  return (value.startsWith('/') && !value.startsWith('//')) ||
      ((uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty);
}

/// Conversation summaries currently carry only text, not the last message's
/// type. Recognize a whole image-file URL without hiding ordinary links or
/// text that merely mentions a filename. Queries do not determine file type.
bool isChatImagePreviewUrl(String value) {
  final url = value.trim();
  return isChatImageUrl(url) &&
      RegExp(
        r'\.(?:avif|bmp|gif|heic|heif|ico|jpe?g|png|svg|tiff?|webp)$',
        caseSensitive: false,
      ).hasMatch(Uri.parse(url).path);
}

class ChatImage extends ConsumerWidget {
  const ChatImage({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final resolved = resolveApiAssetUrl(url);
    return Semantics(
      button: true,
      label: l10n.imageViewPosition(1, 1),
      child: GestureDetector(
        onTap: () {
          final epoch = ref.read(offlineCacheEpochProvider);
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (context) => Consumer(
                builder: (context, ref, _) {
                  if (ref.watch(offlineCacheEpochProvider) != epoch) {
                    _dismissExpiredImageRoute(context);
                    return const SizedBox.shrink();
                  }
                  return Scaffold(
                    backgroundColor: Colors.black,
                    body: SafeArea(
                      child: GfImageViewer(
                        images: [resolved],
                        onSaveImage: (url) => saveImageFromUrl(context, url),
                        saveImageLabel: l10n.imageSave,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GfNetworkImage(
            resolved,
            width: 240,
            height: 180,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (context, _, _) => SizedBox(
              width: 240,
              height: 100,
              child: Center(child: Text(l10n.commonLoadFailed)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selection is previewed locally; only explicit send uploads it. Upload errors
/// retain the bytes for retry. The owning page enqueues the returned image URL.
class ChatImagePreview extends ConsumerStatefulWidget {
  const ChatImagePreview({
    super.key,
    required this.bytes,
    required this.ownerEpoch,
    required this.upload,
  });
  final Uint8List bytes;
  final int ownerEpoch;
  final Future<String> Function() upload;

  @override
  ConsumerState<ChatImagePreview> createState() => _ChatImagePreviewState();
}

class _ChatImagePreviewState extends ConsumerState<ChatImagePreview> {
  bool _uploading = false;
  Object? _error;

  bool get _current =>
      mounted && ref.read(offlineCacheEpochProvider) == widget.ownerEpoch;

  Future<void> _send() async {
    if (!_current || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await widget.upload();
      if (mounted && _current) Navigator.of(context).pop(url);
    } catch (error) {
      if (_current) setState(() => _error = error);
    } finally {
      if (_current) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (ref.watch(offlineCacheEpochProvider) != widget.ownerEpoch) {
      _dismissExpiredImageRoute(context);
      return const SizedBox.shrink();
    }
    return PopScope(
      canPop: !_uploading,
      child: AlertDialog(
        title: Text(l10n.messagesImage),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(widget.bytes, height: 240, fit: BoxFit.contain),
              if (_uploading) const LinearProgressIndicator(),
              if (_error != null) Text(resolveErrorMessage(l10n, _error!)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _uploading ? null : () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: _uploading ? null : _send,
            child: Text(_error == null ? l10n.commonSend : l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
