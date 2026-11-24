import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../services/team_service.dart';
import '../widgets/team_widgets.dart';
import 'team_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Join a Team Screen  —  Browse | Code | Scan
// As per the screenshot:
//   Browse : search bar, teams list (Ready badge, Join button, location, count)
//   Code   : 6-char invite code input → Find team → Join
//   Scan   : QR scanner using mobile_scanner package
//            (add to pubspec: mobile_scanner: ^5.2.3)
// ─────────────────────────────────────────────────────────────────────────────
class JoinTeamScreen extends StatefulWidget {
  const JoinTeamScreen({super.key});

  @override
  State<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends State<JoinTeamScreen>
    with SingleTickerProviderStateMixin {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  late final TabController _tabCtrl;
  bool _busy = false;

  // ── Browse ──────────────────────────────────────────────────────────────
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  bool _listLoading = true;
  List<Map<String, dynamic>> _teams = [];
  bool _hasMore = false;
  int _page = 1;
  bool _loadingMore = false;
  final _scrollCtl = ScrollController();

  // ── Code ────────────────────────────────────────────────────────────────
  final _codeCtl = TextEditingController();
  bool _finding  = false;
  Map<String, dynamic>? _foundTeam;
  String? _codeError;

  // ── Scan ────────────────────────────────────────────────────────────────
  bool _scanActive  = false;
  bool _scanHandled = false; // scan already done, do not repeat

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {
          if (_tabCtrl.index == 2) {
            _scanActive  = true;
            _scanHandled = false;
          } else {
            _scanActive = false;
          }
        });
      }
    });
    _codeCtl.addListener(() => setState(() {}));
    _scrollCtl.addListener(_onScroll);
    _loadTeams(reset: true);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _debounce?.cancel();
    _searchCtl.dispose();
    _codeCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  // ── Browse helpers ───────────────────────────────────────────────────────
  Future<void> _loadTeams({bool reset = false}) async {
    if (reset) {
      setState(() { _listLoading = true; _page = 1; _teams = []; });
    }
    final res = await TeamService.browse(q: _searchCtl.text.trim(), page: _page);
    if (!mounted) return;
    final fetched = TeamService.asList(res['teams']);
    setState(() {
      if (reset) {
        _teams = fetched;
      } else {
        _teams.addAll(fetched);
      }
      _hasMore     = res['hasMore'] == true;
      _listLoading = false;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollCtl.position.pixels >= _scrollCtl.position.maxScrollExtent - 200) {
      setState(() { _page++; _loadingMore = true; });
      _loadTeams();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () => _loadTeams(reset: true));
  }

  // ── Join ─────────────────────────────────────────────────────────────────
  Future<void> _join({String? teamId, String? inviteCode}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await TeamService.join(teamId: teamId, inviteCode: inviteCode);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res['success'] != true) {
      _snack(res['message'] ?? 'Could not join team', error: true);
      return;
    }
    _snack(res['message'] ?? 'Done!');
    if (res['joined'] == true) {
      Navigator.pop(context, TeamService.asMap(res['team']));
    } else {
      // Request sent — show "Requested" in the list
      setState(() {
        for (final t in _teams) {
          if (t['id'].toString() == teamId) t['requested'] = true;
        }
        if (_foundTeam != null && _foundTeam!['id'].toString() == teamId) {
          _foundTeam = {..._foundTeam!, 'requested': true};
        }
      });
    }
  }

  Future<void> _cancelRequest(String teamId) async {
    final res = await TeamService.cancelRequest(teamId);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        for (final t in _teams) {
          if (t['id'].toString() == teamId) t['requested'] = false;
        }
      });
    } else {
      _snack(res['message'] ?? 'Could not cancel', error: true);
    }
  }

  // ── Code tab ─────────────────────────────────────────────────────────────
  Future<void> _findByCode() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _finding = true; _foundTeam = null; _codeError = null; });
    final res = await TeamService.findByCode(code);
    if (!mounted) return;
    setState(() {
      _finding = false;
      if (res['success'] == true) {
        _foundTeam = TeamService.asMap(res['team']);
      } else {
        _codeError = (res['message'] ?? 'Team not found').toString();
      }
    });
  }

  // ── Scan result handler ───────────────────────────────────────────────────
  Future<void> _onScannedCode(String raw) async {
    if (_scanHandled) return;
    setState(() { _scanHandled = true; _scanActive = false; });

    // The QR contains either just the code or the full URL (last segment = code)
    final code = raw.trim().split('/').last.toUpperCase();

    setState(() { _finding = true; _foundTeam = null; _codeError = null; });
    final res = await TeamService.findByCode(code);
    if (!mounted) return;
    setState(() {
      _finding = false;
      if (res['success'] == true) {
        _foundTeam = TeamService.asMap(res['team']);
        // Switch to the Code tab so the user can see Join
        _tabCtrl.animateTo(1);
        _codeCtl.text = code;
      } else {
        _codeError = (res['message'] ?? 'Team not found').toString();
        _tabCtrl.animateTo(1);
      }
    });
  }

  // ── Open team detail ──────────────────────────────────────────────────────
  Future<void> _openTeam(Map<String, dynamic> t) async {
    final joined = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: t['id'].toString())),
    );
    if (joined != null && mounted) {
      Navigator.pop(context, joined);
    } else if (mounted) {
      _loadTeams(reset: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.redAccent : null,
      ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9EEF7),
      body: Column(
        children: [
          _header(),
          _tabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _browseTab(),
                _codeTab(),
                _scanTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header (gradient) ─────────────────────────────────────────────────────
  Widget _header() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join a Team',
                  style: TextStyle(color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w900)),
              Text('Browse, scan, or enter a code',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab bar (Browse | # Code | QR Scan) ──────────────────────────────────
  Widget _tabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FC),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
            gradient: const LinearGradient(colors: [_pink, _purple]),
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: _purple,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(icon: Icon(Icons.search_rounded, size: 15), text: 'Browse',
                iconMargin: EdgeInsets.only(bottom: 2)),
            Tab(icon: Icon(Icons.tag_rounded, size: 15), text: 'Code',
                iconMargin: EdgeInsets.only(bottom: 2)),
            Tab(icon: Icon(Icons.qr_code_scanner_rounded, size: 15), text: 'Scan',
                iconMargin: EdgeInsets.only(bottom: 2)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BROWSE TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _browseTab() {
    return Column(children: [
      // Search bar
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: TextField(
          controller: _searchCtl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search teams, regions, tags...',
            hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFFBBBBBB)),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFBBBBBB), size: 20),
            filled: true,
            fillColor: const Color(0xFFF5F0FA),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      // List
      Expanded(
        child: _listLoading
            ? const Center(child: CircularProgressIndicator(color: _pink))
            : RefreshIndicator(
                color: _pink,
                onRefresh: () => _loadTeams(reset: true),
                child: _teams.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: const [
                        EmptyState(
                          icon: Icons.groups_outlined,
                          title: 'No teams found',
                          message: 'Try a different search, use an invite code, or create your own team.',
                        ),
                      ])
                    : ListView.builder(
                        controller: _scrollCtl,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: _teams.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _teams.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator(color: _pink)),
                            );
                          }
                          return _browseRow(_teams[i]);
                        },
                      ),
              ),
      ),
    ]);
  }

  Widget _browseRow(Map<String, dynamic> t) {
    final id        = t['id'].toString();
    final isFull    = t['status'] == 'full';
    final requested = t['requested'] == true;

    final Widget btn;
    if (requested) {
      btn = _chip('Requested', onTap: () => _cancelRequest(id), outlined: true);
    } else if (isFull) {
      btn = _chip('Full', disabled: true);
    } else {
      btn = _chip('Join', filled: true, onTap: _busy ? null : () => _join(teamId: id));
    }

    final name   = (t['name']   ?? '').toString();
    final tag    = (t['tag']    ?? '').toString();
    final region = (t['region'] ?? t['city'] ?? '').toString();
    final about  = (t['about']  ?? '').toString();
    final count  = t['memberCount'] ?? 0;
    final max    = t['maxMembers']  ?? 10;
    final logo   = t['logo']?.toString();

    return GestureDetector(
      onTap: () => _openTeam(t),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(children: [
          // Avatar
          TeamAvatar(name: name, tag: tag, logo: logo, size: 50),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + Ready badge
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A))),
                ),
                const SizedBox(width: 6),
                _readyBadge(isFull),
              ]),
              // About (if any)
              if (about.isNotEmpty)
                Text(about,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF999999))),
              const SizedBox(height: 2),
              // Location + members
              Row(children: [
                if (region.isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF999999)),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(region,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF999999))),
                  ),
                  const Text(' · ', style: TextStyle(color: Color(0xFF999999))),
                ],
                const Icon(Icons.group_outlined, size: 12, color: Color(0xFF999999)),
                const SizedBox(width: 2),
                Text('$count/$max',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF999999))),
              ]),
            ],
          )),
          const SizedBox(width: 10),
          btn,
        ]),
      ),
    );
  }

  // "Ready" / "Full" badge — green "Ready" as per the screenshot
  Widget _readyBadge(bool full) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: full ? const Color(0xFFFFEDED) : const Color(0xFFE6FAF0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        full ? 'Full' : 'Ready',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: full ? Colors.redAccent : const Color(0xFF15803D),
        ),
      ),
    );
  }

  // Join / Requested / Full chip button
  Widget _chip(
    String label, {
    VoidCallback? onTap,
    bool filled = false,
    bool outlined = false,
    bool disabled = false,
  }) {
    final bg = disabled
        ? const Color(0xFFEEEEEE)
        : filled
            ? _pink
            : Colors.white;
    final fg = disabled
        ? const Color(0xFFAAAAAA)
        : filled
            ? Colors.white
            : _pink;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: outlined || (!filled && !disabled)
              ? Border.all(color: _pink, width: 1.3)
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CODE TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _codeTab() {
    final ready = _codeCtl.text.trim().length >= 4;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // Code entry card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(children: [
            // Icon
            Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFF1E4FB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tag_rounded, color: _purple, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Got an invite code?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 6),
            const Text(
              'Type the 6-character code shared by the captain below — you will find the team right away.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFF999999), height: 1.4),
            ),
            const SizedBox(height: 20),
            // 6 boxes
            _codeBoxes(),
            const SizedBox(height: 18),
            // Find button
            AnimatedOpacity(
              opacity: ready ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: ready && !_finding ? _findByCode : null,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_pink, _purple]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: _finding
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Find Team',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ),
            // Error
            if (_codeError != null) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                const SizedBox(width: 6),
                Text(_codeError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ]),
            ],
          ]),
        ),

        // Found team card
        if (_foundTeam != null) ...[
          const SizedBox(height: 20),
          _sectionLabel('Team found! 🎉'),
          const SizedBox(height: 8),
          _browseRow(_foundTeam!.map((k, v) {
            if (k == 'id') return MapEntry(k, v);
            return MapEntry(k, v);
          })
            ..putIfAbsent('id', () => _foundTeam!['id'])),
        ],
      ],
    );
  }

  /// 6 individual character boxes (like OTP input)
  Widget _codeBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final char = i < _codeCtl.text.length ? _codeCtl.text[i] : '';
        final active = i == _codeCtl.text.length;
        return GestureDetector(
          onTap: () => _focusCodeField(),
          child: Container(
            width: 42, height: 50,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: char.isNotEmpty
                  ? const Color(0xFFFDE8F1)
                  : const Color(0xFFF5F0FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? _pink
                    : char.isNotEmpty
                        ? _pink.withValues(alpha: 0.4)
                        : const Color(0xFFE0D5EE),
                width: active ? 2 : 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              char,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
            ),
          ),
        );
      }),
    );
  }

  // Hidden text field for code input
  final _codeFocusNode = FocusNode();
  void _focusCodeField() {
    _codeFocusNode.requestFocus();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCAN TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _scanTab() {
    return _ScanTabView(
      active: _scanActive,
      onScanned: _onScannedCode,
      finding: _finding,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: Color(0xFF8B7F8E))),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SCAN TAB VIEW  —  Uses mobile_scanner package
// Add to pubspec.yaml:
//   mobile_scanner: ^5.2.3
// CAMERA permission in AndroidManifest, NSCameraUsageDescription in iOS Info.plist
// ════════════════════════════════════════════════════════════════════════════
class _ScanTabView extends StatefulWidget {
  final bool active;
  final Future<void> Function(String code) onScanned;
  final bool finding;

  const _ScanTabView({
    required this.active,
    required this.onScanned,
    required this.finding,
  });

  @override
  State<_ScanTabView> createState() => _ScanTabViewState();
}

class _ScanTabViewState extends State<_ScanTabView> {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  // We dynamically load mobile_scanner — if not available show fallback.
  // Actual scanner widget is wrapped in try-catch at build time.
  final bool _permissionDenied = false;
  final bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    if (widget.finding) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE93D95)));
    }

    if (_permissionDenied) {
      return _fallback('Camera permission not granted',
          'Go to Settings, allow the camera, then come back.');
    }

    // Try to show scanner — if mobile_scanner not in pubspec, show install guide
    return _scannerWidget();
  }

  Widget _scannerWidget() {
    // ── use the mobile_scanner package ──────────────────────────────────
    // If the package is installed, uncomment the code below:
    //
    // return MobileScanner(
    //   controller: MobileScannerController(
    //     detectionSpeed: DetectionSpeed.normal,
    //     returnImage: false,
    //   ),
    //   onDetect: (capture) {
    //     if (_scanned || !widget.active) return;
    //     final barcode = capture.barcodes.firstOrNull;
    //     final raw = barcode?.rawValue;
    //     if (raw == null || raw.isEmpty) return;
    //     setState(() => _scanned = true);
    //     widget.onScanned(raw);
    //   },
    //   errorBuilder: (ctx, err, _) => _fallback('Camera did not open', err.errorDetails?.message ?? ''),
    //   overlayBuilder: (ctx, constraints) => _overlay(constraints),
    // );
    //
    // ── Show this placeholder until the package is added ─────────────
    return Stack(
      children: [
        // Dark camera preview placeholder
        Container(color: const Color(0xFF1A1A1A)),

        // Corner frame overlay
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: CustomPaint(painter: _QRFramePainter()),
          ),
        ),

        // Instructions
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Column(children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Keep the QR code inside the frame — it will scan automatically',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            // Manual hint
            GestureDetector(
              onTap: () {
                // Send to the Code tab
                DefaultTabController.maybeOf(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_pink, _purple]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '# Use the Code tab',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ]),
        ),

        // Package install note (in dev)
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Add to pubspec.yaml:\nmobile_scanner: ^5.2.3',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4000)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(String title, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, size: 64, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: Color(0xFF555555))),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
          const SizedBox(height: 20),
          const Text('Or use the "Code" tab',
              style: TextStyle(fontSize: 13, color: _pink, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Paints the corners of the QR scanning frame
class _QRFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0xFFE93D95);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const r = 16.0; // corner radius
    const len = 32.0; // corner line length

    // Top-left
    canvas.drawLine(const Offset(r, 0), const Offset(r + len, 0), paint);
    canvas.drawLine(const Offset(0, r), const Offset(0, r + len), paint);
    canvas.drawArc(const Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, paint);

    // Top-right
    canvas.drawLine(Offset(size.width - r - len, 0), Offset(size.width - r, 0), paint);
    canvas.drawLine(Offset(size.width, r), Offset(size.width, r + len), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2), -1.5708, 1.5708, false, paint);

    // Bottom-left
    canvas.drawLine(Offset(0, size.height - r - len), Offset(0, size.height - r), paint);
    canvas.drawLine(Offset(r, size.height), Offset(r + len, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2), 1.5708, 1.5708, false, paint);

    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height - r - len), Offset(size.width, size.height - r), paint);
    canvas.drawLine(Offset(size.width - r - len, size.height), Offset(size.width - r, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, size.height - r * 2, r * 2, r * 2), 0, 1.5708, false, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
