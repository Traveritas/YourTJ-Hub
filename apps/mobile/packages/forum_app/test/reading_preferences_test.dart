import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/src/reading_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults to 100% when nothing is stored', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(contentFontScaleProvider), 1);
    await pumpEventQueue();
    expect(container.read(contentFontScaleProvider), 1);
  });

  test('persists the reader preference and restores it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(contentFontScaleProvider.notifier).setScale(1.3);
    expect(container.read(contentFontScaleProvider), 1.3);
    await pumpEventQueue();
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        ContentFontScaleNotifier.prefsKey,
      ),
      1.3,
    );

    SharedPreferences.setMockInitialValues(<String, Object>{
      ContentFontScaleNotifier.prefsKey: 1.3,
    });
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(contentFontScaleProvider);
    await pumpEventQueue();
    expect(restored.read(contentFontScaleProvider), 1.3);
  });

  test('clamps out-of-range values, including restored ones', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(contentFontScaleProvider.notifier);

    notifier.setScale(.1);
    expect(container.read(contentFontScaleProvider), .8);
    notifier.setScale(9);
    expect(container.read(contentFontScaleProvider), 1.4);
    notifier.resetToDefault();
    expect(container.read(contentFontScaleProvider), 1);

    // Flush queued writes before replacing the mock store; otherwise the
    // earlier 100% write lands in the fresh store and hides the restore path.
    await pumpEventQueue();
    SharedPreferences.setMockInitialValues(<String, Object>{
      ContentFontScaleNotifier.prefsKey: 3,
    });
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(contentFontScaleProvider);
    await pumpEventQueue();
    expect(restored.read(contentFontScaleProvider), 1.4);
  });

  test('the last choice wins even when writes are still in flight', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(contentFontScaleProvider.notifier);

    notifier.setScale(1.4);
    notifier.setScale(.9);
    await pumpEventQueue();
    expect(container.read(contentFontScaleProvider), .9);
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        ContentFontScaleNotifier.prefsKey,
      ),
      .9,
    );
  });
}
