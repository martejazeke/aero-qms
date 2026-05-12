// lib/views/home_screen.dart

import 'package:aero/views/session_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../models/session.dart';
import '../services/queue_service.dart';
import '../services/settings_service.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

const _gold = Color(0xFFD4AF37);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (queue.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }

    final sessions = _showArchived
        ? queue.archivedSessions
        : queue.activeSessions;

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          isDark
              ? 'assets/images/logo_text_dark.png'
              : 'assets/images/logo_text_light.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        centerTitle: false,
        actions: [
          // Archive toggle
          IconButton(
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            tooltip: _showArchived ? 'Active' : 'Archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab strip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _TabChip(
                  label: 'Active',
                  count: queue.activeSessions.length,
                  selected: !_showArchived,
                  onTap: () => setState(() => _showArchived = false),
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: 'Archived',
                  count: queue.archivedSessions.length,
                  selected: _showArchived,
                  onTap: () => setState(() => _showArchived = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: sessions.isEmpty
                ? _EmptyState(archived: _showArchived)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: sessions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (ctx, i) =>
                        _SessionCard(session: sessions[i], isDark: isDark),
                  ),
          ),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateSessionDialog(context),
              label: const Text('New Session'),
              icon: const Icon(Icons.add),
              backgroundColor: _gold,
              foregroundColor: Colors.white,
            ),
    );
  }

  void _showCreateSessionDialog(BuildContext context) {
    final settings = context.read<SettingsService>();
    final nameCtrl = TextEditingController();
    DateTime selDate = DateTime.now();
    int courtCount = settings.defaultCourts;
    String teamMode = settings.defaultTeamMode;
    String courtType = settings.defaultCourtType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateSessionSheet(
        nameController: nameCtrl,
        initialDate: selDate,
        initialCourtCount: courtCount,
        initialTeamMode: teamMode,
        initialCourtType: courtType,
        onConfirm: (name, date, courts, mode, courtType) {
          final tm = TeamAssignmentMode.values.byName(mode);
          final ct = courtType == 'singles'
              ? CourtType.singles
              : CourtType.doubles;
          context.read<QueueService>().createSession(
            name: name,
            date: date,
            courtCount: courts,
            teamMode: tm,
            defaultCourtType: ct,
          );
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ── Tab chip ──────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _gold : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          '$label  $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}

// ── Session card ──────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final Session session;
  final bool isDark;
  const _SessionCard({required this.session, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(session.date);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SessionScreen(sessionId: session.id)),
      ),
      onLongPress: () => _showCardMenu(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: session.isEnded
                ? const Color(0xFFE2E8F0)
                : isToday
                ? _gold.withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
            width: isToday && !session.isEnded ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (session.isEnded)
                  _Pill('ENDED', const Color(0xFF94A3B8))
                else if (isToday)
                  _Pill('TODAY', _gold),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(session.date),
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatChip(
                  Icons.people_outline,
                  '${session.playerCount} players',
                ),
                const SizedBox(width: 10),
                _StatChip(
                  Icons.sports_tennis_outlined,
                  '${session.courtCount} courts',
                ),
                if (session.activeCourts.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _StatChip(
                    Icons.sports_outlined,
                    '${session.activeCourts.length} live',
                  ),
                ],
              ],
            ),
            if (session.isEnded) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionSummaryScreen(sessionId: session.id),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 14, color: _gold),
                      SizedBox(width: 6),
                      Text(
                        'View Summary',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _gold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCardMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              session.name,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 20),
            if (!session.isEnded)
              _MenuOption(
                icon: Icons.stop_circle_outlined,
                label: 'End Session',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(context);
                  _confirmEnd(context);
                },
              ),
            _MenuOption(
              icon: Icons.delete_outline,
              label: 'Delete Session',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmEnd(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
          'The session will be archived. All player stats are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<QueueService>().endSession(session.id);
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SessionSummaryScreen(sessionId: session.id),
                ),
              );
            },
            child: const Text(
              'End',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: const Text('This cannot be undone. All data will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<QueueService>().deleteSession(session.id);
              Navigator.pop(ctx);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
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
    return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool archived;
  const _EmptyState({required this.archived});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            archived
                ? Icons.inventory_2_outlined
                : Icons.sports_tennis_outlined,
            size: 32,
            color: _gold,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          archived ? 'No archived sessions' : 'No sessions yet',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          archived
              ? 'Ended sessions will appear here'
              : 'Tap New Session to get started',
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
      ],
    ),
  );
}

// ── Create session sheet ──────────────────────────────────────

class _CreateSessionSheet extends StatefulWidget {
  final TextEditingController nameController;
  final DateTime initialDate;
  final int initialCourtCount;
  final String initialTeamMode;
  final String initialCourtType;
  final void Function(String, DateTime, int, String, String) onConfirm;

  const _CreateSessionSheet({
    required this.nameController,
    required this.initialDate,
    required this.initialCourtCount,
    required this.initialTeamMode,
    required this.initialCourtType,
    required this.onConfirm,
  });
  @override
  State<_CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<_CreateSessionSheet> {
  late DateTime _date;
  late int _courts;
  late String _teamMode;
  late String _courtType;

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
    return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _courts = widget.initialCourtCount;
    _teamMode = widget.initialTeamMode;
    _courtType = widget.initialCourtType;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
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
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'New Session',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 24),

              const _SheetLabel('SESSION NAME'),
              const SizedBox(height: 8),
              TextField(
                controller: widget.nameController,
                autofocus: true,
                decoration: _inputDeco('e.g. Friday Night Session'),
              ),
              const SizedBox(height: 20),

              const _SheetLabel('DATE'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(primary: _gold),
                      ),
                      child: child!,
                    ),
                  );
                  if (p != null) setState(() => _date = p);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatDate(_date),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const _SheetLabel('NUMBER OF COURTS'),
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  6,
                  (i) => GestureDetector(
                    onTap: () => setState(() => _courts = i + 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _courts == i + 1
                            ? _gold
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _courts == i + 1
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const _SheetLabel('COURT TYPE'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _courtType = 'singles'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _courtType == 'singles'
                              ? _gold.withValues(alpha: 0.1)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _courtType == 'singles'
                                ? _gold
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 20,
                              color: _courtType == 'singles'
                                  ? _gold
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Singles',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _courtType == 'singles'
                                    ? _gold
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _courtType = 'doubles'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _courtType == 'doubles'
                              ? _gold.withValues(alpha: 0.1)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _courtType == 'doubles'
                                ? _gold
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 20,
                              color: _courtType == 'doubles'
                                  ? _gold
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Doubles',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _courtType == 'doubles'
                                    ? _gold
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const _SheetLabel('TEAM MODE'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ModeChip(
                    'balanced',
                    'Balanced',
                    _teamMode,
                    (v) => setState(() => _teamMode = v),
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    'random',
                    'Random',
                    _teamMode,
                    (v) => setState(() => _teamMode = v),
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    'perLevel',
                    'Per Level',
                    _teamMode,
                    (v) => setState(() => _teamMode = v),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final name = widget.nameController.text.trim();
                    if (name.isEmpty) return;
                    widget.onConfirm(
                      name,
                      _date,
                      _courts,
                      _teamMode,
                      _courtType,
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
                    'Create Session',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String value, label, current;
  final ValueChanged<String> onTap;
  const _ModeChip(this.value, this.label, this.current, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? _gold.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? _gold : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: sel ? _gold : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Color(0xFF94A3B8),
      letterSpacing: 1.2,
    ),
  );
}

InputDecoration _inputDeco(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
  filled: true,
  fillColor: const Color(0xFFF8FAFC),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _gold, width: 1.5),
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
);
