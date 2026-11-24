import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

const kTeamPageBg = Color(0xFFFDEBF4);
const kTeamHeaderColors = [Color(0xFFE93D95), Color(0xFFA64CF5)];

/// Gradient header (back button + title + subtitle) - sab team screens mein same
class GradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final List<Widget> actions;

  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, MediaQuery.of(context).padding.top + 10, 14, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: kTeamHeaderColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(
        children: [
          if (showBack) ...[
            GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const HeaderIconButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Team ka logo. logo (URL / data URI) ho to wo, warna tag letters gradient square par.
class TeamAvatar extends StatelessWidget {
  final String name;
  final String tag;
  final String? logo;
  final double size;

  const TeamAvatar({
    super.key,
    required this.name,
    required this.tag,
    this.logo,
    this.size = 48,
  });

  static const _palettes = [
    [Color(0xFF1FB5C9), Color(0xFF0E8FA8)],
    [Color(0xFFF59E0B), Color(0xFFD97706)],
    [Color(0xFFA855F7), Color(0xFF7B2FBE)],
    [Color(0xFFEC4899), Color(0xFFBE185D)],
    [Color(0xFF6366F1), Color(0xFF4338CA)],
    [Color(0xFF10B981), Color(0xFF047857)],
  ];

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final l = logo;
    if (l != null && l.isNotEmpty) {
      Widget? img;
      if (l.startsWith('data:image')) {
        try {
          img = Image.memory(base64Decode(l.split(',').last), fit: BoxFit.cover);
        } catch (_) {}
      } else {
        img = Image.network(l, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _letters(radius));
      }
      if (img != null) {
        return ClipRRect(
          borderRadius: radius,
          child: SizedBox(width: size, height: size, child: img),
        );
      }
    }
    return _letters(radius);
  }

  Widget _letters(BorderRadius radius) {
    final seed = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final colors = _palettes[seed % _palettes.length];
    final text = tag.isEmpty ? (name.isEmpty ? '?' : name[0].toUpperCase()) : tag;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radius,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * (text.length > 2 ? 0.27 : 0.36),
        ),
      ),
    );
  }
}

/// Chhota rounded label (Public / Ready / Full / Captain ...)
class MiniPill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const MiniPill(this.text, {super.key, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final bool full;
  const StatusPill({super.key, required this.full});

  @override
  Widget build(BuildContext context) => full
      ? const MiniPill('Full', fg: Color(0xFFB91C1C), bg: Color(0xFFFEE2E2))
      : const MiniPill('Ready', fg: Color(0xFF15803D), bg: Color(0xFFDCFCE7));
}

/// White rounded card
class WhiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  const WhiteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B6570),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Pill tabs (Members | Scoreboard | Invite | Matches, Browse | Code | Scan)
class PillTabs extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;

  const PillTabs({
    super.key,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final on = i == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFA64CF5) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icons[i],
                        size: 14, color: on ? Colors.white : const Color(0xFF8E3FD6)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white : const Color(0xFF8E3FD6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Browse list / My teams list ki ek row
class TeamRow extends StatelessWidget {
  final Map<String, dynamic> team;
  final Widget? trailing;
  final VoidCallback? onTap;
  const TeamRow({super.key, required this.team, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (team['name'] ?? '').toString();
    final region = (team['region'] ?? team['city'] ?? '').toString();
    final count = team['memberCount'] ?? 0;
    final max = team['maxMembers'] ?? 10;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: WhiteCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            TeamAvatar(
              name: name,
              tag: (team['tag'] ?? '').toString(),
              logo: team['logo']?.toString(),
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(full: team['status'] == 'full'),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (region.isNotEmpty) ...[
                        const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textGrey),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            region,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.group_outlined, size: 13, color: AppColors.textGrey),
                      const SizedBox(width: 2),
                      Text(
                        '$count/$max',
                        style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Chhota pink "Join" button
class SmallPinkButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool filled;
  const SmallPinkButton({super.key, required this.text, this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: filled && !disabled ? AppColors.primaryPink : const Color(0xFFFCE4F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: filled && !disabled
                ? Colors.white
                : (disabled ? AppColors.textGrey : AppColors.primaryPink),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Color(0xFFF1E4FB), shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFF8E3FD6), size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey, height: 1.3),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Yes',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textGrey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText,
              style: const TextStyle(color: AppColors.primaryPink, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r == true;
}
