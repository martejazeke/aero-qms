import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/queue_service.dart';
import '../models/player.dart';
import 'package:printing/printing.dart';



const _gold = Color(0xFFD4AF37);

String _formatSummaryDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return '${weekdays[date.weekday - 1]}, ${date.day} '
      '${months[date.month - 1]} ${date.year}';
}

class SessionSummaryScreen extends StatelessWidget {
  final String sessionId;
  const SessionSummaryScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final queue = context.read<QueueService>();
    final summary = queue.buildSessionSummary(sessionId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SESSION SUMMARY'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareAsPdf(context, summary),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _SummaryContent(summary: summary, isDark: isDark),
      ),
    );
  }

  Future<void> _shareAsPdf(
      BuildContext context, SessionSummary summary) async {
    try {
      final pdfDoc = await _buildPdfDocument(summary);
      final bytes  = await pdfDoc.save();

      final safeName = summary.sessionName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();

      await Printing.sharePdf(
        bytes: bytes,
        filename: '${safeName}_summary.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export PDF: $e')),
        );
      }
    }
  }

  Future<pw.Document> _buildPdfDocument(SessionSummary summary) async {
    final pdf = pw.Document();
    final gold = PdfColor.fromHex('#D4AF37');
    final grey = PdfColors.grey600;
    final date = _formatSummaryDate(summary.sessionDate);

    final logoBytes = await rootBundle.load(
      'assets/images/logo_text_light.png',
    );
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      summary.sessionName,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: gold,
                      ),
                    ),
                    pw.Text(
                      date,
                      style: pw.TextStyle(fontSize: 11, color: grey),
                    ),
                  ],
                ),
                pw.Image(logoImage, height: 32),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: gold, thickness: 1.5),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (ctx) => [
          // ── Overview ──────────────────────────────────────
          pw.Text(
            'OVERVIEW',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: grey,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _pdfStatBox(
                'Total Matches Played',
                '${summary.totalMatches}',
                gold,
              ),
              pw.SizedBox(width: 8),
              _pdfStatBox('Players', '${summary.totalPlayers}', gold),
              pw.SizedBox(width: 8),
              _pdfStatBox('Court Time', summary.totalTimeFormatted, gold),
              pw.SizedBox(width: 8),
              _pdfStatBox('Avg Match', summary.avgTimeFormatted, gold),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Awards ────────────────────────────────────────
          pw.Text(
            'AWARDS',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: grey,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 8),
          if (summary.mostWins.isNotEmpty)
            _pdfAwardRow(
              'Most Wins',
              summary.mostWins.map((p) => p.name).join(', '),
              '${summary.mostWins.first.wins} wins',
              gold,
            ),
          if (summary.bestWinRate.isNotEmpty)
            _pdfAwardRow(
              'Best Win Rate',
              summary.bestWinRate.map((p) => p.name).join(', '),
              summary.bestWinRate.first.winRateDisplay,
              gold,
            ),
          if (summary.mostGames.isNotEmpty)
            _pdfAwardRow(
              'Most Games Played',
              summary.mostGames.map((p) => p.name).join(', '),
              '${summary.mostGames.first.gamesPlayed} games',
              gold,
            ),
          if (summary.longestStreak.isNotEmpty)
            _pdfAwardRow(
              'Longest Win Streak',
              summary.longestStreak.map((p) => p.name).join(', '),
              '${summary.longestStreak.first.currentStreak} in a row',
              gold,
            ),
          if (summary.bestPartnerA != null && summary.bestPartnerB != null)
            _pdfAwardRow(
              'Best Pair',
              '${summary.bestPartnerA} & ${summary.bestPartnerB}',
              '${summary.bestPairWins} wins together',
              gold,
            ),
          pw.SizedBox(height: 20),

          // ── Leaderboard ───────────────────────────────────
          pw.Text(
            'LEADERBOARD',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: grey,
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(50),
              4: const pw.FixedColumnWidth(55),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FDF8E7'),
                ),
                children: [
                  _pdfTableCell('#', bold: true, color: grey),
                  _pdfTableCell('Player', bold: true, color: grey),
                  _pdfTableCell('Wins', bold: true, color: grey),
                  _pdfTableCell('Losses', bold: true, color: grey),
                  _pdfTableCell('Win %', bold: true, color: grey),
                ],
              ),
              // Player rows
              ...summary.allPlayers.asMap().entries.map((e) {
                final isFirst =
                    e.value.wins == summary.allPlayers.first.wins &&
                    e.value.winRate == summary.allPlayers.first.winRate;
                return pw.TableRow(
                  decoration: isFirst
                      ? pw.BoxDecoration(color: PdfColor.fromHex('#FFFBEF'))
                      : null,
                  children: [
                    _pdfTableCell(
                      '${e.key + 1}',
                      bold: isFirst,
                      color: isFirst ? gold : null,
                    ),
                    _pdfTableCell(e.value.name, bold: isFirst),
                    _pdfTableCell('${e.value.wins}'),
                    _pdfTableCell('${e.value.losses}'),
                    _pdfTableCell(
                      e.value.winRateDisplay,
                      bold: true,
                      color: gold,
                    ),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Center(
            child: pw.Text(
              'Generated by Aero QMS',
              style: pw.TextStyle(
                fontSize: 9,
                color: grey,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
    return pdf;
  }

  // ── PDF helper widgets ──────────────────────────────────────

  pw.Widget _pdfStatBox(String label, String value, PdfColor gold) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: gold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                label,
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      );

  pw.Widget _pdfAwardRow(
    String title,
    String name,
    String value,
    PdfColor gold,
  ) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              name,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#FDF8E7'),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: gold,
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget _pdfTableCell(String text, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );
}

// ── Summary content (also used for image export) ──────────────

class _SummaryContent extends StatelessWidget {
  final SessionSummary summary;
  final bool isDark;
  const _SummaryContent({required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.sessionName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatSummaryDate(summary.sessionDate),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Overview stats row
        Row(
          children: [
            _StatBox(
              label: 'Matches',
              value: '${summary.totalMatches}',
              isDark: isDark,
            ),
            const SizedBox(width: 10),
            _StatBox(
              label: 'Players',
              value: '${summary.totalPlayers}',
              isDark: isDark,
            ),
            const SizedBox(width: 10),
            _StatBox(
              label: 'Court Time',
              value: summary.totalTimeFormatted,
              isDark: isDark,
            ),
            const SizedBox(width: 10),
            _StatBox(
              label: 'Avg Match',
              value: summary.avgTimeFormatted,
              isDark: isDark,
            ),
          ],
        ),
        const SizedBox(height: 20),

        _SectionHeader('🏆  AWARDS'),
        const SizedBox(height: 10),

        if (summary.mostWins.isNotEmpty)
          _AwardCard(
            emoji: '🏆',
            title: 'Most Wins',
            names: summary.mostWins.map((p) => p.name).toList(),
            subtitle: '${summary.mostWins.first.wins} wins',
            isDark: isDark,
          ),
        if (summary.bestWinRate.isNotEmpty)
          _AwardCard(
            emoji: '🎯',
            title: 'Best Win Rate',
            names: summary.bestWinRate.map((p) => p.name).toList(),
            subtitle: summary.bestWinRate.first.winRateDisplay,
            isDark: isDark,
          ),
        if (summary.mostGames.isNotEmpty)
          _AwardCard(
            emoji: '🏸',
            title: 'Most Games Played',
            names: summary.mostGames.map((p) => p.name).toList(),
            subtitle: '${summary.mostGames.first.gamesPlayed} games',
            isDark: isDark,
          ),
        if (summary.longestStreak.isNotEmpty)
          _AwardCard(
            emoji: '🔥',
            title: 'Longest Win Streak',
            names: summary.longestStreak.map((p) => p.name).toList(),
            subtitle: '${summary.longestStreak.first.currentStreak} in a row',
            isDark: isDark,
          ),
        if (summary.bestPartnerA != null && summary.bestPartnerB != null)
          _AwardCard(
            emoji: '🤝',
            title: 'Best Pair',
            names: ['${summary.bestPartnerA} & ${summary.bestPartnerB}'],
            subtitle: '${summary.bestPairWins} wins together',
            isDark: isDark,
          ),

        const SizedBox(height: 20),
        _SectionHeader('📊  LEADERBOARD'),
        const SizedBox(height: 10),

        ...summary.allPlayers.asMap().entries.map((e) {
          final isTop =
              e.value.wins == summary.allPlayers.first.wins &&
              e.value.winRate == summary.allPlayers.first.winRate;
          return _LeaderboardRow(
            rank: e.key + 1,
            player: e.value,
            isDark: isDark,
            isTopRank: isTop,
          );
        }),

        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF94A3B8),
      letterSpacing: 1.4,
    ),
  );
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final bool isDark;
  const _StatBox({
    required this.label,
    required this.value,
    required this.isDark,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _gold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AwardCard extends StatelessWidget {
  final String emoji;
  final String title;
  final List<String> names;
  final String subtitle;
  final bool isDark;

  const _AwardCard({
    required this.emoji,
    required this.title,
    required this.names,
    required this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1F2937) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0),
      ),
    ),
    child: Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              // Show all tied players
              Text(
                names.join(', '),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              // If more than one, show tied label
              if (names.length > 1)
                Text(
                  '${names.length}-way tie',
                  style: const TextStyle(
                    fontSize: 10,
                    color: _gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _gold,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final Player player;
  final bool isDark;
  final bool isTopRank;
  const _LeaderboardRow({
    required this.rank,
    required this.player,
    required this.isDark,
    required this.isTopRank,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: isTopRank
          ? _gold.withValues(alpha: 0.06)
          : isDark
          ? const Color(0xFF1F2937)
          : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isTopRank
            ? _gold.withValues(alpha: 0.3)
            : isDark
            ? const Color(0xFF374151)
            : const Color(0xFFE2E8F0),
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isTopRank
                  ? _gold
                  : isDark
                  ? Colors.white54
                  : Colors.black38,
            ),
          ),
        ),
        Expanded(
          child: Text(
            player.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF111827),
            ),
          ),
        ),
        Text(
          '${player.wins}W  ${player.losses}L',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          player.winRateDisplay,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _gold,
          ),
        ),
      ],
    ),
  );
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: _gold, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
