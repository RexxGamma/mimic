import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimic/appcolors.dart';

import 'appcolors.dart';
import 'track.dart';
import 'Backend/queuemanager.dart';
import '3dotsmanager.dart';
import 'Backend/metadatamanager.dart';

// ─────────────────────────────────────────────────────────────────────
//  Ruta transparente. La pantalla anterior se ve por debajo de la Queue.
//  Igual que PlayerRoute: slide-up al entrar, drag-down para salir.
// ─────────────────────────────────────────────────────────────────────
class QueueRoute extends PageRouteBuilder {
  factory QueueRoute() => QueueRoute._();

  QueueRoute._()
    : super(
        opaque: false,
        barrierColor: null,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const Queuewidget(),
      );

  @override
  Widget buildTransitions(_, animation, __, child) {
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    );
  }
}

Future<void> showQueueSheet(BuildContext context) {
  return Navigator.of(context).push(QueueRoute());
}

class Queuewidget extends StatefulWidget {
  const Queuewidget({super.key});

  @override
  State<Queuewidget> createState() => _QueuewidgetState();
}

class _QueuewidgetState extends State<Queuewidget>
    with SingleTickerProviderStateMixin {
  final _manager = QueueManager.instance;

  // ── Drag (idéntico al Player) ─────────────────────────────────────
  late final AnimationController _drag;
  final ScrollController _scroll = ScrollController();
  double _startY = 0;
  double _lastY = 0;
  bool _dragging = false;

  // ── Reorder flag (para no rebotar mientras reordenas) ─────────────
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _drag = AnimationController.unbounded(vsync: this);
    SongContextManager.push(SongSource.queue);
    QueueManager.instance.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    QueueManager.instance.removeListener(_onQueueChanged);
    _drag.dispose();
    _scroll.dispose();
    SongContextManager.pop();
    super.dispose();
  }

  void _onQueueChanged() {
    if (_reordering) return;
    if (!mounted) return;
    setState(() {});
  }

  bool get _atTop => !_scroll.hasClients || _scroll.position.pixels <= 0;

  void _onDown(PointerDownEvent e) {
    if (_drag.isAnimating) _drag.stop();
    _lastY = e.position.dy;
    _dragging = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (_reordering) return;

    final y = e.position.dy;
    if (!_dragging && _atTop && y > _lastY + 1) {
      _dragging = true;
      _startY = y;
      _drag.value = 0;
      HapticFeedback.selectionClick();
    }
    if (_dragging) {
      _drag.value = (y - _startY).clamp(0.0, double.infinity);
    }
    _lastY = y;
  }

  void _release() {
    if (!_dragging) return;
    _dragging = false;
    final h = MediaQuery.of(context).size.height;

    if (_drag.value > 120) {
      HapticFeedback.mediumImpact();
      _drag
          .animateTo(
            h,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) Navigator.of(context).pop();
          });
    } else {
      _drag.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _drag,
        builder: (_, child) {
          // Cuanto más arrastras, menos radio → la hoja se "despega".
          final radius = (24 - (_drag.value / 30)).clamp(0.0, 24.0);
          return Transform.translate(
            offset: Offset(0, _drag.value),
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: child,
            ),
          );
        },
        child: _buildSheet(context),
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHandle(),
              _buildHeader(),
              _buildNowPlaying(),
              _buildQueueHeader(),
              Expanded(child: _buildQueueList()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Handle (barrita superior) ─────────────────────────────────────
  Widget _buildHandle() {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _dragging ? 0.7 : 1.0,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header: "Queue" + contador ───────────────────────────────────
  Widget _buildHeader() {
    final count = _manager.queue.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          const Text(
            'Queue',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Now Playing (card destacado) ─────────────────────────────────
  Widget _buildNowPlaying() {
    return ListenableBuilder(
      listenable: Metadatamanager.instance,
      builder: (_, __) {
        final song = Metadatamanager.instance.currentSong;
        if (song == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    _PlayingIndicator(color: AppColors.accent),

                    SizedBox(width: 8),
                    Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
                child: Onesong(
                  song: song,
                  thredots: true,
                  hideplayingnow: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── "UP NEXT" con separador tipográfico ──────────────────────────
  Widget _buildQueueHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          Text(
            'UP NEXT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }

  // ── Lista ────────────────────────────────────────────────────────
  Widget _buildQueueList() {
    final queue = _manager.queue;
    if (queue.isEmpty) return _buildEmptyState();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ReorderableListView.builder(
        key: const PageStorageKey('queue_list'),
        scrollController: _scroll,
        padding: const EdgeInsets.only(bottom: 12),
        onReorderStart: (_) {
          HapticFeedback.selectionClick();
          _reordering = true;
        },
        onReorderEnd: (_) {
          _reordering = false;
          if (mounted) setState(() {});
        },
        onReorder: (o, n) => _manager.reorder(o, n),
        itemCount: queue.length,
        itemBuilder: (context, i) {
          final song = queue[i];
          return Padding(
            key: ValueKey(song.id),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Onesong(song: song, index: i),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 44,
            color: Colors.white.withOpacity(0.18),
          ),
          const SizedBox(height: 12),
          Text(
            'Your queue is empty',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Songs you add will appear here',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tres barritas animadas estilo "now playing".
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({
    this.color,
    this.barWidth = 2.5,
    this.height = 12,
    this.width = 12,
  });

  final Color? color; // si null → colorScheme.primary (fallback)
  final double barWidth;
  final double height;
  final double width;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();

    SongContextManager.push(SongSource.queue);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    SongContextManager.pop();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value + i * 0.3) % 1.0;
              final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
              final h = widget.height * 0.25 + t * widget.height * 0.58;
              return Container(
                width: widget.barWidth,
                height: h,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
