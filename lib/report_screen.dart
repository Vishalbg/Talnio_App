import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'auth_provider.dart';
import 'dart:io';
// Import the new package for opening files
import 'package:open_file_plus/open_file_plus.dart';

class ReportScreen extends StatefulWidget {
  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with SingleTickerProviderStateMixin {
  final TextEditingController reportController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  TabController? _tabController;
  bool _isLoading = false;
  bool isDownloading = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.role == 'manager' || authProvider.role == 'admin') {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    reportController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (reportController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report cannot be empty'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection('reports').doc().set({
        'userId': user.uid,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'report': reportController.text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Report submitted successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      reportController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit report: $e'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  // This function is no longer needed as we don't require special storage permissions.
  // Future<bool> _requestStoragePermission() async { ... }

  void _showDownloadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Download Daily Report',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Select the period for your report',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 20),
                      _buildReportOption(
                        icon: Icons.today,
                        title: 'Daily Report',
                        subtitle: 'Selected date\'s reports',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(0);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_view_day,
                        title: '1 Month Report',
                        subtitle: 'Current month reports',
                        color: Colors.green,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(1);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_view_week,
                        title: '2 Months Report',
                        subtitle: 'Last 2 months reports',
                        color: Colors.orange,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(2);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_today,
                        title: '3 Months Report',
                        subtitle: 'Last 3 months reports',
                        color: Colors.purple,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(3);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.date_range,
                        title: '6 Months Report',
                        subtitle: 'Last 6 months reports',
                        color: Colors.red,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(6);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_view_month,
                        title: '12 Months Report',
                        subtitle: 'Last 12 months reports',
                        color: Colors.teal,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(12);
                        },
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  // UPDATED: New function to save the file and open it.
  Future<void> _saveAndOpenFile(List<int> bytes, String fileName) async {
    try {
      // Get the public downloads directory using the correct modern method.
      final Directory? directory = await getDownloadsDirectory();

      if (directory == null) {
        throw Exception("Could not get the downloads directory.");
      }

      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);

      // Write the file bytes.
      await file.writeAsBytes(bytes, flush: true);

      // Open the file.
      final OpenResult result = await OpenFile.open(filePath);

      if (result.type != ResultType.done) {
        throw Exception('Could not open the file: ${result.message}');
      }
    } catch (e) {
      rethrow; // Rethrow the exception to be caught in _downloadReport
    }
  }

  // UPDATED: This function now uses the new save method.
  Future<void> _downloadReport(int months) async {
    setState(() {
      isDownloading = true;
    });

    try {
      // We no longer need to request storage permission here.
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No authenticated user. Please sign in again.')),
          );
        }
        return;
      }

      DateTime endDate = months == 0
          ? selectedDate
          : DateTime(selectedDate.year, selectedDate.month + 1, 0);
      DateTime startDate = months == 0
          ? selectedDate
          : DateTime(selectedDate.year, selectedDate.month - months + 1, 1);

      List<QueryDocumentSnapshot<Map<String, dynamic>>> reportDocs = [];

      if (authProvider.role != 'admin') {
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('managerId', isEqualTo: currentUserId)
            .get();
        final employeeIds = userQuery.docs.map((doc) => doc.id).toList();

        if (employeeIds.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No employees assigned to you')),
            );
          }
          return;
        }

        const int chunkSize = 10;
        for (int i = 0; i < employeeIds.length; i += chunkSize) {
          final chunk = employeeIds.sublist(
            i,
            i + chunkSize > employeeIds.length ? employeeIds.length : i + chunkSize,
          );

          try {
            final querySnapshot = await FirebaseFirestore.instance
                .collection('reports')
                .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String().split('T')[0])
                .where('date', isLessThanOrEqualTo: endDate.toIso8601String().split('T')[0])
                .where('userId', whereIn: chunk)
                .get();
            reportDocs.addAll(querySnapshot.docs);
          } catch (e) {
            print('Error fetching report chunk: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error fetching reports: $e')),
              );
            }
            return;
          }
        }
      } else {
        try {
          final querySnapshot = await FirebaseFirestore.instance
              .collection('reports')
              .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String().split('T')[0])
              .where('date', isLessThanOrEqualTo: endDate.toIso8601String().split('T')[0])
              .get();
          reportDocs = querySnapshot.docs;
        } catch (e) {
          print('Error fetching admin reports: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error fetching reports: $e')),
            );
          }
          return;
        }
      }

      if (reportDocs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No reports found for the selected period')),
          );
        }
        return;
      }

      Map<String, String> userNames = {};
      List<Map<String, dynamic>> reportDataList = [];

      for (var report in reportDocs) {
        final data = report.data() as Map<String, dynamic>;
        final userId = data['userId'];
        String userName = 'Unknown User';

        if (userNames.containsKey(userId)) {
          userName = userNames[userId]!;
        } else {
          try {
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>?;
              userName = userData?['name'] ?? 'Unknown User';
              userNames[userId] = userName;
            }
          } catch (e) {
            print('Error fetching user data: $e');
          }
        }

        reportDataList.add({
          'userName': userName,
          'date': data['date'] ?? '',
          'report': data['report'] ?? 'No content',
          'timestamp': data['timestamp'] != null
              ? (data['timestamp'] as Timestamp).toDate().toString().split('.')[0]
              : 'N/A',
        });
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  months == 0 ? 'Daily Report' : '${months} Months Report',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
              for (var data in reportDataList)
                pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 16),
                  padding: pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text(
                            'Submitted by: ${data['userName']}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                          ),
                          pw.Spacer(),
                          pw.Text(
                            'Date: ${data['timestamp']}',
                            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 12),
                      pw.Text(
                        'Report Content:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        data['report'],
                        style: pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
                      ),
                    ],
                  ),
                ),
            ];
          },
        ),
      );

      final reportPeriodText = months == 0 ? 'Daily' : months == 1 ? 'Monthly' : '${months}Months';
      final startMonth = startDate.month.toString().padLeft(2, '0');
      final startYear = startDate.year;
      final endMonth = endDate.month.toString().padLeft(2, '0');
      final endYear = endDate.year;

      String fileName;
      if (months == 0) {
        fileName = "Report_Daily_${endMonth}-${endDate.day}-${endYear}.pdf";
      } else {
        fileName = "Report_${reportPeriodText}_${startMonth}${startYear}_to_${endMonth}${endYear}.pdf";
      }

      // Use the new function to save and open the file.
      await _saveAndOpenFile(await pdf.save(), fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to Downloads folder and opened.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Detailed error downloading report: $e');
      if (mounted) {
        String errorMessage = 'Error downloading report: $e';
        if (e.toString().contains('requires an index')) {
          errorMessage = 'Query requires a Firestore index. Please check the Firebase Console for details.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isDownloading = false;
        });
      }
    }
  }

  Widget _buildSubmitReportTab() {
    final user = fa.FirebaseAuth.instance.currentUser!;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Report',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Share your daily progress and updates',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: TextField(
                controller: reportController,
                decoration: InputDecoration(
                  labelText: 'Write your daily report here...',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  errorText: reportController.text.isEmpty ? 'Report is required' : null,
                ),
                maxLines: 6,
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                  'Submit Report',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                onPressed: reportController.text.isEmpty || _isLoading ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Your Previous Reports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('reports')
                  .where('userId', isEqualTo: user.uid)
                  .where('date', isEqualTo: selectedDate.toIso8601String().split('T')[0])
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                        SizedBox(height: 16),
                        Text('Loading your reports...', style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  );
                }
                final reports = snapshot.data!.docs;
                if (reports.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          'No reports submitted for today',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Submit your first report above',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final reportData = reports[index].data() as Map<String, dynamic>;
                    final reportText = reportData['report'] ?? 'No content';
                    final timestamp = reportData['timestamp'] != null
                        ? (reportData['timestamp'] as Timestamp).toDate().toString()
                        : 'N/A';
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.assignment, color: Colors.green[600]),
                                SizedBox(width: 8),
                                Text(
                                  'Your Report',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  timestamp.split('.')[0].split(' ')[1],
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green[200]!),
                              ),
                              child: Text(
                                reportText,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewReportsTab() {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = authProvider.role == 'admin';
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    if (!isAdmin && currentUserId == null) {
      return Center(
        child: Text('No authenticated user. Please sign in again.'),
      );
    }

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.grey[600], size: 20),
              SizedBox(width: 8),
              Text(
                'Filter by Date: ',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                  fontSize: 16,
                ),
              ),
              Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: TextButton.icon(
                  icon: Icon(Icons.calendar_today, size: 18, color: Colors.blue[700]),
                  onPressed: () => _selectDate(context),
                  label: Text(
                    '${selectedDate.toLocal()}'.split(' ')[0],
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isAdmin
              ? StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('reports')
                .where('date', isEqualTo: selectedDate.toIso8601String().split('T')[0])
                .snapshots(),
            builder: (context, snapshot) {
              return _buildReportsList(snapshot);
            },
          )
              : FutureBuilder<List<String>>(
            future: FirebaseFirestore.instance
                .collection('users')
                .where('managerId', isEqualTo: currentUserId)
                .get()
                .then((snapshot) => snapshot.docs.map((doc) => doc.id).toList()),
            builder: (context, futureSnapshot) {
              if (!futureSnapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }

              final employeeIds = futureSnapshot.data!;
              if (employeeIds.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
                      SizedBox(height: 16),
                      Text(
                        'No employees assigned to you',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('reports')
                    .where('date', isEqualTo: selectedDate.toIso8601String().split('T')[0])
                    .where('userId', whereIn: employeeIds)
                    .snapshots(),
                builder: (context, snapshot) {
                  return _buildReportsList(snapshot);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReportsList(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            SizedBox(height: 16),
            Text('Loading reports...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    final reports = snapshot.data!.docs;
    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'No reports for this date',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Select a different date to view reports',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final reportData = reports[index].data() as Map<String, dynamic>;
        final userId = reportData['userId'];
        final reportText = reportData['report'] ?? 'No content';
        final timestamp = reportData['timestamp'] != null
            ? (reportData['timestamp'] as Timestamp).toDate().toString()
            : 'N/A';

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
          builder: (context, userSnapshot) {
            if (!userSnapshot.hasData) {
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircularProgressIndicator(strokeWidth: 2),
                  title: Text('Loading...'),
                ),
              );
            }
            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            final userName = userData?['name']?.toString() ?? 'Unknown';
            final userInitial = userName.isNotEmpty && userName.trim().isNotEmpty
                ? userName.trim()[0].toUpperCase()
                : 'U';
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: Text(
                            userInitial,
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Submitted by: $userName',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Date: ${timestamp.split('.')[0]}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Report Content:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.blue[800],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            reportText,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isManager = authProvider.role == 'manager';
    final isAdmin = authProvider.role == 'admin';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          isAdmin ? 'View Reports' : (isManager ? 'Report Management' : 'Submit Daily Report'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          if (isAdmin || isManager)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: isDownloading
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                )
                    : Icon(Icons.download, color: Colors.blue),
                onPressed: isDownloading ? null : _showDownloadOptions,
                tooltip: 'Download Report',
              ),
            ),
        ],
        bottom: isManager
            ? TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Submit Report'),
            Tab(text: 'View Reports'),
          ],
        )
            : PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      body: isAdmin
          ? _buildViewReportsTab()
          : isManager
          ? TabBarView(
        controller: _tabController,
        children: [
          _buildSubmitReportTab(),
          _buildViewReportsTab(),
        ],
      )
          : _buildSubmitReportTab(),
    );
  }
}
