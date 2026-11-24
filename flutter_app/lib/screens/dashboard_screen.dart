import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
import 'teams_hub_screen.dart';
import 'team_detail_screen.dart';
import '../services/search_service.dart';
import '../services/weather_service.dart';
import '../widgets/search_results.dart';
import '../widgets/weather_sheet.dart';
import '../services/battle_service.dart';
import '../widgets/match_card.dart';
import '../widgets/leaderboard_sheet.dart';
import 'match_detail_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _pageBg = Color(0xFFFDEBF4);
  static const _navHeight = 74.0;

  int _selectedIndex = 0;
  Map<String, dynamic>? _user;

  // ---- Search ----
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  int _searchSeq = 0; // purane (late aaye) responses ignore karne ke liye
  String _query = '';
  bool _searchLoading = false;
  String? _searchError;
  Map<String, dynamic>? _searchData;

  bool get _searchActive => _selectedIndex == 0 && _query.trim().isNotEmpty;

  // ---- Matches near you ----
  List<Map<String, dynamic>> _matches = [];
  int _liveCount = 0;
  int _upcomingCount = 0;
  bool _matchesLoading = true;
  String? _matchesError;
  String _matchesCity = '';
  bool _matchesLoaded = false;

  // ---- Weather ----
  WeatherInfo? _weather;
  String _weatherCity = '';
  Timer? _weatherTimer;

  String get _weatherLabel => _weather == null
      ? 'Weather'
      : '${_weather!.temp.round()}° ${_weather!.condition}';

  @override
  void initState() {
    super.initState();
    _loadUser();
    // App khulte hi FCM token server par sync (pehle se login users ke liye bhi)
    NotificationService.registerToken();
    // Mausam har 15 minute me refresh
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _loadWeather(force: true),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _weatherTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final local = await AuthService.getCurrentUser();
    if (mounted) {
      setState(() => _user = local);
      _loadWeather();
      _loadMatches();
    }
    // Server se latest (team wagairah) - fail ho to local data chalega
    final fresh = await AuthService.refreshMe();
    if (fresh != null && mounted) {
      setState(() => _user = fresh);
      _loadWeather();
      _loadMatches();
    }
  }

  // ------------------------------------------------------------------
  // Matches near you (live + upcoming, user ki city me)
  // ------------------------------------------------------------------
  Future<void> _loadMatches({bool force = false}) async {
    final city = (_user?['city'] ?? '').toString().trim();
    if (!force && _matchesLoaded && city == _matchesCity) return;
    _matchesCity = city;
    if (mounted) setState(() => _matchesLoading = _matches.isEmpty || force);

    final results = await Future.wait([
      BattleService.nearby(city: city, status: 'live', limit: 10),
      BattleService.nearby(city: city, status: 'upcoming', limit: 10),
    ]);
    if (!mounted || city != _matchesCity) return;

    final live = results[0];
    final upcoming = results[1];
    if (live['success'] != true && upcoming['success'] != true) {
      setState(() {
        _matchesError = (live['message'] ?? upcoming['message'] ?? 'Matches load nahi hue').toString();
        _matchesLoading = false;
      });
      return;
    }
    final counts = BattleService.asMap((upcoming['success'] == true ? upcoming : live)['counts']) ?? {};
    setState(() {
      _matches = [
        ...BattleService.asList(live['battles']),
        ...BattleService.asList(upcoming['battles']),
      ];
      _liveCount = (counts['live'] as num?)?.toInt() ?? 0;
      _upcomingCount = (counts['upcoming'] as num?)?.toInt() ?? 0;
      _matchesError = null;
      _matchesLoading = false;
      _matchesLoaded = true;
    });
  }

  Future<void> _openMatch(Map<String, dynamic> m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: m['id'].toString())),
    );
    if (mounted) _loadMatches(force: true); // score badla ho sakta hai
  }

  // ------------------------------------------------------------------
  // Weather
  // ------------------------------------------------------------------
  Future<void> _loadWeather({bool force = false}) async {
    final city = (_user?['city'] ?? '').toString().trim();
    if (city.isEmpty) {
      if (_weather != null && mounted) setState(() => _weather = null);
      _weatherCity = '';
      return;
    }
    if (!force && city == _weatherCity && _weather != null) return;
    _weatherCity = city;
    try {
      final w = await WeatherService.forCity(city, force: force);
      if (!mounted || city != _weatherCity) return;
      setState(() => _weather = w);
    } catch (_) {
      // chip "Weather" hi rahega; sheet kholne par error + retry dikhega
    }
  }

  void _openWeather() {
    showWeatherSheet(context, city: (_user?['city'] ?? '').toString());
  }

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------
  void _onQueryChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    setState(() {
      _query = v;
      _searchError = null;
      if (q.length < SearchService.minLength) {
        _searchSeq++; // chal rahi request ka result ignore
        _searchData = null;
        _searchLoading = false;
      } else {
        _searchLoading = true;
      }
    });
    if (q.length >= SearchService.minLength) {
      _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
    }
  }

  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    final res = await SearchService.search(q);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searchLoading = false;
      if (res['success'] == true) {
        _searchData = res;
        _searchError = null;
      } else {
        _searchError = (res['message'] ?? 'Search nahi ho paya').toString();
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchSeq++;
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _searchData = null;
      _searchError = null;
      _searchLoading = false;
    });
  }

  Future<void> _openTeam(String id) async {
    _searchFocus.unfocus();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: id)),
    );
    if (mounted) _loadUser(); // join/leave hua ho to refresh
  }

  // ------------------------------------------------------------------
  // Profile screen navigation
  // ------------------------------------------------------------------
  Future<void> _openProfileSheet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          onLogout: () {
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          },
        ),
      ),
    );
    // Refresh user data after returning from profile screen
    if (mounted) _loadUser();
  }

  // ------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return PopScope(
      canPop: !_searchActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSearch(); // back dabane par pehle search band
      },
      child: Scaffold(
      backgroundColor: _pageBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: _selectedIndex == 0
                ? _buildHomeTab(bottomInset)
                : _selectedIndex == 2
                    ? MatchesScreen(
                        key: ValueKey('matches-${(_user?['city'] ?? '')}'),
                        city: (_user?['city'] ?? '').toString(),
                        bottomPadding: _navHeight + bottomInset + 40,
                      )
                : _selectedIndex == 3
                    ? TeamsHubScreen(
                        bottomPadding: _navHeight + bottomInset + 40,
                        onChanged: _loadUser,
                      )
                    : _buildPlaceholderTab(),
          ),
          if (!keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomNav(bottomInset),
            ),
        ],
      ),
    ),
    );
  }

  // ------------------------------------------------------------------
  // HOME
  // ------------------------------------------------------------------
  Widget _buildHomeTab(double bottomInset) {
    final name = (_user?['name'] ?? 'Player').toString();
    final city = (_user?['city'] ?? '').toString();

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: _navHeight + bottomInset + 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_searchActive)
            SearchResults(
              query: _query,
              loading: _searchLoading,
              error: _searchError,
              data: _searchData,
              onTeamTap: _openTeam,
            )
          else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlayerCard(name, city),
                const SizedBox(height: 16),
                _buildChips(),
                const SizedBox(height: 22),
                _buildMatchesHeading(),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _buildMatchesList(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, MediaQuery.of(context).padding.top + 12, 14, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const GulabiLogo(size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gulabi Charkhi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'गुलाबी चरखी • Kite Battle Arena',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search
          Container(
            height: 50,
            padding: const EdgeInsets.only(left: 14, right: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textGrey, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onChanged: _onQueryChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14, color: AppColors.textDark),
                    decoration: const InputDecoration(
                      hintText: 'Search matches, venues, players...',
                      hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textGrey),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.close_rounded, color: AppColors.textGrey, size: 20),
                    ),
                  ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPink,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Colors.white, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(double size) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF5FA8E8),
        ),
        child: Icon(Icons.person_rounded, color: Colors.white, size: size * 0.55),
      ),
    );
  }

  Widget _buildPlayerCard(String name, String city) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _avatar(62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hey there 👋',
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppColors.textDark,
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          '@Player',
                          style: TextStyle(
                            color: Color(0xFF9B3FD9),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (city.isNotEmpty) ...[
                          const Text('  •  ',
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: AppColors.textGrey),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textGrey, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _openProfileSheet,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFCE4F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_outlined,
                      color: AppColors.primaryPink, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1E7EE)),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('0', 'Matches'),
              _statDivider(),
              _stat('0', 'Wins'),
              _statDivider(),
              _stat('—', 'Rank', valueColor: AppColors.primaryPink),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primaryPink, size: 22),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {Color valueColor = AppColors.textDark}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
        ],
      ),
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 30, color: const Color(0xFFF1E7EE));

  // ------------------------------------------------------------------
  // Chips
  // ------------------------------------------------------------------
  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(_weatherLabel, _weather?.icon ?? Icons.cloud_outlined,
              selected: true, onTap: _openWeather),
          const SizedBox(width: 8),
          _chip('Filters', Icons.tune_rounded, dot: AppColors.primaryPink),
          const SizedBox(width: 8),
          _chip('Sort', Icons.bar_chart_rounded, dot: const Color(0xFF3B82F6)),
          const SizedBox(width: 8),
          _chip('Nearby', Icons.location_on_rounded, dot: const Color(0xFF10B981)),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon,
      {bool selected = false, Color? dot, VoidCallback? onTap}) {
    final chip = Container(
      height: 40,
      padding: const EdgeInsets.only(left: 6, right: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryPink : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (selected ? AppColors.primaryPink : Colors.black)
                .withValues(alpha: selected ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? Colors.white.withValues(alpha: 0.25) : dot,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textDark,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }

  // ------------------------------------------------------------------
  // Matches near you
  // ------------------------------------------------------------------
  Widget _buildMatchesHeading() {
    final city = (_user?['city'] ?? '').toString().trim();
    String sub;
    if (_matchesLoading && _matches.isEmpty) {
      sub = 'Loading...';
    } else if (_matches.isEmpty) {
      sub = city.isEmpty ? 'Koi match nahi mila' : 'Abhi $city me koi match nahi';
    } else {
      sub = '$_liveCount live • $_upcomingCount upcoming${city.isEmpty ? '' : ' in $city'}';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Matches near you',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _selectedIndex = 2),
          child: const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'View All →',
              style: TextStyle(
                color: AppColors.primaryPink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchesList() {
    if (_matchesLoading && _matches.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
      );
    }
    if (_matchesError != null && _matches.isEmpty) {
      return _matchesMessage(Icons.wifi_off_rounded, _matchesError!, retry: true);
    }
    if (_matches.isEmpty) {
      return _matchesMessage(
        Icons.sports_score_rounded,
        'Abhi koi live ya upcoming match nahi. Team ka captain kisi team ko challenge karega to yahan dikhega.',
      );
    }
    return SizedBox(
      height: 226,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: _matches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => MatchCard(
          match: _matches[i],
          width: 284,
          onTap: () => _openMatch(_matches[i]),
          onLeaderboard: () => showLeaderboardSheet(context),
        ),
      ),
    );
  }

  Widget _matchesMessage(IconData icon, String text, {bool retry = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.primaryPink.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 13, height: 1.35),
            ),
            if (retry)
              TextButton(
                onPressed: () => _loadMatches(force: true),
                child: const Text('Retry', style: TextStyle(color: AppColors.primaryPink)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab() {
    const labels = ['', 'Register for Matches', 'Matches', 'Teams', 'Association'];
    const icons = [
      Icons.home_rounded,
      Icons.group_add_outlined,
      Icons.gps_fixed_rounded,
      Icons.workspace_premium_outlined,
      Icons.business_center_outlined,
    ];
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icons[_selectedIndex],
                size: 60, color: AppColors.primaryPink.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              labels[_selectedIndex],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Coming soon...', style: TextStyle(color: AppColors.textGrey)),
            const SizedBox(height: _navHeight),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Bottom nav (beech mein ubhra hua Matches button)
  // ------------------------------------------------------------------
  Widget _buildBottomNav(double bottomInset) {
    const lift = 28.0; // center button kitna bahar nikla hai
    return SizedBox(
      height: _navHeight + bottomInset + lift,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // White bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _navHeight + bottomInset,
            child: Container(
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryPink.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _navItem(0, 'Home', Icons.home_outlined, Icons.home_rounded),
                  _navItem(1, 'Register', Icons.group_add_outlined, Icons.group_add_rounded),
                  const Expanded(child: SizedBox()), // center ke liye jagah
                  _navItem(3, 'Teams', Icons.workspace_premium_outlined,
                      Icons.workspace_premium_rounded),
                  _navItem(4, 'Association', Icons.business_center_outlined,
                      Icons.business_center_rounded),
                ],
              ),
            ),
          ),

          // Center Matches button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: lift + _navHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedIndex = 2),
                child: SizedBox(
                  width: 84,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryPink.withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.gps_fixed_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Matches',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              _selectedIndex == 2 ? FontWeight.w800 : FontWeight.w600,
                          color: _selectedIndex == 2
                              ? AppColors.primaryPink
                              : AppColors.primaryPink.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, String label, IconData icon, IconData activeIcon) {
    final selected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: 24,
              color: selected ? AppColors.primaryPink : const Color(0xFF9A93A0),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? AppColors.primaryPink : const Color(0xFF9A93A0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
