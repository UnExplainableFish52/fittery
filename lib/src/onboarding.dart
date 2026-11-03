import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controller.dart';
import 'models.dart';

/// One welcome flow for startup and Settings. Artwork is decorative; all copy is native.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.c,
    required this.onFinished,
    this.replay = false,
  });
  final BatteryController c;
  final VoidCallback onFinished;
  final bool replay;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver, RestorationMixin {
  final _page = RestorableInt(0);
  final _visited = RestorableInt(0);
  late final _dontShow = RestorableBool(
    !widget.c.onboardingCompleted || !widget.c.showOnboardingOnLaunch,
  );
  late final _waits = List.generate(
    4,
    (_) => RestorableInt(widget.replay ? 0 : 3),
  );
  Timer? _timer;
  bool _active = true, _saving = false, _accessible = false;
  String? _error;
  static const _art = ['welcome', 'features', 'forever', 'setup'];
  static const _titles = [
    'Welcome to Fittery!',
    'Powerful features. Zero clutter.',
    'Sounds too good to be true?',
    "You're all set!",
  ];
  static const _buttons = [
    'Tell me more',
    "Okay, that's awesome!",
    "There's more?",
    "Let's get started!",
  ];

  @override
  String? get restorationId =>
      widget.replay ? 'welcome_replay' : 'welcome_launch';

  @override
  void initState() {
    super.initState();
    widget.c.setOnboardingVisible(true);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_page, 'page');
    registerForRestoration(_visited, 'viewed');
    registerForRestoration(_dontShow, 'dont_show_again');
    for (var i = 0; i < 4; i++) {
      registerForRestoration(_waits[i], 'remaining_$i');
    }
    _page.value = _page.value.clamp(0, 3);
    _visited.value |= 1 << _page.value;
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    if (accessible != _accessible) {
      _accessible = accessible;
      if (accessible) {
        for (final wait in _waits) {
          wait.value = 0;
        }
      }
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_active ||
        widget.replay ||
        _accessible ||
        _waits[_page.value].value <= 0) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_active) {
        timer.cancel();
        return;
      }
      setState(
        () => _waits[_page.value].value = math.max(
          0,
          _waits[_page.value].value - 1,
        ),
      );
      if (_waits[_page.value].value == 0) timer.cancel();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _go(int page, {bool bypassWait = false}) {
    if (_saving || page == _page.value) return;
    setState(() {
      final seen = _visited.value & (1 << page) != 0;
      if (seen || bypassWait || widget.replay || _accessible) {
        _waits[page].value = 0;
      }
      _visited.value |= 1 << page;
      _page.value = page;
      _error = null;
    });
    _schedule();
  }

  Future<void> _continue() async {
    if (_saving || _waits[_page.value].value > 0) return;
    if (_page.value < 3) {
      _go(_page.value + 1);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.c.completeOnboarding(dontShowAgain: _dontShow.value);
      if (mounted) widget.onFinished();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PlatformException
              ? e.message ??
                    'Your preference could not be saved. Please try again.'
              : 'Your preference could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _page.dispose();
    _visited.dispose();
    _dontShow.dispose();
    for (final wait in _waits) {
      wait.dispose();
    }
    widget.c.setOnboardingVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final page = _page.value;
    final remaining = _waits[page].value;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: page == 0 && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && page > 0 && !_saving) _go(page - 1);
      },
      child: Scaffold(
        key: const ValueKey('welcome-tutorial'),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(.4, -.65),
              radius: 1.1,
              colors: [
                (page == 2 ? const Color(0xFF8470DC) : mint).withValues(
                  alpha: dark ? .12 : .08,
                ),
                scheme.surface,
              ],
              stops: const [0, .85],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Row(
                        children: [
                          if (page > 0 || widget.replay)
                            IconButton(
                              key: const ValueKey('onboarding-back'),
                              tooltip: page == 0
                                  ? 'Close tutorial'
                                  : 'Previous page',
                              onPressed: _saving
                                  ? null
                                  : () {
                                      if (page > 0) {
                                        _go(page - 1);
                                      } else {
                                        Navigator.maybePop(context);
                                      }
                                    },
                              icon: Icon(
                                page == 0
                                    ? Icons.close_rounded
                                    : Icons.arrow_back_rounded,
                              ),
                            )
                          else
                            const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.asset(
                                    'fittery_app_drawer_512.png',
                                    width: 25,
                                    height: 25,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                const Flexible(
                                  child: Text(
                                    'Fittery',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      letterSpacing: -.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (page < 3)
                            TextButton(
                              key: const ValueKey('onboarding-skip'),
                              onPressed: _saving
                                  ? null
                                  : () => _go(3, bypassWait: true),
                              child: Semantics(
                                label: 'Skip to the final setup page',
                                child: const ExcludeSemantics(
                                  child: Text('Skip'),
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 12, height: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bounds) {
                          final artHeight =
                              (bounds.maxHeight *
                                      switch (page) {
                                        1 => .44,
                                        2 => .58,
                                        _ => .70,
                                      })
                                  .clamp(
                                    page == 1 ? 170.0 : 220.0,
                                    page == 1 ? 300.0 : 440.0,
                                  );
                          return SingleChildScrollView(
                            key: ValueKey('onboarding-scroll-$page'),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey('onboarding-slide-$page'),
                              tween: Tween(
                                begin: reducedMotion ? 1 : 0,
                                end: 1,
                              ),
                              duration: reducedMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              builder: (context, progress, child) =>
                                  Transform.translate(
                                    offset: Offset(0, 8 * (1 - progress)),
                                    child: Opacity(
                                      opacity: progress,
                                      child: child,
                                    ),
                                  ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: artHeight,
                                    width: double.infinity,
                                    child: Image.asset(
                                      'assets/onboarding/${_art[page]}.webp',
                                      key: ValueKey('onboarding-art-$page'),
                                      fit: BoxFit.contain,
                                      cacheWidth: math.min(
                                        1024,
                                        (artHeight *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .ceil(),
                                      ),
                                      excludeFromSemantics: true,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Semantics(
                                    header: true,
                                    child: _headline(context, page),
                                  ),
                                  const SizedBox(height: 12),
                                  ..._copy(context, page),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: .94),
                        border: Border(
                          top: BorderSide(
                            color: scheme.onSurface.withValues(alpha: .06),
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: 'Page ${page + 1} of 4',
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  4,
                                  (i) => Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    width: i == page ? 24 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: i == page
                                          ? scheme.primary
                                          : scheme.onSurface.withValues(
                                              alpha: .18,
                                            ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (page == 3)
                            CheckboxListTile(
                              key: const ValueKey('onboarding-dont-show'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _dontShow.value,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(
                                      () => _dontShow.value = value ?? true,
                                    ),
                              title: const Text(
                                "Don't show this again",
                                style: TextStyle(fontSize: 14),
                              ),
                            )
                          else
                            const SizedBox(height: 18),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.error,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const ValueKey('onboarding-continue'),
                              onPressed: remaining > 0 || _saving
                                  ? null
                                  : _continue,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      remaining > 0
                                          ? 'Continue in ${remaining}s'
                                          : _buttons[page],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headline(BuildContext context, int page) {
    final prefix = switch (page) {
      0 => 'Welcome to ',
      1 => 'Powerful features. ',
      2 => 'Sounds ',
      _ => "You're ",
    };
    final highlight = switch (page) {
      1 => const Color(0xFF68D6F4),
      2 => const Color(0xFFC79BFF),
      _ => mint,
    };
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: TextStyle(
              color: page == 1
                  ? _keywordInk(context, mint)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          TextSpan(
            text: _titles[page].substring(prefix.length),
            style: TextStyle(color: _keywordInk(context, highlight)),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 32,
        height: 1.14,
        fontWeight: FontWeight.w800,
        letterSpacing: -.9,
      ),
    );
  }

  List<Widget> _copy(BuildContext context, int page) {
    final scheme = Theme.of(context).colorScheme;
    Widget tagline(String text, {Color? color}) => Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: color == null
            ? scheme.onSurfaceVariant
            : _keywordInk(context, color),
      ),
    );
    return switch (page) {
      0 => [
        tagline('Your battery. Your way.'),
        const SizedBox(height: 16),
        const _KeywordPills(
          items: [
            (Icons.bolt_rounded, 'Live readings', Color(0xFF68D6F4)),
            (Icons.notifications_active_outlined, 'Smart alarms', mint),
          ],
        ),
      ],
      1 => [const _FeatureTiles()],
      2 => [
        tagline("Let's add even more.", color: const Color(0xFFC79BFF)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [
                mint.withValues(alpha: .1),
                const Color(0xFFB58BEE).withValues(alpha: .12),
              ],
            ),
            border: Border.all(
              color: const Color(0xFFB58BEE).withValues(alpha: .25),
            ),
          ),
          child: Column(
            children: [
              const _GradientWords(
                'Free. Forever.',
                colors: [mint, Color(0xFF68D6F4)],
                size: 33,
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Icon(
                    Icons.code_rounded,
                    color: _keywordInk(context, const Color(0xFFC79BFF)),
                    size: 26,
                  ),
                  const _GradientWords(
                    'Open source.',
                    colors: [Color(0xFFC79BFF), Color(0xFFF89DDA)],
                    size: 26,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _KeywordPills(
          items: [
            (
              Icons.favorite_border_rounded,
              'Made with care',
              Color(0xFFF89DDA),
            ),
          ],
        ),
      ],
      _ => [
        tagline('Make it yours.', color: mint),
        const SizedBox(height: 16),
        const _KeywordPills(
          items: [
            (Icons.explore_outlined, 'Explore', Color(0xFF68D6F4)),
            (Icons.tune_rounded, 'Customize', Color(0xFFC79BFF)),
          ],
        ),
      ],
    };
  }
}

Color _keywordInk(BuildContext context, Color color) =>
    Theme.of(context).brightness == Brightness.dark
    ? color
    : Color.lerp(color, Colors.black, .50)!;

class _GradientWords extends StatelessWidget {
  const _GradientWords(this.text, {required this.colors, required this.size});
  final String text;
  final List<Color> colors;
  final double size;
  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => LinearGradient(
      colors: colors.map((color) => _keywordInk(context, color)).toList(),
    ).createShader(bounds),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1.1,
        letterSpacing: -.7,
      ),
    ),
  );
}

class _KeywordPills extends StatelessWidget {
  const _KeywordPills({required this.items});
  final List<(IconData, String, Color)> items;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: items
        .map(
          (item) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: item.$3.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: item.$3.withValues(alpha: .2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, size: 16, color: _keywordInk(context, item.$3)),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _keywordInk(context, item.$3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class _FeatureTiles extends StatelessWidget {
  const _FeatureTiles();
  static const _features = [
    (Icons.battery_charging_full_rounded, 'Full-charge alarm', mint),
    (Icons.battery_alert_rounded, 'Low-battery alarm', Color(0xFFE3B86A)),
    (Icons.thermostat_rounded, 'Temperature alerts', coral),
    (Icons.bolt_rounded, 'Live monitoring', Color(0xFF68D6F4)),
    (Icons.history_rounded, 'Battery logs', Color(0xFFC79BFF)),
    (Icons.insights_rounded, 'Beautiful graphs', mint),
    (Icons.notifications_active_outlined, 'Notifications', Color(0xFF68D6F4)),
    (Icons.music_note_rounded, 'Custom audio', Color(0xFFF89DDA)),
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final twoColumns =
          bounds.maxWidth >= 270 &&
          MediaQuery.textScalerOf(context).scale(13) <= 17;
      final width = twoColumns ? (bounds.maxWidth - 8) / 2 : bounds.maxWidth;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _features
            .map(
              (item) => Container(
                width: width,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      item.$3.withValues(alpha: .12),
                      item.$3.withValues(alpha: .035),
                    ],
                  ),
                  border: Border.all(color: item.$3.withValues(alpha: .2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      item.$1,
                      color: _keywordInk(context, item.$3),
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: _keywordInk(context, item.$3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    },
  );
}
