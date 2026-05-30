import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/mosque_profile.dart';
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
        _buildSummaryItem('Saldo Bulan Ini', income - expense, PdfColors.blue),
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
