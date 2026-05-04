import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/queue_service.dart';
import '../models/player.dart';
import '../models/session.dart';

const _gold = Color(0xFFD4AF37);

class SessionScreen extends StatefulWidget {
  final String sessionId;
  const SessionScreen({super.key, required this.sessionId});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  int _currentTab = 0;

  static const _tabs  = ['Queue', 'Players', 'Rankings', 'Courts', 'Settings'];
  static const _icons = [
    Icons.list_alt_outlined,
    Icons.people_outline,
    Icons.leaderboard_outlined,
    Icons.sports_tennis_outlined,
    Icons.tune_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final queue   = context.watch<QueueService>();
    final session = queue.getSession(widget.sessionId);
    if (session == null) {
      return const Scaffold(body: Center(child: Text('Session not found')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(children: [
          Text(session.name.toUpperCase(),
              style: const TextStyle(fontSize: 16, letterSpacing: 1.5)),
          Text(_formatDate(session.date),
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B),
                  fontWeight: FontWeight.w400, letterSpacing: 0)),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => _showAddPlayerDialog(context, session.id),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _QueueTab(sessionId: widget.sessionId),
          _PlayersTab(sessionId: widget.sessionId,
              onAddPlayer: () => _showAddPlayerDialog(context, session.id)),
          _RankingsTab(sessionId: widget.sessionId),
          _CourtsTab(sessionId: widget.sessionId), // This uses the new upgraded tab
          _SettingsTab(sessionId: widget.sessionId),
        ],
      ),
      bottomNavigationBar: _AeroNavBar(
        currentIndex: _currentTab,
        tabs: _tabs,
        icons: _icons,
        onTap: (i) => setState(() => _currentTab = i),
      ),
      floatingActionButton: _currentTab == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                final ok = context
                    .read<QueueService>()
                    .fillCourt(sessionId: widget.sessionId);
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Need at least 4 players in the queue'),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2)),
                )),
                const Text('Add Player',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
                const SizedBox(height: 24),
                const _Label('PLAYER NAME'),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
                  decoration: _inputDeco('e.g. Alex Chen'),
                ),
                const SizedBox(height: 20),
                const _Label('SKILL LEVEL'),
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
                              right: skill != SkillLevel.advanced ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: sel ? col.withOpacity(0.12) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: sel ? col : Colors.transparent, width: 1.5),
                          ),
                          child: Text(
                            skill.name[0].toUpperCase() + skill.name.substring(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: sel ? col : const Color(0xFF64748B)),
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
                          sessionId: sessionId, name: name, skill: selectedSkill);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Add to Queue',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const wd = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}';
  }
}

// ── Nav bar ───────────────────────────────────────────────────

class _AeroNavBar extends StatelessWidget {
  final int currentIndex;
  final List<String> tabs;
  final List<IconData> icons;
  final ValueChanged<int> onTap;
  const _AeroNavBar({required this.currentIndex, required this.tabs,
      required this.icons, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 4, top: 8),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = currentIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? _gold.withOpacity(0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icons[i], size: 20,
                      color: active ? _gold : const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 2),
                Text(tabs[i], style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? _gold : const Color(0xFF94A3B8))),
              ]),
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
  const _QueueTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<QueueService>().getSession(sessionId);
    final waiting = session?.waitingRoom ?? [];

    if (waiting.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.hourglass_empty_outlined, size: 40, color: Color(0xFFCBD5E1)),
          SizedBox(height: 12),
          Text('Queue is empty', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w500, color: Color(0xFF94A3B8))),
          SizedBox(height: 4),
          Text('Add players using the icon above',
              style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1))),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: waiting.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = waiting[i];
        final waitMins = DateTime.now().difference(p.lastWaitStartTime).inMinutes;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: i == 0 ? _gold.withOpacity(0.1) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: Text('${i + 1}', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: i == 0 ? _gold : const Color(0xFF64748B)))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(p.name, style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              Text('$waitMins min wait · ${p.gamesPlayed} games',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            ])),
            if (p.currentStreak != 0) ...[
              _StreakBadge(streak: p.currentStreak),
              const SizedBox(width: 8),
            ],
            _SkillBadge(skill: p.skill),
          ]),
        );
      },
    );
  }
}

// ── Tab: Players ──────────────────────────────────────────────

class _PlayersTab extends StatelessWidget {
  final String sessionId;
  final VoidCallback onAddPlayer;
  const _PlayersTab({required this.sessionId, required this.onAddPlayer});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<QueueService>().getSession(sessionId);
    final players = session?.players ?? [];

    return Stack(children: [
      players.isEmpty
          ? const Center(child: Text('No players added yet',
              style: TextStyle(color: Color(0xFF94A3B8))))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              itemCount: players.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p       = players[i];
                final inQueue = session!.waitingRoom.any((x) => x.id == p.id);
                final onCourt = session.activeCourts
                    .any((c) => c.allPlayers.any((x) => x.id == p.id));

                return GestureDetector(
                  onTap: () => _openPlayerStatsSheet(context, p, players),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _gold.withOpacity(0.1),
                        child: Text(p.name[0].toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, color: _gold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(p.name, style: const TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                        Text('${p.wins}W · ${p.losses}L · ${p.winRateDisplay} win rate',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8))),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        _SkillBadge(skill: p.skill),
                        const SizedBox(height: 4),
                        _StatusPill(inQueue: inQueue, onCourt: onCourt),
                      ]),
                    ]),
                  ),
                );
              },
            ),
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
    ]);
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
      return const Center(child: Text('No rankings yet',
          style: TextStyle(color: Color(0xFF94A3B8))));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: players.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = players[i];
        return GestureDetector(
          onTap: () => _openPlayerStatsSheet(context, p, allPlayers),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: i < 3
                        ? _podiumColor(i).withOpacity(0.3)
                        : const Color(0xFFE2E8F0))),
            child: Row(children: [
              SizedBox(
                width: 32,
                child: Text(
                  i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}',
                  style: const TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                Text('${p.wins}W · ${p.losses}L · ${p.winRateDisplay} win rate',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ])),
              if (p.currentStreak != 0) ...[
                _StreakBadge(streak: p.currentStreak),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFCBD5E1)),
            ]),
          ),
        );
      },
    );
  }

  Color _podiumColor(int i) =>
      [const Color(0xFFF59E0B), const Color(0xFF94A3B8), const Color(0xFFCD7C2F)][i];
}

// ── Tab: Upgraded Courts (Integrated from Claude) ─────────────

class _CourtsTab extends StatelessWidget {
  final String sessionId;
  const _CourtsTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final queue   = context.watch<QueueService>();
    final session = queue.getSession(sessionId);
    if (session == null) return const SizedBox();

    final courts      = session.activeCourts;
    final courtCount  = session.courtCount;
    final totalSlots  = courts.length < courtCount ? courtCount : courts.length;

    return Stack(children: [
      ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        itemCount: totalSlots + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) {
          if (i == totalSlots) {
            return _AddCourtButton(onTap: () => queue.addCourt(sessionId));
          }
          final hasData = i < courts.length;
          return _CourtCard(
            courtIndex: i,
            court:      hasData ? courts[i] : null,
            session:    session,
            onFill: () {
              final ok = queue.fillCourt(sessionId: sessionId);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Need at least 4 players in the queue'),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            onEnd: (teamAWon) => queue.endMatch(
                sessionId: sessionId, courtIndex: i, teamAWon: teamAWon),
            onSwap: (a, b) => queue.swapPlayers(
                sessionId: sessionId, courtIndex: i,
                playerIdA: a, playerIdB: b),
            onAssign: (playerId, team, slot) =>
                queue.assignPlayerToCourt(
                    sessionId: sessionId, courtIndex: i,
                    playerId: playerId, team: team, slotIndex: slot),
            onRemove: () => queue.removeCourt(sessionId, i),
          );
        },
      ),
    ]);
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
        border: Border.all(color: _gold.withOpacity(0.4),
            width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.add_circle_outline, color: _gold.withOpacity(0.7), size: 20),
        const SizedBox(width: 8),
        Text('Add Court', style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: _gold.withOpacity(0.8))),
      ]),
    ),
  );
}

class _CourtCard extends StatefulWidget {
  final int       courtIndex;
  final Court?    court;
  final Session   session;
  final VoidCallback onFill;
  final void Function(bool) onEnd;
  final void Function(String, String) onSwap;
  final void Function(String, String, int) onAssign;
  final VoidCallback onRemove;

  const _CourtCard({
    required this.courtIndex,
    required this.court,
    required this.session,
    required this.onFill,
    required this.onEnd,
    required this.onSwap,
    required this.onAssign,
    required this.onRemove,
  });
  @override
  State<_CourtCard> createState() => _CourtCardState();
}

class _CourtCardState extends State<_CourtCard> {
  bool? _winner;
  bool  _editMode = false;
  String? _selectedForSwap;

  bool get _isEmpty => widget.court == null ||
      (widget.court!.teamA.isEmpty && widget.court!.teamB.isEmpty);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(children: [
        _buildHeader(),
        if (_isEmpty) _buildEmptyCourtBody()
        else _buildTeamsBody(),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(
              color: _isEmpty ? const Color(0xFFCBD5E1) : _gold,
              shape: BoxShape.circle,
            )),
        const SizedBox(width: 8),
        Text('Court ${widget.courtIndex + 1}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: Color(0xFF111827), letterSpacing: 0.5)),
        const Spacer(),
        if (!_isEmpty) ...[
          GestureDetector(
            onTap: () => setState(() {
              _editMode = !_editMode;
              _selectedForSwap = null;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _editMode ? _gold.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _editMode ? _gold : const Color(0xFFE2E8F0)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.swap_horiz_rounded, size: 14,
                    color: _editMode ? _gold : const Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(_editMode ? 'Done' : 'Edit',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: _editMode ? _gold : const Color(0xFF94A3B8))),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Text(_isEmpty ? 'EMPTY' : 'LIVE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _isEmpty ? const Color(0xFFCBD5E1) : _gold,
                  letterSpacing: 1.2)),
        ] else
          GestureDetector(
            onTap: widget.onRemove,
            child: const Icon(Icons.close, size: 16, color: Color(0xFFCBD5E1)),
          ),
      ]),
    );
  }

  Widget _buildEmptyCourtBody() {
    final waiting = widget.session.waitingRoom;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildManualAssign(),
        const SizedBox(height: 12),
        const _OrDivider(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: waiting.length >= 4 ? widget.onFill : null,
            icon: const Icon(Icons.bolt, size: 16),
            label: Text(waiting.length >= 4
                ? 'Auto-fill from Queue'
                : 'Need ${4 - waiting.length} more in queue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF94A3B8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildManualAssign() {
    final court   = widget.court;
    final waiting = widget.session.waitingRoom;
    final courtPlayers = court?.allPlayers ?? [];
    final available = [...waiting, ...courtPlayers];
    available.sort((a, b) => a.name.compareTo(b.name));

    Widget slot(String team, int slotIndex, Player? current) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: team == 'A'
              ? const Color(0xFF3B82F6).withOpacity(0.05)
              : const Color(0xFFEF4444).withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: team == 'A'
                  ? const Color(0xFF3B82F6).withOpacity(0.2)
                  : const Color(0xFFEF4444).withOpacity(0.2)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: current?.id,
            hint: Text('Select player',
                style: TextStyle(fontSize: 13,
                    color: team == 'A'
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFEF4444))),
            icon: Icon(Icons.keyboard_arrow_down,
                color: team == 'A'
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFFEF4444),
                size: 18),
            items: [
              const DropdownMenuItem<String>(
                  value: null, child: Text('— Empty —')),
              ...available.map((p) => DropdownMenuItem(
                value: p.id,
                child: Text(p.name,
                    style: const TextStyle(fontSize: 13)),
              )),
            ],
            onChanged: (pid) {
              if (pid == null) return;
              widget.onAssign(pid, team, slotIndex);
            },
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Team A', style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w700, color: Color(0xFF3B82F6),
          letterSpacing: 0.5)),
      const SizedBox(height: 6),
      slot('A', 0, court?.teamA.isNotEmpty == true ? court!.teamA[0] : null),
      slot('A', 1, court?.teamA.length == 2 ? court!.teamA[1] : null),
      const SizedBox(height: 8),
      const Text('Team B', style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w700, color: Color(0xFFEF4444),
          letterSpacing: 0.5)),
      const SizedBox(height: 6),
      slot('B', 0, court?.teamB.isNotEmpty == true ? court!.teamB[0] : null),
      slot('B', 1, court?.teamB.length == 2 ? court!.teamB[1] : null),
    ]);
  }

  Widget _buildTeamsBody() {
    final court = widget.court!;
    return Column(children: [
      if (_editMode)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _gold.withOpacity(0.05),
          child: Text(
            _selectedForSwap == null
                ? 'Tap a player to select for swap'
                : 'Tap another player on the opposite team',
            style: const TextStyle(fontSize: 12, color: _gold),
            textAlign: TextAlign.center,
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _TeamPanel(
            label: 'Team A',
            players: court.teamA,
            color: const Color(0xFF3B82F6),
            isWinner: _winner == true,
            isLoser:  _winner == false,
            editMode: _editMode,
            selectedForSwap: _selectedForSwap,
            onTeamTap: _editMode ? null
                : () => setState(
                    () => _winner = _winner == true ? null : true),
            onPlayerTap: _editMode
                ? (pid) => _handleSwap(pid) : null,
          )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(children: [
              Container(width: 1, height: 36,
                  color: const Color(0xFFE2E8F0)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('VS', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1),
                    letterSpacing: 1)),
              ),
              Container(width: 1, height: 36,
                  color: const Color(0xFFE2E8F0)),
            ]),
          ),
          Expanded(child: _TeamPanel(
            label: 'Team B',
            players: court.teamB,
            color: const Color(0xFFEF4444),
            isWinner: _winner == false,
            isLoser:  _winner == true,
            editMode: _editMode,
            selectedForSwap: _selectedForSwap,
            onTeamTap: _editMode ? null
                : () => setState(
                    () => _winner = _winner == false ? null : false),
            onPlayerTap: _editMode
                ? (pid) => _handleSwap(pid) : null,
          )),
        ]),
      ),
      if (!_editMode) ...[
        if (_winner == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Tap a team to declare the winner',
                style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _winner == null ? null : () => widget.onEnd(_winner!),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                disabledForegroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                _winner == null
                    ? 'Select winner to end match'
                    : 'End Match  ·  ${_winner! ? "Team A" : "Team B"} wins 🏆',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  void _handleSwap(String pid) {
    if (_selectedForSwap == null) {
      setState(() => _selectedForSwap = pid);
    } else if (_selectedForSwap == pid) {
      setState(() => _selectedForSwap = null);
    } else {
      widget.onSwap(_selectedForSwap!, pid);
      setState(() => _selectedForSwap = null);
    }
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
  final void Function(String playerId)? onPlayerTap;

  const _TeamPanel({
    required this.label, required this.players, required this.color,
    required this.isWinner, required this.isLoser,
    required this.editMode, this.selectedForSwap,
    this.onTeamTap, this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTeamTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWinner ? color.withOpacity(0.07) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isWinner ? color : const Color(0xFFE2E8F0),
              width: isWinner ? 1.5 : 1),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isWinner) ...[
              Icon(Icons.emoji_events_rounded, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isWinner ? color : const Color(0xFF94A3B8))),
          ]),
          const SizedBox(height: 10),
          ...players.map((p) {
            final isSelected = editMode && selectedForSwap == p.id;
            return GestureDetector(
              onTap: editMode ? () => onPlayerTap?.call(p.id) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? _gold.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? _gold : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: isSelected
                        ? _gold.withOpacity(0.2)
                        : color.withOpacity(isLoser ? 0.05 : 0.14),
                    child: Text(p.name[0].toUpperCase(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: isSelected ? _gold
                                : isLoser ? const Color(0xFFCBD5E1) : color)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                            color: isSelected ? _gold
                                : isLoser ? const Color(0xFFCBD5E1)
                                : const Color(0xFF374151))),
                    Text('${p.wins}W ${p.losses}L',
                        style: TextStyle(fontSize: 10,
                            color: isLoser ? const Color(0xFFE2E8F0)
                                : const Color(0xFF94A3B8))),
                  ])),
                  if (editMode)
                    Icon(isSelected ? Icons.check_circle : Icons.swap_horiz,
                        size: 14,
                        color: isSelected ? _gold : const Color(0xFFCBD5E1)),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }
}

// ── Tab: Settings ─────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final String sessionId;
  const _SettingsTab({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final queue   = context.watch<QueueService>();
    final session = queue.getSession(sessionId);
    if (session == null) return const SizedBox();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        const _Label('TEAM ASSIGNMENT MODE'),
        const SizedBox(height: 12),
        ...TeamAssignmentMode.values.map((mode) {
          final sel = session.teamMode == mode;
          return GestureDetector(
            onTap: () => queue.updateTeamMode(sessionId, mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sel ? _gold.withOpacity(0.06) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: sel ? _gold : const Color(0xFFE2E8F0),
                    width: sel ? 1.5 : 1),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: sel ? _gold.withOpacity(0.1) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(_modeIcon(mode), size: 20,
                      color: sel ? _gold : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_modeTitle(mode), style: TextStyle(fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: sel ? const Color(0xFF111827) : const Color(0xFF374151))),
                  Text(_modeDesc(mode),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                ])),
                if (sel)
                  const Icon(Icons.check_circle_rounded, color: _gold, size: 20),
              ]),
            ),
          );
        }),
      ],
    );
  }

  IconData _modeIcon(TeamAssignmentMode m) => switch (m) {
        TeamAssignmentMode.balanced => Icons.balance_outlined,
        TeamAssignmentMode.random   => Icons.shuffle_rounded,
        TeamAssignmentMode.perLevel => Icons.military_tech_outlined,
      };
  String _modeTitle(TeamAssignmentMode m) => switch (m) {
        TeamAssignmentMode.balanced => 'Balanced',
        TeamAssignmentMode.random   => 'Random',
        TeamAssignmentMode.perLevel => 'Per Level',
      };
  String _modeDesc(TeamAssignmentMode m) => switch (m) {
        TeamAssignmentMode.balanced => 'Snake draft by win rate — fairest overall',
        TeamAssignmentMode.random   => 'Randomly assigned each match',
        TeamAssignmentMode.perLevel => 'Mixed skill — best + worst vs middle two',
      };
}

// ── Shared widgets & Helper methods ───────────────────────────

void _openPlayerStatsSheet(BuildContext context, Player player, List<Player> allPlayers) {
  final opponents = allPlayers.where((p) => p.id != player.id).toList();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _gold.withOpacity(0.12),
                child: Text(player.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 18,
                        fontWeight: FontWeight.w700, color: _gold)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(player.name, style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                Text('${player.wins}W · ${player.losses}L · '
                    '${player.gamesPlayed} games',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              ])),
              if (player.currentStreak != 0)
                _StreakBadge(streak: player.currentStreak),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Overall win rate',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B))),
                Text(player.winRateDisplay,
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: _gold)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: player.winRate,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation(_gold),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          if (opponents.any((o) => player.headToHead.containsKey(o.id))) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('HEAD-TO-HEAD',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8), letterSpacing: 1.2))),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: opponents
                    .where((o) => player.headToHead.containsKey(o.id))
                    .map((opp) {
                  final record = player.recordAgainst(opp.id);
                  final w = record[0], l = record[1];
                  final total = w + l;
                  final rate = total == 0 ? 0.0 : w / total;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFE2E8F0),
                        child: Text(opp.name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(opp.name, style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: rate,
                            minHeight: 4,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation(
                                rate >= 0.5 ? _gold : const Color(0xFFEF4444)),
                          ),
                        ),
                      ])),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        Text('$w - $l', style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                        Text('${(rate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                color: rate >= 0.5 ? _gold : const Color(0xFFEF4444))),
                      ]),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No head-to-head data yet.\nPlay some matches!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
            ),
        ]),
      ),
    ),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Text('or', style: TextStyle(
          fontSize: 12, color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w500)),
    ),
    const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
  ]);
}

class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});
  @override
  Widget build(BuildContext context) {
    final win   = streak > 0;
    final color = win ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(win ? '🔥 ${streak}W' : '❄️ ${streak.abs()}L',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
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
      SkillLevel.beginner     => 'BEG',
      SkillLevel.intermediate => 'INT',
      SkillLevel.advanced     => 'ADV',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: color, letterSpacing: 0.8)),
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
      decoration: BoxDecoration(color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: color, letterSpacing: 0.5)),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: Color(0xFF94A3B8), letterSpacing: 1.2));
}

Color _skillColor(SkillLevel s) => switch (s) {
      SkillLevel.beginner     => const Color(0xFF3B82F6),
      SkillLevel.intermediate => const Color(0xFFF59E0B),
      SkillLevel.advanced     => const Color(0xFFEF4444),
    };

InputDecoration _inputDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );