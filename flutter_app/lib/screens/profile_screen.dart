import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';

/// Profile screen - Screenshot ke mutabik:
/// - Gradient header with profile photo (camera button)
/// - Welcome banner (pehli baar)
/// - Player name, Location, Date of birth, Email, Mobile
/// - Update button
/// - Active sessions section
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const ProfileScreen({super.key, this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _pink = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);
  static const _bg = Color(0xFFFDE8F1);
  static const _cardBg = Colors.white;

  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _error;
  bool _isFirstTime = false;

  final _nameCtr = TextEditingController();
  final _locationCtr = TextEditingController();
  final _dobCtr = TextEditingController();
  final _emailCtr = TextEditingController();
  final _phoneCtr = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _locationCtr.dispose();
    _dobCtr.dispose();
    _emailCtr.dispose();
    _phoneCtr.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await AuthService.getProfile();
    if (!mounted) return;
    if (res['success'] != true) {
      // Fallback to local
      final local = await AuthService.getCurrentUser();
      if (!mounted) return;
      if (local != null) {
        _populate(local);
        setState(() { _loading = false; });
      } else {
        setState(() { _error = res['message']?.toString(); _loading = false; });
      }
      return;
    }
    final user = Map<String, dynamic>.from(res['user'] as Map);
    _populate(user);
    // Check if first time (no location set)
    _isFirstTime = (user['city'] ?? '').toString().isEmpty ||
        (user['playerName'] ?? user['name'] ?? '').toString().isEmpty;
    // Load sessions
    final sessRes = await AuthService.getSessions();
    if (mounted && sessRes['success'] == true) {
      _sessions = (sessRes['sessions'] as List? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
    }
    if (!mounted) return;
    setState(() { _loading = false; });
  }

  void _populate(Map<String, dynamic> user) {
    _user = user;
    _nameCtr.text = (user['playerName'] ?? user['name'] ?? '').toString();
    _locationCtr.text = (user['location'] ?? user['city'] ?? '').toString();
    final dob = user['dateOfBirth'];
    if (dob != null) {
      try {
        final d = DateTime.parse(dob.toString());
        _dobCtr.text =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      } catch (_) {
        _dobCtr.text = '';
      }
    } else {
      _dobCtr.text = '';
    }
    _emailCtr.text = (user['email'] ?? '').toString();
    _phoneCtr.text = (user['phone'] ?? '').toString();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtr.text.trim();
    final location = _locationCtr.text.trim();
    if (name.isEmpty) {
      AppUi.snack(context, 'Player name is required', error: true);
      return;
    }
    if (location.isEmpty) {
      AppUi.snack(context, 'Location is required', error: true);
      return;
    }
    setState(() => _saving = true);
    final res = await AuthService.updateProfile(
      playerName: name,
      location: location,
      phone: _phoneCtr.text.trim(),
      dateOfBirth: _dobCtr.text.trim().isEmpty ? null : _dobCtr.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      AppUi.snack(context, res['message']?.toString() ?? 'Profile updated!');
      _isFirstTime = false;
      if (res['user'] != null) _populate(Map<String, dynamic>.from(res['user'] as Map));
    } else {
      AppUi.snack(context, res['message']?.toString() ?? 'Could not update profile', error: true);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 400);
    if (img == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await img.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = img.path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final dataUri = 'data:$mime;base64,$b64';
      final res = await AuthService.updatePhoto(dataUri);
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _user = {...?_user, 'profilePhoto': res['profilePhoto']};
        });
        AppUi.snack(context, 'Photo updated!');
      } else {
        AppUi.snack(context, res['message']?.toString() ?? 'Could not upload photo', error: true);
      }
    } catch (e) {
      if (mounted) AppUi.snack(context, 'Could not upload photo', error: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout?'),
        content: const Text('You will be signed out of this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AuthService.logout();
    widget.onLogout?.call();
  }

  Future<void> _clearSessions() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear all sessions?'),
        content: const Text('You will be logged out from all devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await AuthService.clearSessions();
    if (!mounted) return;
    if (res['success'] == true) {
      await AuthService.logout();
      widget.onLogout?.call();
    } else {
      AppUi.snack(context, res['message']?.toString() ?? 'Could not clear sessions', error: true);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1950),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _pink, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _dobCtr.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _pink))
          : _error != null && _user == null
              ? _errorView()
              : _content(),
    );
  }

  Widget _errorView() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: _pink, size: 48),
                const SizedBox(height: 12),
                Text(_error ?? 'Could not load profile',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF55505A))),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  style: ElevatedButton.styleFrom(backgroundColor: _pink, foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    final name = (_user?['name'] ?? '').toString();
    return Column(
      children: [
        _header(name: name),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              const SizedBox(height: 16),
              if (_isFirstTime) _welcomeBanner(),
              _formCard(),
              const SizedBox(height: 16),
              _sessionsCard(),
              const SizedBox(height: 8),
              _logoutButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header({String name = ''}) {
    final photo = _user?['profilePhoto']?.toString();
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Gradient background
        Container(
          width: double.infinity,
          height: topPad + 120,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(0)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Profile photo (centered, overlapping)
        Positioned(
          bottom: -50,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      color: const Color(0xFFE93D95),
                    ),
                    child: ClipOval(
                      child: _uploadingPhoto
                          ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : photo != null && photo.isNotEmpty
                              ? (photo.startsWith('http')
                                  ? Image.network(photo, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _defaultAvatar(name))
                                  : photo.startsWith('data:image')
                                      ? Image.memory(base64Decode(photo.split(',').last), fit: BoxFit.cover)
                                      : _defaultAvatar(name))
                              : _defaultAvatar(name),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: _pink,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Height for the overlap
        SizedBox(height: topPad + 120 + 50),
      ],
    );
  }

  Widget _defaultAvatar(String name) {
    return Container(
      color: const Color(0xFFE93D95),
      child: Icon(Icons.person_rounded, color: Colors.white.withValues(alpha: 0.9), size: 48),
    );
  }

  Widget _welcomeBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCE4F1)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to Gulabi Charkhi! 🪁',
                  style: TextStyle(
                    color: _pink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tell us your player name and city to get started.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF55505A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            label: 'Player name *',
            controller: _nameCtr,
            hint: 'Your display name',
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Location *',
            controller: _locationCtr,
            hint: 'Your city',
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Date of birth',
            controller: _dobCtr,
            hint: 'YYYY-MM-DD',
            readOnly: true,
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Email address',
            controller: _emailCtr,
            hint: 'your@email.com',
            readOnly: true, // email change allowed nahi
            enabled: false,
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Mobile number',
            controller: _phoneCtr,
            hint: '+91 00000 00000',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),
          _saving
              ? const Center(child: CircularProgressIndicator(color: _pink))
              : GestureDetector(
                  onTap: _save,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_pink, _purple],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Update',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool readOnly = false,
    bool enabled = true,
    TextInputType? keyboardType,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF8B7F8E),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: readOnly,
          enabled: enabled,
          keyboardType: keyboardType,
          onTap: onTap,
          style: TextStyle(
            fontSize: 15,
            color: enabled ? const Color(0xFF1A1A1A) : const Color(0xFFB0A0B0),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFD0C0D0), fontSize: 14),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8, top: 4),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE5D5E5)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _pink, width: 1.5),
            ),
            disabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFEEDDEE)),
            ),
            fillColor: Colors.transparent,
          ),
        ),
      ],
    );
  }

  Widget _sessionsCard() {
    return GestureDetector(
      onTap: () {}, // expandable in future
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active sessions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  Text(
                    '${_sessions.length} device${_sessions.length == 1 ? '' : 's'} logged in',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8B7F8E)),
                  ),
                ],
              ),
            ),
            if (_sessions.length > 1)
              GestureDetector(
                onTap: _clearSessions,
                child: const Text(
                  'Clear all',
                  style: TextStyle(color: _pink, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFCCB0CC)),
          ],
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red, size: 20),
            SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
          ],
        ),
      ),
    );
  }
}
