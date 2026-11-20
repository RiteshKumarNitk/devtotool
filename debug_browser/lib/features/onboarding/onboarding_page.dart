import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branding/logo_painter.dart';
import '../../core/browser_settings.dart';
import '../../core/extensions.dart';
import '../../core/home_stats.dart';
import '../newtab/aurora_background.dart';

/// Shows onboarding on first launch, otherwise [child].
class FirstRunGate extends ConsumerWidget {
  final Widget child;
  const FirstRunGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(onboardedProvider) ? child : OnboardingPage(next: child);
}

class OnboardingPage extends ConsumerStatefulWidget {
  final Widget next;
  const OnboardingPage({super.key, required this.next});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;
  bool? _isDefault;
  static const _count = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _count - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _finish() => ref.read(onboardedProvider.notifier).complete();

  Future<void> _makeDefault() async {
    final ok = await SystemBrowser.requestDefault();
    if (mounted) setState(() => _isDefault = ok);
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _count - 1;
    return Scaffold(
      body: AuroraBackground(
        theme: NewTabTheme.aurora,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: last ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed: last ? null : _finish,
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    child: const Text('Skip'),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    const _WelcomeStep(),
                    const _PrivacyStep(),
                    const _SearchStep(),
                    _DefaultStep(isDefault: _isDefault, onMakeDefault: _makeDefault),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(
                  children: [
                    for (var i = 0; i < _count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: BrandColors.deep,
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      ),
                      onPressed: _next,
                      child: Text(last ? 'Start browsing' : 'Next',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final Widget art;
  final String title;
  final String body;
  final Widget? extra;
  const _Step({required this.art, required this.title, required this.body, this.extra});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Center(child: art),
            const SizedBox(height: 32),
            Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 12),
            Text(body, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.45)),
            if (extra != null) ...[const SizedBox(height: 20), extra!],
          ],
        ),
      );
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) => _Step(
        art: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 1400),
          builder: (context, t, _) => SizedBox(
            width: 160,
            height: 160,
            child: CustomPaint(
              painter: LogoPainter(
                outline: Curves.easeInOutCubic.transform((t / 0.5).clamp(0, 1)),
                spin: Curves.easeOutBack.transform(((t - 0.2) / 0.5).clamp(0, 1)),
                badge: Curves.elasticOut.transform(((t - 0.5) / 0.5).clamp(0, 1)),
              ),
            ),
          ),
        ),
        title: 'Welcome to\nDebug Browser',
        body: 'A fast, private browser with real developer tools built in: console, network, '
            'storage and more for any page you open.',
      );
}

class _PrivacyStep extends ConsumerWidget {
  const _PrivacyStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = ref.watch(extensionsProvider);
    final n = ref.read(extensionsProvider.notifier);
    Widget toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => Card(
          color: Colors.white.withValues(alpha: 0.12),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          child: SwitchListTile(
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
            value: value,
            onChanged: onChanged,
          ),
        );
    return _Step(
      art: const Icon(Icons.shield, size: 120, color: Color(0xFF69F0AE)),
      title: 'Browse without\nads and trackers',
      body: 'Ads and tracking scripts are blocked on every site, so pages load faster and follow you less.',
      extra: Column(children: [
        toggle('Block ads & trackers', 'Recommended', ext.blocker, (v) => n.update((x) => x.copyWith(blocker: v))),
        toggle('Hide cookie banners', 'Fewer pop-ups', ext.cookies, (v) => n.update((x) => x.copyWith(cookies: v))),
        toggle('Dark mode for websites', 'Easier on the eyes at night', ext.dark,
            (v) => n.update((x) => x.copyWith(dark: v))),
      ]),
    );
  }
}

class _SearchStep extends ConsumerWidget {
  const _SearchStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(browserSettingsProvider).engine;
    return _Step(
      art: const Icon(Icons.travel_explore, size: 110, color: Color(0xFF80D8FF)),
      title: 'Choose your\nsearch engine',
      body: 'Used when you type in the address bar. You can change it any time in Settings.',
      extra: Column(children: [
        for (final e in SearchEngine.values)
          Card(
            color: Colors.white.withValues(alpha: e == engine ? 0.22 : 0.10),
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(e == engine ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Colors.white),
              title: Text(e.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onTap: () => ref.read(browserSettingsProvider.notifier).update((s) => s.copyWith(engine: e)),
            ),
          ),
      ]),
    );
  }
}

class _DefaultStep extends StatelessWidget {
  final bool? isDefault;
  final VoidCallback onMakeDefault;
  const _DefaultStep({required this.isDefault, required this.onMakeDefault});

  @override
  Widget build(BuildContext context) => _Step(
        art: const Icon(Icons.open_in_browser, size: 110, color: Color(0xFFFFD180)),
        title: 'Make it your\ndefault browser',
        body: 'Links you tap in other apps, like messages and email, will open here with ads and '
            'trackers blocked.',
        extra: isDefault == true
            ? const Row(children: [
                Icon(Icons.check_circle, color: Color(0xFF69F0AE)),
                SizedBox(width: 8),
                Text('Debug Browser is your default browser', style: TextStyle(color: Colors.white)),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onPressed: onMakeDefault,
                    icon: const Icon(Icons.check),
                    label: const Text('Set as default browser'),
                  ),
                  if (isDefault == false)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('Not changed. You can do this later in Settings.',
                          style: TextStyle(color: Colors.white70)),
                    ),
                ],
              ),
      );
}
