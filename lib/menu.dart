import 'package:flutter/material.dart';
import 'package:mimic/Backend/songdata.dart';
import 'package:mimic/searchmenu.dart';

import 'appcolors.dart';
import 'playing_trackui.dart';
import 'library.dart';
import 'Backend/providers/providermanager.dart';
import 'home.dart';
import 'settingsmenu.dart';

import 'package:provider/provider.dart';

import 'providerswap.dart';
import 'Backend/providers/privdersenums.dart';

int body = 0;
int _lastBody = body;
int _dir = 1;
bool showappbar = true;
var labelText = "Home";
final GlobalKey<MainMenuState> mainMenuKey = GlobalKey<MainMenuState>();

class MainMenu extends StatefulWidget {
  MainMenu({Key? key}) : super(key: mainMenuKey);

  @override
  State<MainMenu> createState() => MainMenuState();
}

class MainMenuState extends State<MainMenu> {
  SongInfo? previewplayerdata;
  bool showplayerpreviw = false;
  metadataprovider? _lastType;

  bool _isAppBarVisible = true;

  void updatepreviewplayer(SongInfo song) {
    setState(() {
      showplayerpreviw = true;
      previewplayerdata = song;
      print("UPDATED");
    });
  }

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MetadataProvider>();
    print('>>> BUILD with provider: ${mp.type.name}');

    if (_lastType != null && _lastType != mp.type) {
      _lastType = mp.type;
      WidgetsBinding.instance.addPostFrameCallback((_) {});
    } else if (_lastType == null) {
      _lastType = mp.type;
    }

    if (body != _lastBody) {
      _dir = body > _lastBody ? 1 : -1;
      _lastBody = body;
    }

    return Scaffold(
      backgroundColor: AppColors.background,

      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is! ScrollUpdateNotification) return false;

          // Solo responder a scroll vertical (ignora listas horizontales internas)
          final dir = notification.metrics.axisDirection;
          if (dir != AxisDirection.up && dir != AxisDirection.down) {
            return false;
          }

          final delta = notification.scrollDelta ?? 0;

          if (delta > 3 && _isAppBarVisible) {
            setState(() => _isAppBarVisible = false);
          } else if (delta < -3 && !_isAppBarVisible) {
            setState(() => _isAppBarVisible = true);
          }
          return false; // deja que la notificación siga propagándose
        },

        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // 1️⃣ CONTENIDO PRINCIPAL (con tus transiciones actuales)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(body);
                final begin = Offset((incoming ? _dir : -_dir) * 0.15, 0);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(body),
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  // Solo Search necesita hueco reservado:
                  // - Home / Library → 0 (contenido pasa por debajo del AppBar)
                  // - Search        → kToolbarHeight cuando el AppBar está visible
                  padding: EdgeInsets.only(
                    top: (showappbar && _isAppBarVisible && body == 1)
                        ? kToolbarHeight
                        : 0,
                  ),
                  child: getbody(() {
                    setState(() {
                      showappbar = false;
                    });
                  }),
                ),
              ),
            ),

            // 2️⃣ APPBAR ANIMADO (posicionado en la parte superior)
            if (showappbar)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  offset: _isAppBarVisible ? Offset.zero : const Offset(0, -1),
                  child: AppBar(
                    backgroundColor: AppColors.background,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    title: Text(
                      labelText,
                      style: TextStyle(color: AppColors.accent),
                    ),
                    actions: [
                      IconButton(
                        color: AppColors.text,
                        icon: const Icon(Icons.swap_horiz),
                        tooltip: 'change source',
                        onPressed: () async {
                          final picked = await showProviderSheet(context);
                          if (picked == null || !context.mounted) return;

                          await context.read<MetadataProvider>().switchTo(
                            picked,
                          );
                          if (!context.mounted) return;

                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Fuente: ${picked.name}'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SettingsMenu(),
                            ),
                          );
                        },
                        icon: Icon(Icons.settings),
                        color: AppColors.text2,
                        iconSize: 30,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            showplayerpreviw ? PlayingTrackui() : const SizedBox.shrink(),
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(
                  top: BorderSide(color: AppColors.bordier, width: 1),
                ),
              ),
              child: Row(
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    selected: body == 0,
                    onTap: () => setState(() {
                      labelText = "Home";
                      body = 0;
                      showappbar = true;
                      _isAppBarVisible = true;
                    }),
                  ),
                  _NavItem(
                    icon: Icons.search_rounded,
                    selected: body == 1,
                    onTap: () => setState(() {
                      labelText = "Search";
                      body = 1;
                      showappbar = true;
                      _isAppBarVisible = true;
                    }),
                  ),
                  _NavItem(
                    icon: Icons.album_rounded,
                    selected: body == 2,
                    onTap: () => setState(() {
                      labelText = "Library";
                      body = 2;
                      showappbar = true;
                      _isAppBarVisible = true;
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget menubody() => const HomeMenu();

Widget getbody(searchting) {
  switch (body) {
    case 0:
      return menubody();
    case 1:
      return Searchmenu(onsearch: searchting);
    case 2:
      return Playlistmenu();
    default:
      return MainMenu();
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withOpacity(0.06),
          highlightColor: Colors.white.withOpacity(0.04),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 24,
                color: selected ? AppColors.accent : AppColors.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
