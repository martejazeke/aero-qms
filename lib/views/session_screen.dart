// lib/views/session_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/queue_service.dart';
import '../services/settings_service.dart';
import '../models/player.dart';
import '../models/session.dart';

const _gold = Color(0xFFD4AF37);

// ── Helpers ───────────────────────────────────────────────────

Color _cardBg(BuildContext ctx) => Theme.of(ctx).brightness == Brightness.dark
    ? const Color(0xFF1F2937)
    : Colors.white;

Color _borderColor(BuildContext ctx) =>
    Theme.of(ctx).brightness == Brightness.dark
    ? const Color(0xFF374151)
    : const Color(0xFFE2E8F0);

Color _textPrimary(BuildContext ctx) =>
    Theme.of(ctx).brightness == Brightness.dark
    ? Colors.white
    : const Color(0xFF111827);

Color _textSecondary(BuildContext ctx) => const Color(0xFF94A3B8);

Color _surfaceDim(BuildContext ctx) =>
    Theme.of(ctx).brightness == Brightness.dark
    ? const Color(0xFF111827)
    : const Color(0xFFF8FAFC);

// ── Session Screen ────────────────────────────────────────────

class SessionScreen extends StatefulWidget {
  final String sessionId;
  const SessionScreen({super.key, required this.sessionId});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  int _currentTab = 0;

  static const _tabs = [
    'Queue',
    'Players',
    'Rankings',
    'Courts',
    'History',
    'Settings',
  ];
  static const _icons = [
    Icons.list_alt_outlined,
    Icons.people_outline,
    Icons.leaderboard_outlined,
    Icons.sports_tennis_outlined,
    Icons.history_outlined,
    Icons.tune_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueService>();
    final session = queue.getSession(widget.sessionId);
    if (session == null) {
      return const Scaffold(body: Center(child: Text('Session not found')));
    }

    final isArchived = session.isEnded;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              session.name.toUpperCase(),
              style: const TextStyle(fontSize: 16, letterSpacing: 1.5),
            ),
            Text(
              _formatDate(session.date),
              style: TextStyle(
                fontSize: 11,
                color: _textSecondary(context),
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!isArchived) ...[
            IconButton(
              icon: const Icon(Icons.group_add_outlined),
              tooltip: 'Bulk import',
              onPressed: () => _showBulkImportDialog(context, session.id),
            ),
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Add player',
              onPressed: () => _showAddPlayerDialog(context, session.id),
            ),
          ],
          if (isArchived)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF94A3B8).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'ARCHIVED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _QueueTab(sessionId: widget.sessionId, isArchived: isArchived),
          _PlayersTab(
            sessionId: widget.sessionId,
            isArchived: isArchived,
            onAddPlayer: isArchived
                ? null
                : () => _showAddPlayerDialog(context, session.id),
          ),
          _RankingsTab(sessionId: widget.sessionId),
          _CourtsTab(sessionId: widget.sessionId, isArchived: isArchived),
          _HistoryTab(sessionId: widget.sessionId),
          _SettingsTab(sessionId: widget.sessionId, isArchived: isArchived),
        ],
      ),
      bottomNavigationBar: _AeroNavBar(
        currentIndex: _currentTab,
        tabs: _tabs,
        icons: _icons,
        onTap: (i) => setState(() => _currentTab = i),
      ),
      floatingActionButton: (!isArchived && _currentTab == 0)
          ? FloatingActionButton.extended(
              onPressed: () {
                final queue = context.read<QueueService>();
                final session = queue.getSession(widget.sessionId);
                final activeCourts = session?.activeCourts ?? [];
                final courtCount = session?.courtCount ?? 0;
                // Either there's a real empty court, or there are unfilled placeholder slots
                final hasEmptyCourt =
                    activeCourts.any(
                      (c) => c.teamA.isEmpty && c.teamB.isEmpty,
                    ) ||
                    activeCourts.length < courtCount;
                final enoughPlayers = (session?.waitingRoom.length ?? 0) >= 4;

                if (!enoughPlayers) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Need at least 4 players in the queue'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                // All courts are occupied — confirm before creating a new one.
                if (!hasEmptyCourt) {
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Create a new court?'),
                      content: const Text(
                        'All courts are currently occupied. '
                        'This will add a new court and fill it from the queue.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dCtx);
                            queue.fillCourt(sessionId: widget.sessionId);
                          },
                          child: const Text(
                            'Create & Fill',
                            style: TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                queue.fillCourt(sessionId: widget.sessionId);
              },
              label: const Text('Fill Court'),
              icon: const Icon(Icons.bolt),
              backgroundColor: _gold,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  void _showAddPlayerDialog(BuildContext context, String sessionId) {
    final nameCtrl = TextEditingController();
    SkillLevel selectedSkill = SkillLevel.intermediate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _borderColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Add Player',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary(context),
                  ),
                ),
                const SizedBox(height: 24),
                _Label('PLAYER NAME'),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 15, color: _textPrimary(context)),
                  decoration: _inputDeco('e.g. Alex Chen', context),
                ),
                const SizedBox(height: 20),
                _Label('SKILL LEVEL'),
                const SizedBox(height: 8),
                Row(
                  children: SkillLevel.values.map((skill) {
                    final sel = selectedSkill == skill;
                    final col = _skillColor(skill);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => set(() => selectedSkill = skill),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: EdgeInsets.only(
                            right: skill != SkillLevel.advanced ? 8 : 0,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: sel
                                ? col.withOpacity(0.12)
                                : _surfaceDim(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? col : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            skill.name[0].toUpperCase() +
                                skill.name.substring(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? col : _textSecondary(context),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      context.read<QueueService>().addPlayerToSession(
                        sessionId: sessionId,
                        name: name,
                        skill: selectedSkill,
                      );
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Add to Queue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bulk import ─────────────────────────────────────────────
  void _showBulkImportDialog(BuildContext context, String sessionId) {
    final ctrl = TextEditingController();
    SkillLevel defaultSkill = SkillLevel.intermediate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _borderColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.group_add_outlined,
                      color: _gold,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Bulk Import Players',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Paste names separated by commas or new lines. '
                  'Players start as Absent — tap Present on their card when they arrive.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary(context),
                  ),
                ),
                const SizedBox(height: 16),
                _Label('DEFAULT SKILL LEVEL'),
                const SizedBox(height: 8),
                Row(
                  children: SkillLevel.values.map((skill) {
                    final sel = defaultSkill == skill;
                    final col = _skillColor(skill);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => set(() => defaultSkill = skill),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: EdgeInsets.only(
                            right: skill != SkillLevel.advanced ? 8 : 0,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: sel
                                ? col.withOpacity(0.12)
                                : _surfaceDim(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? col : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            skill.name[0].toUpperCase() +
                                skill.name.substring(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? col : _textSecondary(context),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _Label('PLAYER NAMES'),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 6,
                  style: TextStyle(fontSize: 14, color: _textPrimary(context)),
                  decoration: _inputDeco(
                    'e.g. Alice, Bob, Carol\nDave, Eve',
                    context,
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: ctrl,
                  builder: (_, val, __) {
                    final names = _parseNames(val.text);
                    return Text(
                      names.isEmpty
                          ? 'Enter names above'
                          : '${names.length} player${names.length == 1 ? "" : "s"} ready to import',
                      style: TextStyle(
                        fontSize: 12,
                        color: names.isEmpty ? _textSecondary(context) : _gold,
                        fontWeight: names.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final names = _parseNames(ctrl.text);
                      if (names.isEmpty) return;
                      final queue = context.read<QueueService>();
                      queue.addPlayersBulk(
                        sessionId: sessionId,
                        names: names,
                        skill: defaultSkill,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${names.length} players added to queue',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Import Players',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Parses raw text into clean, deduplicated, sorted name list.
  /// Handles commas, newlines, semicolons.
  /// Handles numbered lists (1. 2. 1) 2)), commas, newlines,
  /// semicolons, zero-width unicode chars, and emojis in names.
  List<String> _parseNames(String raw) {
    return raw
        .split(RegExp(r'[,\n;]+'))
        .map((s) {
          // Remove zero-width spaces and invisible unicode
          var c = s.replaceAll(
            RegExp(r'[\u200b\u200c\u200d\u2060\ufeff\u00a0]'),
            '',
          );
          // Strip leading number prefixes: "1. " "2) " etc
          c = c.replaceAll(RegExp(r'^\d+[\.)\s]\s*'), '');
          return c.trim();
        })
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _formatDate(DateTime d) {
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}';
  }
}

// ── Nav bar ───────────────────────────────────────────────────

class _AeroNavBar extends StatelessWidget {
  final int currentIndex;
  final List<String> tabs;
  final List<IconData> icons;
  final ValueChanged<int> onTap;
  const _AeroNavBar({
    required this.currentIndex,
    required this.tabs,
    required this.icons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg(context),
        border: Border(top: BorderSide(color: _borderColor(context))),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 4,
        top: 8,
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = currentIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? _gold.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      icons[i],
                      size: 18,
                      color: active ? _gold : _textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? _gold : _textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Tab: Queue ────────────────────────────────────────────────

class _QueueTab extends StatelessWidget {
  final String sessionId;
  final bool isArchived;
  const _QueueTab({required this.sessionId, required this.isArchived});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<QueueService>().getSession(sessionId);
    final waiting = session?.waitingRoom ?? [];

    if (waiting.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_outlined,
              size: 40,
              color: _textSecondary(context),
            ),
            const SizedBox(height: 12),
            Text(
              'Queue is empty',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            if (!isArchived)
              Text(
                'Add players using the icon above',
                style: TextStyle(fontSize: 13, color: _textSecondary(context)),
              ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: waiting.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = waiting[i];
        final waitMins = DateTime.now()
            .difference(p.lastWaitStartTime)
            .inMinutes;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: i == 0 ? _gold.withOpacity(0.1) : _surfaceDim(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: i == 0 ? _gold : _textSecondary(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary(context),
                      ),
                    ),
                    Text(
                      isArchived
                          ? '${p.gamesPlayed} games played'
                          : '$waitMins min wait · ${p.gamesPlayed} games',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (p.currentStreak != 0) ...[
                _StreakBadge(streak: p.currentStreak),
                const SizedBox(width: 6),
              ],
              if (p.preferredPartnerId != null) ...[
                _PartnerBadge(),
                const SizedBox(width: 6),
              ],
              _SkillBadge(skill: p.skill),
            ],
          ),
        );
      },
    );
  }
}

// ── Tab: Players ──────────────────────────────────────────────

class _PlayersTab extends StatelessWidget {
  final String sessionId;
  final bool isArchived;
  final VoidCallback? onAddPlayer;
  const _PlayersTab({
    required this.sessionId,
    required this.isArchived,
    this.onAddPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<QueueService>().getSession(sessionId);
    final players = session?.players ?? [];

    return Stack(
      children: [
        players.isEmpty
            ? Center(
                child: Text(
                  'No players added yet',
                  style: TextStyle(color: _textSecondary(context)),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                itemCount: players.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = players[i];
                  final inQueue = session!.waitingRoom.any((x) => x.id == p.id);
                  final onCourt = session.activeCourts.any(
                    (c) => c.allPlayers.any((x) => x.id == p.id),
                  );

                  final isAbsent = !p.isPresent;
                  return GestureDetector(
                    onTap: isArchived
                        ? () => _openPlayerStats(context, p, players)
                        : () => _showEditPlayerDialog(
                            context,
                            p,
                            sessionId,
                            players,
                          ),
                    onLongPress: () => _openPlayerStats(context, p, players),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isAbsent ? 0.45 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAbsent
                                ? _borderColor(context).withOpacity(0.5)
                                : _borderColor(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: isAbsent
                                  ? _textSecondary(context).withOpacity(0.1)
                                  : _gold.withOpacity(0.1),
                              child: Text(
                                p.name[0].toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isAbsent
                                      ? _textSecondary(context)
                                      : _gold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimary(context),
                                          ),
                                        ),
                                      ),
                                      if (!isArchived)
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: _textSecondary(
                                            context,
                                          ).withOpacity(0.5),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    '${p.wins}W · ${p.losses}L · ${p.winRateDisplay} win rate',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _SkillBadge(skill: p.skill),
                                const SizedBox(height: 4),
                                // Presence toggle — most prominent action
                                if (!isArchived)
                                  GestureDetector(
                                    onTap: () => context
                                        .read<QueueService>()
                                        .togglePlayerPresence(
                                          sessionId: sessionId,
                                          playerId: p.id,
                                        ),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isAbsent
                                            ? _textSecondary(
                                                context,
                                              ).withOpacity(0.08)
                                            : const Color(
                                                0xFF22C55E,
                                              ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isAbsent
                                                ? Icons.person_off_outlined
                                                : Icons.check_circle_outline,
                                            size: 11,
                                            color: isAbsent
                                                ? _textSecondary(context)
                                                : const Color(0xFF22C55E),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isAbsent ? 'Absent' : 'Present',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isAbsent
                                                  ? _textSecondary(context)
                                                  : const Color(0xFF22C55E),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  _StatusPill(
                                    inQueue: inQueue,
                                    onCourt: onCourt,
                                  ),
                                const SizedBox(height: 4),
                                if (!isArchived && p.isPresent)
                                  _PartnerButton(
                                    player: p,
                                    allPlayers: players,
                                    onSet: (partnerId) => context
                                        .read<QueueService>()
                                        .setPreferredPartner(
                                          sessionId: sessionId,
                                          playerId: p.id,
                                          partnerId: partnerId,
                                        ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        if (!isArchived && onAddPlayer != null)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'add_player_fab',
              onPressed: onAddPlayer,
              label: const Text('Add Player'),
              icon: const Icon(Icons.person_add_outlined),
              backgroundColor: _gold,
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }
}

// ── Tab: Rankings ─────────────────────────────────────────────

class _RankingsTab extends StatelessWidget {
  final String sessionId;
  const _RankingsTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<QueueService>().getSession(sessionId);
    final players = [...(session?.players ?? [])]
      ..sort((a, b) => b.wins.compareTo(a.wins));
    final allPlayers = session?.players ?? [];

    if (players.isEmpty) {
      return Center(
        child: Text(
          'No rankings yet',
          style: TextStyle(color: _textSecondary(context)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: players.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = players[i];
        return GestureDetector(
          onTap: () => _openPlayerStats(context, p, allPlayers),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: i < 3
                    ? _podiumColor(i).withOpacity(0.3)
                    : _borderColor(context),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    i == 0
                        ? '🥇'
                        : i == 1
                        ? '🥈'
                        : i == 2
                        ? '🥉'
                        : '${i + 1}',
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary(context),
                        ),
                      ),
                      Text(
                        '${p.wins}W · ${p.losses}L · ${p.winRateDisplay} win rate',
                        style: TextStyle(
                          fontSize: 12,
                          color: _textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (p.currentStreak != 0) ...[
                  _StreakBadge(streak: p.currentStreak),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: _textSecondary(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _podiumColor(int i) => [
    const Color(0xFFF59E0B),
    const Color(0xFF94A3B8),
    const Color(0xFFCD7C2F),
  ][i];
}

// ── Tab: Courts ───────────────────────────────────────────────

class _CourtsTab extends StatelessWidget {
  final String sessionId;
  final bool isArchived;
  const _CourtsTab({required this.sessionId, required this.isArchived});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueService>();
    final session = queue.getSession(sessionId);
    if (session == null) return const SizedBox();

    final courts = session.activeCourts;
    final totalSlots = courts.length < session.courtCount
        ? session.courtCount
        : courts.length;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: isArchived ? courts.length : totalSlots + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        if (!isArchived && i == totalSlots) {
          return _AddCourtButton(onTap: () => queue.addCourt(sessionId));
        }
        final hasData = i < courts.length;
        return _CourtCard(
          courtIndex: i,
          court: hasData ? courts[i] : null,
          session: session,
          isArchived: isArchived,
          onFill: (courtIdx) {
            final ok = queue.fillCourt(
              sessionId: sessionId,
              courtIndex: courtIdx,
            );
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Need at least 4 players in the queue'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onEnd: (teamAWon) => queue.endMatch(
            sessionId: sessionId,
            courtIndex: i,
            teamAWon: teamAWon,
          ),
          onSwap: (a, b) => queue.swapPlayers(
            sessionId: sessionId,
            courtIndex: i,
            playerIdA: a,
            playerIdB: b,
          ),
          onSubstitute: (outId, inId) => queue.substitutePlayer(
            sessionId: sessionId,
            courtIndex: i,
            outPlayerId: outId,
            inPlayerId: inId,
          ),
          onAssign: (pid, team, slot) => queue.assignPlayerToCourt(
            sessionId: sessionId,
            courtIndex: i,
            playerId: pid,
            team: team,
            slotIndex: slot,
          ),
          onClear: (team, slot) => queue.clearCourtSlot(
            sessionId: sessionId,
            courtIndex: i,
            team: team,
            slotIndex: slot,
          ),
          onRemove: () => queue.removeCourt(sessionId, i),
        );
      },
    );
  }
}

class _AddCourtButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCourtButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_circle_outline,
            color: _gold.withOpacity(0.7),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Add Court',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _gold.withOpacity(0.8),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CourtCard extends StatefulWidget {
  final int courtIndex;
  final Court? court;
  final Session session;
  final bool isArchived;
  final void Function(int courtIdx) onFill;
  final void Function(bool) onEnd;
  final void Function(String, String) onSwap;
  final void Function(String outId, String? inId) onSubstitute;
  final void Function(String, String, int) onAssign;
  final void Function(String, int) onClear;
  final VoidCallback onRemove;

  const _CourtCard({
    required this.courtIndex,
    required this.court,
    required this.session,
    required this.isArchived,
    required this.onFill,
    required this.onEnd,
    required this.onSwap,
    required this.onSubstitute,
    required this.onAssign,
    required this.onClear,
    required this.onRemove,
  });

  @override
  State<_CourtCard> createState() => _CourtCardState();
}

class _CourtCardState extends State<_CourtCard> {
  bool? _winner;
  bool _editMode = false;
  String? _selectedForSwap;

  bool get _isFull {
    final court = widget.court;
    if (court == null) return false;
    final perTeam = court.type == CourtType.singles ? 1 : 2;
    return court.teamA.length == perTeam && court.teamB.length == perTeam;
  }

  bool get _isEmpty =>
      widget.court == null ||
      (widget.court!.teamA.isEmpty && widget.court!.teamB.isEmpty);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor(context)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          if (_isFull && !_isEmpty)
            _buildFilledBody(context)
          else
            _buildEmptyBody(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final dotColor = _isFull ? _gold : _textSecondary(context).withOpacity(0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceDim(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: _borderColor(context))),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            'Court ${widget.courtIndex + 1}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary(context),
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (_isFull && !widget.isArchived) ...[
            // Delete court in edit mode
            if (_editMode)
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Remove Court?'),
                      content: const Text(
                        'All players will be sent back to the queue.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dCtx);
                            setState(() {
                              _editMode = false;
                              _selectedForSwap = null;
                            });
                            widget.onRemove();
                          },
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withOpacity(0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Remove',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_editMode) const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _editMode = !_editMode;
                _selectedForSwap = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _editMode
                      ? _gold.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _editMode ? _gold : _borderColor(context),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 14,
                      color: _editMode ? _gold : _textSecondary(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _editMode ? 'Done' : 'Edit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _editMode ? _gold : _textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'LIVE',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _gold,
                letterSpacing: 1.2,
              ),
            ),
          ] else if (!_isFull && !widget.isArchived)
            GestureDetector(
              onTap: widget.onRemove,
              child: Icon(
                Icons.close,
                size: 16,
                color: _textSecondary(context),
              ),
            ),
        ],
      ),
    );
  }

  // ── Empty / partial court ─────────────────────────────────
  Widget _buildEmptyBody(BuildContext context) {
    if (widget.isArchived) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No match data',
          style: TextStyle(color: _textSecondary(context), fontSize: 13),
        ),
      );
    }

    final waiting = widget.session.waitingRoom;
    final court = widget.court;
    final courtPl = court?.allPlayers ?? [];
    final available = [...waiting, ...courtPl]
      ..sort((a, b) => a.name.compareTo(b.name));

    Player? slotPlayer(String team, int idx) {
      final list = team == 'A' ? court?.teamA : court?.teamB;
      if (list == null || idx >= list.length) return null;
      return list[idx];
    }

    Widget dropdownSlot(String team, int slotIdx) {
      final current = slotPlayer(team, slotIdx);
      final teamColor = team == 'A'
          ? const Color(0xFF3B82F6)
          : const Color(0xFFEF4444);

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: teamColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: teamColor.withOpacity(0.2)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: current?.id,
            dropdownColor: _cardBg(context),
            hint: Text(
              'Select player',
              style: TextStyle(fontSize: 13, color: teamColor),
            ),
            icon: Icon(Icons.keyboard_arrow_down, color: teamColor, size: 18),
            items: [
              DropdownMenuItem<String>(
                value: '__clear__',
                child: Text(
                  '— Clear slot —',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary(context),
                  ),
                ),
              ),
              ...available.map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: _textPrimary(context),
                    ),
                  ),
                ),
              ),
            ],
            onChanged: (val) {
              if (val == null) return;
              if (val == '__clear__') {
                if (current != null) {
                  widget.onClear(team, slotIdx);
                }
              } else {
                widget.onAssign(val, team, slotIdx);
              }
            },
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Manual assignment
          Text(
            'Team A',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3B82F6),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          dropdownSlot('A', 0),
          dropdownSlot('A', 1),
          const SizedBox(height: 8),
          Text(
            'Team B',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEF4444),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          dropdownSlot('B', 0),
          dropdownSlot('B', 1),
          const SizedBox(height: 12),
          // OR divider
          Row(
            children: [
              Expanded(child: Divider(color: _borderColor(context))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary(context),
                  ),
                ),
              ),
              Expanded(child: Divider(color: _borderColor(context))),
            ],
          ),
          const SizedBox(height: 12),
          // Auto-fill
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: waiting.length >= 4
                  ? () => widget.onFill(widget.courtIndex)
                  : null,
              icon: const Icon(Icons.bolt, size: 16),
              label: Text(
                waiting.length >= 4
                    ? 'Auto-fill from Queue'
                    : 'Need ${4 - waiting.length} more in queue',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _surfaceDim(context),
                disabledForegroundColor: _textSecondary(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filled court ──────────────────────────────────────────
  Widget _buildFilledBody(BuildContext context) {
    final court = widget.court!;
    final waiting = widget.session.waitingRoom;

    return Column(
      children: [
        if (_editMode && !widget.isArchived)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _gold.withOpacity(0.05),
            child: Text(
              _selectedForSwap == null
                  ? 'Tap a player to select, then tap their replacement'
                  : 'Tap a player on the opposite team — or tap a sub below',
              style: const TextStyle(fontSize: 12, color: _gold),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _TeamPanel(
                  label: 'Team A',
                  players: court.teamA,
                  color: const Color(0xFF3B82F6),
                  isWinner: _winner == true,
                  isLoser: _winner == false,
                  editMode: _editMode,
                  selectedForSwap: _selectedForSwap,
                  onTeamTap: (_editMode || widget.isArchived)
                      ? null
                      : () => setState(
                          () => _winner = _winner == true ? null : true,
                        ),
                  onPlayerTap: (_editMode && !widget.isArchived)
                      ? (pid) => _handleSwap(pid)
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Container(
                      width: 1,
                      height: 36,
                      color: _borderColor(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary(context),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: _borderColor(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _TeamPanel(
                  label: 'Team B',
                  players: court.teamB,
                  color: const Color(0xFFEF4444),
                  isWinner: _winner == false,
                  isLoser: _winner == true,
                  editMode: _editMode,
                  selectedForSwap: _selectedForSwap,
                  onTeamTap: (_editMode || widget.isArchived)
                      ? null
                      : () => setState(
                          () => _winner = _winner == false ? null : false,
                        ),
                  onPlayerTap: (_editMode && !widget.isArchived)
                      ? (pid) => _handleSwap(pid)
                      : null,
                ),
              ),
            ],
          ),
        ),

        // ── Substitution picker (edit mode only) ──────────────
        if (_editMode && !widget.isArchived && waiting.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _SubstitutePicker(
              waiting: waiting,
              enabled: _selectedForSwap != null,
              onSelected: (inId) => _handleSubstitute(inId),
            ),
          ),

        if (!widget.isArchived && !_editMode) ...[
          if (_winner == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Tap a team to declare the winner',
                style: TextStyle(fontSize: 12, color: _textSecondary(context)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _winner == null
                    ? null
                    : () => widget.onEnd(_winner!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _surfaceDim(context),
                  disabledForegroundColor: _textSecondary(context),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _winner == null
                      ? 'Select winner to end match'
                      : 'End Match  ·  ${_winner! ? "Team A" : "Team B"} wins 🏆',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _handleSwap(String pid) {
    if (_selectedForSwap == null) {
      setState(() => _selectedForSwap = pid);
    } else if (_selectedForSwap == pid) {
      setState(() => _selectedForSwap = null);
    } else {
      // Both players are on-court → cross-team swap (existing behaviour).
      widget.onSwap(_selectedForSwap!, pid);
      setState(() => _selectedForSwap = null);
    }
  }

  void _handleSubstitute(String waitingPlayerId) {
    if (_selectedForSwap == null) return;
    widget.onSubstitute(_selectedForSwap!, waitingPlayerId);
    setState(() => _selectedForSwap = null);
  }
}

class _TeamPanel extends StatelessWidget {
  final String label;
  final List<Player> players;
  final Color color;
  final bool isWinner;
  final bool isLoser;
  final bool editMode;
  final String? selectedForSwap;
  final VoidCallback? onTeamTap;
  final void Function(String)? onPlayerTap;

  const _TeamPanel({
    required this.label,
    required this.players,
    required this.color,
    required this.isWinner,
    required this.isLoser,
    required this.editMode,
    this.selectedForSwap,
    this.onTeamTap,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTeamTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWinner ? color.withOpacity(0.07) : _surfaceDim(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isWinner ? color : _borderColor(context),
            width: isWinner ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isWinner) ...[
                  Icon(Icons.emoji_events_rounded, size: 13, color: color),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isWinner ? color : _textSecondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...players.map((p) {
              final isSelected = editMode && selectedForSwap == p.id;
              return GestureDetector(
                onTap: editMode ? () => onPlayerTap?.call(p.id) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _gold.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? _gold : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: isSelected
                            ? _gold.withOpacity(0.2)
                            : color.withOpacity(isLoser ? 0.05 : 0.14),
                        child: Text(
                          p.name[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? _gold
                                : isLoser
                                ? _textSecondary(context)
                                : color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? _gold
                                    : isLoser
                                    ? _textSecondary(context)
                                    : _textPrimary(context),
                              ),
                            ),
                            Text(
                              '${p.wins}W ${p.losses}L',
                              style: TextStyle(
                                fontSize: 10,
                                color: _textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (editMode)
                        Icon(
                          isSelected ? Icons.check_circle : Icons.swap_horiz,
                          size: 14,
                          color: isSelected ? _gold : _textSecondary(context),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Tab: History ──────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final String sessionId;
  const _HistoryTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final allHistory = context.watch<QueueService>().matchHistory;
    final history = allHistory.where((r) => r.sessionId == sessionId).toList();

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_outlined,
              size: 40,
              color: _textSecondary(context),
            ),
            const SizedBox(height: 12),
            Text(
              'No matches played yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Completed matches will appear here',
              style: TextStyle(fontSize: 13, color: _textSecondary(context)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = history[i];
        final aWon = r.winnerTeam == 'A';
        final timeAgo = _timeAgo(r.playedAt);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time
              Text(
                timeAgo,
                style: TextStyle(
                  fontSize: 11,
                  color: _textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              // Teams
              Row(
                children: [
                  // Team A
                  Expanded(
                    child: _HistoryTeam(
                      names: r.teamANames,
                      won: aWon,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'vs',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Team B
                  Expanded(
                    child: _HistoryTeam(
                      names: r.teamBNames,
                      won: !aWon,
                      color: const Color(0xFFEF4444),
                      alignRight: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Winner label
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '🏆  ${aWon ? r.teamANames.join(' & ') : r.teamBNames.join(' & ')} won',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _gold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _HistoryTeam extends StatelessWidget {
  final List<String> names;
  final bool won;
  final Color color;
  final bool alignRight;
  const _HistoryTeam({
    required this.names,
    required this.won,
    required this.color,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: names
        .map(
          (name) => Row(
            mainAxisAlignment: alignRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!alignRight)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: won ? color : _textSecondary(context),
                    shape: BoxShape.circle,
                  ),
                ),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: won
                        ? _textPrimary(context)
                        : _textSecondary(context),
                  ),
                ),
              ),
              if (alignRight)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: won ? color : _textSecondary(context),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        )
        .toList(),
  );
}

// ── Tab: Session Settings ─────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final String sessionId;
  final bool isArchived;
  const _SettingsTab({required this.sessionId, required this.isArchived});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueService>();
    final session = queue.getSession(sessionId);
    if (session == null) return const SizedBox();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        _SLabel('DEFAULT COURT TYPE'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TypeChip(
                label: 'Singles',
                icon: Icons.person_outline,
                selected: session.defaultCourtType == CourtType.singles,
                onTap: isArchived
                    ? null
                    : () => queue.updateDefaultCourtType(
                        sessionId,
                        CourtType.singles,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeChip(
                label: 'Doubles',
                icon: Icons.people_outline,
                selected: session.defaultCourtType == CourtType.doubles,
                onTap: isArchived
                    ? null
                    : () => queue.updateDefaultCourtType(
                        sessionId,
                        CourtType.doubles,
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SLabel('TEAM ASSIGNMENT MODE'),
        const SizedBox(height: 12),
        ...TeamAssignmentMode.values.map((mode) {
          final sel = session.teamMode == mode;
          return GestureDetector(
            onTap: isArchived
                ? null
                : () => queue.updateTeamMode(sessionId, mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sel ? _gold.withOpacity(0.06) : _cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? _gold : _borderColor(context),
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: sel
                          ? _gold.withOpacity(0.1)
                          : _surfaceDim(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _modeIcon(mode),
                      size: 20,
                      color: sel ? _gold : _textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _modeTitle(mode),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary(context),
                          ),
                        ),
                        Text(
                          _modeDesc(mode),
                          style: TextStyle(
                            fontSize: 12,
                            color: _textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sel)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: _gold,
                      size: 20,
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  IconData _modeIcon(TeamAssignmentMode m) => switch (m) {
    TeamAssignmentMode.balanced => Icons.balance_outlined,
    TeamAssignmentMode.random => Icons.shuffle_rounded,
    TeamAssignmentMode.perLevel => Icons.military_tech_outlined,
  };

  String _modeTitle(TeamAssignmentMode m) => switch (m) {
    TeamAssignmentMode.balanced => 'Balanced',
    TeamAssignmentMode.random => 'Random',
    TeamAssignmentMode.perLevel => 'Per Level',
  };

  String _modeDesc(TeamAssignmentMode m) => switch (m) {
    TeamAssignmentMode.balanced => 'Snake draft by win rate — fairest overall',
    TeamAssignmentMode.random => 'Randomly assigned each match',
    TeamAssignmentMode.perLevel => 'Mixed skill — best + worst vs middle two',
  };
}

// ── Player stats sheet (shared by Players + Rankings tabs) ────

void _showEditPlayerDialog(
  BuildContext context,
  Player player,
  String sessionId,
  List<Player> allPlayers,
) {
  final nameCtrl = TextEditingController(text: player.name);
  SkillLevel selectedSkill = player.skill;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _borderColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Player',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary(context),
                      ),
                    ),
                  ),
                  // Delete button
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Remove Player?'),
                          content: Text(
                            'Remove ${player.name} from this session?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                context
                                    .read<QueueService>()
                                    .removePlayerFromSession(
                                      sessionId: sessionId,
                                      playerId: player.id,
                                    );
                                Navigator.pop(dCtx);
                              },
                              child: const Text(
                                'Remove',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                    label: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Label('NAME'),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(fontSize: 15, color: _textPrimary(context)),
                decoration: _inputDeco(player.name, context),
              ),
              const SizedBox(height: 20),
              _Label('SKILL LEVEL'),
              const SizedBox(height: 8),
              Row(
                children: SkillLevel.values.map((skill) {
                  final sel = selectedSkill == skill;
                  final col = _skillColor(skill);
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => set(() => selectedSkill = skill),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.only(
                          right: skill != SkillLevel.advanced ? 8 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: sel
                              ? col.withOpacity(0.12)
                              : _surfaceDim(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel ? col : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          skill.name[0].toUpperCase() + skill.name.substring(1),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? col : _textSecondary(context),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    context.read<QueueService>().updatePlayer(
                      sessionId: sessionId,
                      playerId: player.id,
                      name: name,
                      skill: selectedSkill,
                    );
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Quick-access stats
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openPlayerStats(context, player, allPlayers);
                  },
                  child: Text(
                    'View stats & head-to-head',
                    style: TextStyle(
                      fontSize: 13,
                      color: _textSecondary(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _openPlayerStats(
  BuildContext context,
  Player player,
  List<Player> allPlayers,
) {
  final opponents = allPlayers.where((p) => p.id != player.id).toList();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, ctrl) => Container(
        decoration: BoxDecoration(
          color: _cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _gold.withOpacity(0.12),
                    child: Text(
                      player.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary(context),
                          ),
                        ),
                        Text(
                          '${player.wins}W · ${player.losses}L · '
                          '${player.gamesPlayed} games',
                          style: TextStyle(
                            fontSize: 13,
                            color: _textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (player.currentStreak != 0)
                    _StreakBadge(streak: player.currentStreak),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Overall win rate',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary(context),
                        ),
                      ),
                      Text(
                        player.winRateDisplay,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: player.winRate,
                      minHeight: 6,
                      backgroundColor: _borderColor(context),
                      valueColor: const AlwaysStoppedAnimation(_gold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (opponents.any((o) => player.headToHead.containsKey(o.id))) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'HEAD-TO-HEAD',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary(context),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: opponents
                      .where((o) => player.headToHead.containsKey(o.id))
                      .map((opp) {
                        final rec = player.recordAgainst(opp.id);
                        final w = rec[0], l = rec[1];
                        final total = w + l;
                        final rate = total == 0 ? 0.0 : w / total;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _surfaceDim(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _borderColor(context)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: _borderColor(context),
                                child: Text(
                                  opp.name[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _textSecondary(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opp.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: rate,
                                        minHeight: 4,
                                        backgroundColor: _borderColor(context),
                                        valueColor: AlwaysStoppedAnimation(
                                          rate >= 0.5
                                              ? _gold
                                              : const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$w - $l',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary(context),
                                    ),
                                  ),
                                  Text(
                                    '${(rate * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: rate >= 0.5
                                          ? _gold
                                          : const Color(0xFFEF4444),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No head-to-head data yet.\nPlay some matches!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textSecondary(context),
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ── Shared widgets ────────────────────────────────────────────

class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});
  @override
  Widget build(BuildContext context) {
    final win = streak > 0;
    final color = win ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        win ? '🔥 ${streak}W' : '❄️ ${streak.abs()}L',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SkillBadge extends StatelessWidget {
  final SkillLevel skill;
  const _SkillBadge({required this.skill});
  @override
  Widget build(BuildContext context) {
    final color = _skillColor(skill);
    final label = switch (skill) {
      SkillLevel.beginner => 'BEG',
      SkillLevel.intermediate => 'INT',
      SkillLevel.advanced => 'ADV',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool inQueue;
  final bool onCourt;
  const _StatusPill({required this.inQueue, required this.onCourt});
  @override
  Widget build(BuildContext context) {
    final (label, color) = onCourt
        ? ('On Court', _gold)
        : inQueue
        ? ('In Queue', const Color(0xFF3B82F6))
        : ('Resting', const Color(0xFF94A3B8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: _textSecondary(context),
      letterSpacing: 1.2,
    ),
  );
}

class _SLabel extends StatelessWidget {
  final String text;
  const _SLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: _textSecondary(context),
      letterSpacing: 1.2,
    ),
  );
}

Color _skillColor(SkillLevel s) => switch (s) {
  SkillLevel.beginner => const Color(0xFF3B82F6),
  SkillLevel.intermediate => const Color(0xFFF59E0B),
  SkillLevel.advanced => const Color(0xFFEF4444),
};

InputDecoration _inputDeco(String hint, BuildContext ctx) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(color: _textSecondary(ctx)),
  filled: true,
  fillColor: _surfaceDim(ctx),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: _borderColor(ctx)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: _borderColor(ctx)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _gold, width: 1.5),
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
);

// ── Partner badge ─────────────────────────────────────────────

class _PartnerBadge extends StatelessWidget {
  const _PartnerBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF8B5CF6).withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.favorite, size: 9, color: Color(0xFF8B5CF6)),
        SizedBox(width: 3),
        Text(
          'Pair',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8B5CF6),
          ),
        ),
      ],
    ),
  );
}

// ── Partner button (shown on player card) ─────────────────────

class _PartnerButton extends StatelessWidget {
  final Player player;
  final List<Player> allPlayers;
  final void Function(String? partnerId) onSet;

  const _PartnerButton({
    required this.player,
    required this.allPlayers,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final hasPartner = player.preferredPartnerId != null;
    String? partnerName;
    if (hasPartner) {
      try {
        partnerName = allPlayers
            .firstWhere((p) => p.id == player.preferredPartnerId)
            .name;
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () => _showPartnerPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: hasPartner
              ? const Color(0xFF8B5CF6).withOpacity(0.1)
              : _surfaceDim(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasPartner
                ? const Color(0xFF8B5CF6).withOpacity(0.3)
                : _borderColor(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasPartner ? Icons.favorite : Icons.favorite_border,
              size: 10,
              color: hasPartner
                  ? const Color(0xFF8B5CF6)
                  : _textSecondary(context),
            ),
            const SizedBox(width: 4),
            Text(
              hasPartner ? (partnerName ?? 'Paired') : 'Set partner',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: hasPartner
                    ? const Color(0xFF8B5CF6)
                    : _textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPartnerPicker(BuildContext context) {
    final others = allPlayers.where((p) => p.id != player.id).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _borderColor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.favorite, color: Color(0xFF8B5CF6), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Preferred partner for ${player.name}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'They will always be on the same team when both are waiting.',
              style: TextStyle(fontSize: 12, color: _textSecondary(context)),
            ),
            const SizedBox(height: 16),
            // Clear option
            if (player.preferredPartnerId != null)
              ListTile(
                leading: const Icon(
                  Icons.heart_broken_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove partner',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  onSet(null);
                  Navigator.pop(context);
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            // Player list
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: others.length,
                itemBuilder: (ctx, i) {
                  final p = others[i];
                  final isCurrentPartner = player.preferredPartnerId == p.id;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: isCurrentPartner
                          ? const Color(0xFF8B5CF6).withOpacity(0.15)
                          : _surfaceDim(context),
                      child: Text(
                        p.name[0].toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isCurrentPartner
                              ? const Color(0xFF8B5CF6)
                              : _textSecondary(context),
                        ),
                      ),
                    ),
                    title: Text(
                      p.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      '${p.wins}W · ${p.losses}L',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary(context),
                      ),
                    ),
                    trailing: isCurrentPartner
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF8B5CF6),
                          )
                        : p.preferredPartnerId != null
                        ? Text(
                            'Has partner',
                            style: TextStyle(
                              fontSize: 11,
                              color: _textSecondary(context),
                            ),
                          )
                        : null,
                    onTap: () {
                      onSet(p.id);
                      Navigator.pop(context);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Court type chip ───────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _gold.withOpacity(0.08) : _cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _gold : _borderColor(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? _gold : _textSecondary(context),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? _gold : _textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Substitution picker ───────────────────────────────────────

class _SubstitutePicker extends StatefulWidget {
  final List<Player> waiting;
  final bool enabled;
  final void Function(String inId) onSelected;

  const _SubstitutePicker({
    required this.waiting,
    required this.enabled,
    required this.onSelected,
  });

  @override
  State<_SubstitutePicker> createState() => _SubstitutePickerState();
}

class _SubstitutePickerState extends State<_SubstitutePicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.waiting
        .where(
          (p) =>
              _query.isEmpty ||
              p.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: widget.enabled ? _gold.withOpacity(0.04) : _surfaceDim(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.enabled
              ? _gold.withOpacity(0.4)
              : _borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 14,
                  color: widget.enabled ? _gold : _textSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.enabled
                      ? 'Select a sub to bring in'
                      : 'Select an on-court player first',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.enabled ? _gold : _textSecondary(context),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // Search box — only shown when a player is selected
          if (widget.enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontSize: 13, color: _textPrimary(context)),
                decoration: InputDecoration(
                  hintText: 'Search queue…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: _textSecondary(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: _textSecondary(context),
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: _textSecondary(context),
                          ),
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: _surfaceDim(context),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Player list
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  'No players match',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary(context),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    final waitMins = DateTime.now()
                        .difference(p.lastWaitStartTime)
                        .inMinutes;
                    return GestureDetector(
                      onTap: () => widget.onSelected(p.id),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _cardBg(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _borderColor(context)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: _gold.withOpacity(0.12),
                              child: Text(
                                p.name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _gold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _textPrimary(context),
                                ),
                              ),
                            ),
                            Text(
                              '${waitMins}m',
                              style: TextStyle(
                                fontSize: 11,
                                color: _textSecondary(context),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _SkillBadge(skill: p.skill),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
