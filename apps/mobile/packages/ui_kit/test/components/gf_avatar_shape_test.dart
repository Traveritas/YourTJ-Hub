import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../helpers.dart';

/// Effective clip path of [node] in its own coordinates, or null when the
/// render object does not clip its child.
Path? effectiveClipPath(RenderObject node) {
  if (node is RenderClipPath) {
    return node.clipper?.getClip(node.size) ??
        (Path()..addRect(Offset.zero & node.size));
  }
  if (node is RenderPhysicalShape) {
    return node.clipper?.getClip(node.size) ??
        (Path()..addRect(Offset.zero & node.size));
  }
  if (node is RenderClipOval) {
    final Rect oval =
        node.clipper?.getClip(node.size) ?? (Offset.zero & node.size);
    return Path()..addOval(oval);
  }
  if (node is RenderClipRRect) {
    return Path()..addRRect(
      node.clipper?.getClip(node.size) ??
          node.borderRadius
              .resolve(node.textDirection)
              .toRRect(Offset.zero & node.size),
    );
  }
  if (node is RenderClipRect) {
    return Path()..addRect(Offset.zero & node.size);
  }
  return null;
}

/// Verifies the rendered clip geometry rather than one node's configuration:
/// every clip applied to the avatar — inside [GfAvatar] and from any ancestor
/// wrapper, whether [ClipPath], [PhysicalShape] or the oval/rect clips — must
/// accept 24 sample points on the avatar's inscribed circle (95% of the
/// radius, in global coordinates). A circular clip accepts all of them; a
/// polygon clip — for example the repo's historical six-point hexagon clipper
/// — rejects the directions that fall outside its edges (issue #877 review).
void expectCircularClipGeometry(WidgetTester tester, Finder avatarFinder) {
  final RenderObject avatar = tester.renderObject(avatarFinder);
  final Rect avatarRect = tester.getRect(avatarFinder);
  final List<Path> clips = <Path>[];

  void collect(RenderObject node) {
    final Path? path = effectiveClipPath(node);
    if (path != null) {
      clips.add(path.transform(node.getTransformTo(null).storage));
    }
    node.visitChildren(collect);
  }

  collect(avatar);
  for (RenderObject? node = avatar.parent; node != null; node = node.parent) {
    final Path? path = effectiveClipPath(node);
    if (path != null) {
      clips.add(path.transform(node.getTransformTo(null).storage));
    }
  }

  expect(clips, isNotEmpty, reason: 'the avatar must be clipped');
  final double radius = avatarRect.size.shortestSide / 2 * 0.95;
  for (final Path clip in clips) {
    for (int step = 0; step < 24; step++) {
      final double angle = step * math.pi / 12;
      final Offset point =
          avatarRect.center + Offset(math.cos(angle), math.sin(angle)) * radius;
      expect(
        clip.contains(point),
        isTrue,
        reason:
            'every clip over the avatar must accept the inscribed circle; a '
            'clip rejects $point (${step * 15}°)',
      );
    }
  }
}

/// Asserts the shared circular-avatar contract: the decoration is a circle,
/// the child is clipped to it, neither size nor ring drifts, and the painted
/// region really is circular.
///
/// Regression guard for issue #877 (DM avatars reported as hexagons): the
/// clip shape must survive every avatar refactor.
void expectCircularAvatar(
  WidgetTester tester,
  Finder avatarFinder, {
  required double size,
  required bool ring,
}) {
  final GfAvatar avatar = tester.widget<GfAvatar>(avatarFinder);
  expect(avatar.size, size);
  expect(avatar.ring, ring);

  final Finder containerFinder = find
      .descendant(of: avatarFinder, matching: find.byType(Container))
      .first;
  final Container container = tester.widget<Container>(containerFinder);
  final BoxDecoration decoration = container.decoration! as BoxDecoration;
  expect(
    decoration.shape,
    BoxShape.circle,
    reason: 'DM avatars must stay circular (issue #877)',
  );
  expect(
    container.clipBehavior,
    Clip.antiAlias,
    reason: 'the image must be clipped to the circular decoration',
  );
  expect(
    decoration.border,
    isNull,
    reason: 'the clip must not inset its image',
  );
  final foreground = container.foregroundDecoration as BoxDecoration?;
  expect(foreground?.border, ring ? isNotNull : isNull);
  expect(tester.getSize(avatarFinder), Size(size, size));
  expect(
    find.descendant(of: avatarFinder, matching: find.byType(CustomPaint)),
    findsNothing,
    reason:
        'a custom painter inside the avatar could draw a non-circular shape',
  );
  expectCircularClipGeometry(tester, avatarFinder);
}

void main() {
  testWidgets('ring does not inset the square image inside the outer circle', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(
        const GfAvatar(
          src: 'https://example.test/avatar.png',
          size: 40,
          ring: true,
        ),
      ),
    );
    // An inset square clipped by the larger outer circle has flat sides: the
    // reported polygon appearance. The image must cover the full clip; the
    // ring paints on top of that circle instead of adding content padding.
    expect(tester.getSize(find.byType(Image)), const Size(40, 40));
  });

  testWidgets('GfAvatar keeps every DM size circular and clipped', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(
        const Column(
          children: <Widget>[
            GfAvatar(src: '', size: 32),
            GfAvatar(src: '', size: 36, ring: true),
            GfAvatar(src: '', size: 40, ring: true),
          ],
        ),
      ),
    );

    expectCircularAvatar(
      tester,
      find.byType(GfAvatar).at(0),
      size: 32,
      ring: false,
    );
    expectCircularAvatar(
      tester,
      find.byType(GfAvatar).at(1),
      size: 36,
      ring: true,
    );
    expectCircularAvatar(
      tester,
      find.byType(GfAvatar).at(2),
      size: 40,
      ring: true,
    );
  });

  testWidgets('GfAvatar clips a loaded image to the circular decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(const GfAvatar(src: 'https://example.test/avatar.png', size: 32)),
    );

    final Finder avatarFinder = find.byType(GfAvatar);
    expectCircularAvatar(tester, avatarFinder, size: 32, ring: false);
    expect(
      find.descendant(of: avatarFinder, matching: find.byType(Image)),
      findsOneWidget,
    );
  });

  testWidgets('conversation list row keeps the circular 40px ring avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      gfApp(
        const SizedBox(
          width: 320,
          child: GfConversationRow(
            avatarUrl: '',
            name: 'Bob',
            lastMessage: '你好',
            time: '10:30',
            unreadCount: 0,
          ),
        ),
      ),
    );

    final Finder avatarFinder = find.descendant(
      of: find.byType(GfConversationRow),
      matching: find.byType(GfAvatar),
    );
    expect(avatarFinder, findsOneWidget);
    expectCircularAvatar(tester, avatarFinder, size: 40, ring: true);
  });
}
