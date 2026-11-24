import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../services/team_service.dart';
import '../widgets/team_widgets.dart';

/// Create Team screen. [existing] dene par ye "Edit team" ban jata hai (sirf captain).
/// Success par pop hota hai team map ke saath.
class CreateTeamScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const CreateTeamScreen({super.key, this.existing});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) =>
      v.copyWith(text: v.text.toUpperCase());
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _name = TextEditingController();
  final _tag = TextEditingController();
  final _region = TextEditingController();
  final _about = TextEditingController();
  int _max = 10;
  bool _public = true;
  bool _loading = false;

  bool get _isEdit => widget.existing != null;
  int get _minMax {
    if (!_isEdit) return 4;
    final c = (widget.existing!['members'] is List) ? (widget.existing!['members'] as List).length : 0;
    return c < 4 ? 4 : c;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    if (t != null) {
      _name.text = (t['name'] ?? '').toString();
      _tag.text = (t['tag'] ?? '').toString();
      _region.text = (t['region'] ?? '').toString();
      _about.text = (t['about'] ?? '').toString();
      _max = (t['maxMembers'] is int) ? t['maxMembers'] as int : 10;
      _public = t['isPublic'] != false;
    }
    for (final c in [_name, _tag, _region, _about]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    _region.dispose();
    _about.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().length >= 3 &&
      _tag.text.trim().length >= 2 &&
      _region.text.trim().length >= 2;

  Future<void> _submit() async {
    if (!_valid || _loading) return;
    setState(() => _loading = true);

    final Map<String, dynamic> res;
    if (_isEdit) {
      res = await TeamService.update(widget.existing!['id'].toString(), {
        'name': _name.text.trim(),
        'tag': _tag.text.trim(),
        'region': _region.text.trim(),
        'about': _about.text.trim(),
        'maxMembers': _max,
        'isPublic': _public,
      });
    } else {
      res = await TeamService.create(
        name: _name.text.trim(),
        tag: _tag.text.trim(),
        region: _region.text.trim(),
        about: _about.text.trim(),
        maxMembers: _max,
        isPublic: _public,
      );
    }
    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] != true) {
      AppUi.snack(context, res['message'] ?? 'Something went wrong', error: true);
      return;
    }
    final team = TeamService.asMap(res['team']);
    if (_isEdit) {
      AppUi.snack(context, 'Team updated');
      Navigator.pop(context, team);
      return;
    }
    await _showCreated(team);
    if (mounted) Navigator.pop(context, team);
  }

  Future<void> _showCreated(Map<String, dynamic>? team) {
    final code = (team?['inviteCode'] ?? '').toString();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 54),
            const SizedBox(height: 10),
            Text(
              '${team?['name'] ?? 'Your team'} is ready!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            const Text(
              'Share this invite code with your friends',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFCEFF6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryPink.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPink,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      AppUi.snack(ctx, 'Invite code copied');
                    },
                    icon: const Icon(Icons.copy_rounded, color: AppColors.primaryPurple),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GradientButton(text: 'Continue', onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTeamPageBg,
      body: Column(
        children: [
          GradientHeader(
            title: _isEdit ? 'Edit Team' : 'Create Team',
            subtitle: _isEdit ? 'Update your squad' : 'Build your squad',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              children: [
                Center(
                  child: TeamAvatar(
                    name: _name.text.trim(),
                    tag: _tag.text.trim(),
                    logo: widget.existing?['logo']?.toString(),
                    size: 84,
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text('Team badge (made from your tag)',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
                ),
                _label('Team name', required: true),
                TextField(
                  controller: _name,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('e.g. Sky Riders'),
                ),
                _label('Tag / Initials', required: true),
                TextField(
                  controller: _tag,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    _UpperCaseFormatter(),
                  ],
                  style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w700),
                  decoration: _dec('SKR'),
                ),
                _hint('2-4 letters shown on match cards (e.g. SKR)'),
                _label('Region / Area', required: true),
                TextField(
                  controller: _region,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('e.g. Vaishali Nagar, Jaipur'),
                ),
                _label('About'),
                TextField(
                  controller: _about,
                  maxLength: 200,
                  minLines: 3,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _dec('We battle every Sunday morning. Beginners welcome.'),
                ),
                _hint('Tell players what your team is about (optional)'),
                const SizedBox(height: 14),
                _maxMembers(),
                const SizedBox(height: 14),
                WhiteCard(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primaryPink,
                    value: _public,
                    onChanged: (v) => setState(() => _public = v),
                    title: const Text('Public team',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      _public
                          ? 'Anyone can find and request to join'
                          : 'Only people with your invite code can join',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Opacity(
                opacity: _valid ? 1 : 0.45,
                child: GradientButton(
                  text: _isEdit ? 'Save changes' : 'Create team',
                  icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
                  isLoading: _loading,
                  onPressed: _valid ? _submit : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _maxMembers() {
    final min = _minMax;
    return WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MAX MEMBERS: $_max',
              style: const TextStyle(
                  fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Color(0xFF6B6570))),
          Row(
            children: [
              _stepBtn(Icons.remove_rounded, _max > min ? () => setState(() => _max--) : null),
              Expanded(
                child: Slider(
                  value: _max.clamp(min, 20).toDouble(),
                  min: min.toDouble(),
                  max: 20,
                  divisions: (20 - min) == 0 ? null : 20 - min,
                  activeColor: AppColors.primaryPink,
                  onChanged: (v) => setState(() => _max = v.round()),
                ),
              ),
              _stepBtn(Icons.add_rounded, _max < 20 ? () => setState(() => _max++) : null),
            ],
          ),
          Text('Range $min – 20',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFFCE4F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              size: 18, color: onTap == null ? AppColors.textGrey : AppColors.primaryPink),
        ),
      );

  Widget _label(String t, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6, left: 2),
        child: Text.rich(
          TextSpan(
            text: t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Color(0xFF6B6570)),
            children: required
                ? const [TextSpan(text: ' *', style: TextStyle(color: AppColors.primaryPink))]
                : null,
          ),
        ),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 2),
        child: Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.textGrey)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        fillColor: Colors.white,
      );
}
