import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/mosque_profile.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

@lazySingleton
class PdfService {
  Future<void> generateReport({
    required List<Transaction> transactions,
    required String period,
    required double totalIncome,
    required double totalExpense,
    MosqueProfile? profile,
    String? title,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();

    pw.MemoryImage? logoImage;
    try {
      if (profile?.logoUrl != null) {
        final request = await HttpClient().getUrl(Uri.parse(profile!.logoUrl!));
        final response = await request.close();
        final bytes = await response.expand((element) => element).toList();
        logoImage = pw.MemoryImage(Uint8List.fromList(bytes));
      } else if (profile?.logoPath != null) {
        final file = File(profile!.logoPath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          logoImage = pw.MemoryImage(bytes);
        }
      }
    } catch (e) {
      debugPrint('Error loading logo for PDF: $e');
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return [
            _buildHeader(period, profile, title, logoImage),
            pw.SizedBox(height: 20),
            _buildSummary(totalIncome, totalExpense),
            pw.SizedBox(height: 20),
            _buildTransactionTable(transactions),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Laporan_Kas_${DateFormat('dd_MM_yyyy').format(DateTime.now())}',
    );
  }

  Future<void> generateQurbanReport({
    required List<QurbanParticipantProgress> progress,
    required QurbanSummary summary,
    MosqueProfile? profile,
    String period = 'Progress Iuran Qurban',
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();
    final logoImage = await _loadLogo(profile);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return [
            _buildHeader(period, profile, 'Laporan Iuran Qurban', logoImage),
            pw.SizedBox(height: 20),
            _buildQurbanSummary(summary),
            pw.SizedBox(height: 20),
            _buildQurbanParticipantTable(progress),
            pw.SizedBox(height: 20),
            _buildQurbanPaymentTable(progress),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Laporan_Qurban_${DateFormat('dd_MM_yyyy').format(DateTime.now())}',
    );
  }

  pw.Widget _buildHeader(
    String period,
    MosqueProfile? profile,
    String? title,
    pw.MemoryImage? logo,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Container(
                width: 60,
                height: 60,
                margin: const pw.EdgeInsets.only(right: 16),
                child: pw.Image(logo),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (profile != null) ...[
                    pw.Text(
                      profile.name,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (profile.address != null)
                      pw.Text(
                        profile.address!,
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey700,
                        ),
                      ),
                    pw.SizedBox(height: 8),
                  ] else
                    pw.Text(
                      title ?? 'Laporan Kas Masjid',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.Text(period, style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _buildSummary(double income, double expense) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _buildSummaryItem('Total Pemasukan', income, PdfColors.green),
        _buildSummaryItem('Total Pengeluaran', expense, PdfColors.red),
        // "Periode Ini", not "Bulan Ini": generateReport() receives the totals
        // of whatever the user filtered, which is frequently all-time or a
        // custom range. The numbers were right; the label lied.
        _buildSummaryItem('Saldo Periode Ini', income - expense, PdfColors.blue),
      ],
    );
  }

  pw.Widget _buildSummaryItem(String title, double amount, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.Text(
          NumberFormat.currency(locale: 'id', symbol: 'Rp ').format(amount),
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<pw.MemoryImage?> _loadLogo(MosqueProfile? profile) async {
    try {
      if (profile?.logoUrl != null) {
        final request = await HttpClient().getUrl(Uri.parse(profile!.logoUrl!));
        final response = await request.close();
        final bytes = await response.expand((element) => element).toList();
        return pw.MemoryImage(Uint8List.fromList(bytes));
      } else if (profile?.logoPath != null) {
        final file = File(profile!.logoPath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          return pw.MemoryImage(bytes);
        }
      }
    } catch (e) {
      debugPrint('Error loading logo for PDF: $e');
    }
    return null;
  }

  pw.Widget _buildQurbanSummary(QurbanSummary summary) {
    return pw.Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _buildSummaryItem('Total Target', summary.totalTarget, PdfColors.blue),
        _buildSummaryItem('Terkumpul', summary.totalCollected, PdfColors.green),
        _buildSummaryItem('Sisa', summary.totalRemaining, PdfColors.orange),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Peserta / Lunas / Tunggakan',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Text(
              '${summary.participantCount} / ${summary.paidOffCount} / ${summary.overdueCount}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildQurbanParticipantTable(
    List<QurbanParticipantProgress> progress,
  ) {
    final data = progress.map((item) {
      final participant = item.participant;
      return [
        participant.name,
        NumberFormat.currency(
          locale: 'id',
          symbol: '',
          decimalDigits: 0,
        ).format(participant.monthlyAmount),
        '${participant.totalMonths} bln',
        NumberFormat.currency(
          locale: 'id',
          symbol: '',
          decimalDigits: 0,
        ).format(item.targetAmount),
        NumberFormat.currency(
          locale: 'id',
          symbol: '',
          decimalDigits: 0,
        ).format(item.paidAmount),
        _qurbanStatusLabel(item.status),
      ];
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Daftar Peserta',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Nama', 'Cicilan', 'Durasi', 'Target', 'Bayar', 'Status'],
          data: data,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.center,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerLeft,
          },
        ),
      ],
    );
  }

  pw.Widget _buildQurbanPaymentTable(List<QurbanParticipantProgress> progress) {
    final rows = <List<String>>[];
    for (final item in progress) {
      final payments = [...item.payments]
        ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
      final shown = payments.take(5).toList();
      for (final payment in shown) {
        rows.add([
          DateFormat('dd/MM/yy').format(payment.paymentDate),
          item.participant.name,
          NumberFormat.currency(
            locale: 'id',
            symbol: '',
            decimalDigits: 0,
          ).format(payment.amount),
          payment.note ?? '',
        ]);
      }
      // This table is scoped to the 5 most recent payments per participant
      // (see title below) -- make the cutoff visible instead of silently
      // dropping older history, so a reader doesn't mistake it for complete.
      final omitted = payments.length - shown.length;
      if (omitted > 0) {
        rows.add([
          '',
          item.participant.name,
          '',
          '+$omitted pembayaran lainnya tidak ditampilkan',
        ]);
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Histori Pembayaran Terbaru',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        if (rows.isEmpty)
          pw.Text('Belum ada pembayaran')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Tanggal', 'Nama', 'Nominal', 'Catatan'],
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerLeft,
            },
          ),
      ],
    );
  }

  String _qurbanStatusLabel(QurbanProgressStatus status) {
    switch (status) {
      case QurbanProgressStatus.notStarted:
        return 'Belum mulai';
      case QurbanProgressStatus.current:
        return 'Lancar';
      case QurbanProgressStatus.overdue:
        return 'Menunggak';
      case QurbanProgressStatus.paidOff:
        return 'Lunas';
      case QurbanProgressStatus.overpaid:
        return 'Lebih bayar';
    }
  }

  pw.Widget _buildTransactionTable(List<Transaction> transactions) {
    final headers = ['Tanggal', 'Kategori', 'Ket', 'Masuk', 'Keluar'];

    final data = transactions.map((t) {
      final isIncome = t.type == TransactionType.income;
      return [
        DateFormat('dd/MM/yy').format(t.date),
        t.category,
        t.description ?? '',
        isIncome
            ? NumberFormat.currency(
                locale: 'id',
                symbol: '',
                decimalDigits: 0,
              ).format(t.amount)
            : '-',
        !isIncome
            ? NumberFormat.currency(
                locale: 'id',
                symbol: '',
                decimalDigits: 0,
              ).format(t.amount)
            : '-',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellHeight: 30,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
    );
  }
}
