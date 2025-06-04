import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'auth_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

class AttendanceReportScreen extends StatefulWidget {
  @override
  _AttendanceReportScreenState createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime selectedDate = DateTime.now();
  bool isDownloading = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDateTimePicker(context);
    if (picked == null || picked == selectedDate) return;

    setState(() {
      selectedDate = picked;
    });
  }

  Future<DateTime?> showDateTimePicker(BuildContext context) async {
    return showDatePicker(
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
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
          if (!status.isGranted) {
            var photosStatus = await Permission.photos.request();
            var videosStatus = await Permission.videos.request();
            return photosStatus.isGranted || videosStatus.isGranted;
          }
        }
        return status.isGranted;
      } else if (sdkInt >= 30) {
        var manageStatus = await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
          manageStatus = await Permission.manageExternalStorage.request();
          if (manageStatus.isGranted) return true;
        }
        var storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          storageStatus = await Permission.storage.request();
        }
        return storageStatus.isGranted;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    }
    return true;
  }

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
                        'Download Attendance Report',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Select the period for your attendance report',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 20),
                      _buildReportOption(
                        icon: Icons.calendar_view_day,
                        title: '1 Month Report',
                        subtitle: 'Current month attendance',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(1);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_view_week,
                        title: '2 Months Report',
                        subtitle: 'Last 2 months attendance',
                        color: Colors.green,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(2);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_today,
                        title: '3 Months Report',
                        subtitle: 'Last 3 months attendance',
                        color: Colors.orange,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(3);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.date_range,
                        title: '6 Months Report',
                        subtitle: 'Last 6 months attendance',
                        color: Colors.purple,
                        onTap: () {
                          Navigator.pop(context);
                          _downloadReport(6);
                        },
                      ),
                      _buildReportOption(
                        icon: Icons.calendar_view_month,
                        title: '12 Months Report',
                        subtitle: 'Last 12 months attendance',
                        color: Colors.red,
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

  Future<void> _downloadReport(int months) async {
    setState(() {
      isDownloading = true;
    });

    try {
      bool hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Storage permission is required to download the report. Please grant permission in Settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

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

      DateTime endDate = DateTime(selectedDate.year, selectedDate.month + 1, 0);
      DateTime startDate = DateTime(selectedDate.year, selectedDate.month - months + 1, 1);

      Query<Map<String, dynamic>> attendanceQuery = FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String().split('T')[0])
          .where('date', isLessThanOrEqualTo: endDate.toIso8601String().split('T')[0]);

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

        attendanceQuery = attendanceQuery.where('userId', whereIn: employeeIds);
      }

      final attendanceRecords = await attendanceQuery.get();

      if (attendanceRecords.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No attendance records found for the selected period')),
          );
        }
        return;
      }

      var excelFile = excel.Excel.createExcel();
      String reportPeriod = months == 1 ? 'Monthly' : '${months} Months';
      excel.Sheet sheetObject = excelFile['$reportPeriod Attendance Report'];
      excelFile.delete('Sheet1');

      sheetObject.cell(excel.CellIndex.indexByString("A1")).value = excel.TextCellValue("Employee Name");
      sheetObject.cell(excel.CellIndex.indexByString("B1")).value = excel.TextCellValue("Date");
      sheetObject.cell(excel.CellIndex.indexByString("C1")).value = excel.TextCellValue("Check-In Time");
      sheetObject.cell(excel.CellIndex.indexByString("D1")).value = excel.TextCellValue("Check-Out Time");
      sheetObject.cell(excel.CellIndex.indexByString("E1")).value = excel.TextCellValue("Total Hours");
      sheetObject.cell(excel.CellIndex.indexByString("F1")).value = excel.TextCellValue("Status");

      for (int i = 1; i <= 6; i++) {
        var cell = sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: i - 1, rowIndex: 0));
        cell.cellStyle = excel.CellStyle(
          bold: true,
          backgroundColorHex: excel.ExcelColor.green,
          fontColorHex: excel.ExcelColor.white,
        );
      }

      int rowIndex = 2;
      Map<String, String> userNames = {};

      for (var record in attendanceRecords.docs) {
        final data = record.data() as Map<String, dynamic>;
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

        final date = data['date'] ?? '';
        final checkInTime = data['checkInTime'] != null
            ? data['checkInTime'].toDate().toString().split('.')[0]
            : 'Not Checked In';
        final checkOutTime = data['checkOutTime'] != null
            ? data['checkOutTime'].toDate().toString().split('.')[0]
            : 'Not Checked Out';

        String totalHours = 'N/A';
        String status = 'Incomplete';

        if (data['checkInTime'] != null && data['checkOutTime'] != null) {
          final checkIn = data['checkInTime'].toDate();
          final checkOut = data['checkOutTime'].toDate();
          final duration = checkOut.difference(checkIn);
          final hours = duration.inHours;
          final minutes = duration.inMinutes % 60;
          totalHours = '${hours}h ${minutes}m';
          status = 'Complete';
        } else if (data['checkInTime'] != null) {
          status = 'Checked In Only';
        } else {
          status = 'No Check-In';
        }

        sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex - 1)).value = excel.TextCellValue(userName);
        sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex - 1)).value = excel.TextCellValue(date);
        sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex - 1)).value = excel.TextCellValue(checkInTime);
        sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex - 1)).value = excel.TextCellValue(checkOutTime);
        sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex - 1)).value = excel.TextCellValue(totalHours);
        sheetObject.cell(excel.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex - 1)).value = excel.TextCellValue(status);

        rowIndex++;
      }

      final reportPeriodText = months == 1 ? 'Monthly' : '${months}Months';
      final startMonth = startDate.month.toString().padLeft(2, '0');
      final startYear = startDate.year;
      final endMonth = endDate.month.toString().padLeft(2, '0');
      final endYear = endDate.year;

      String fileName;
      if (months == 1) {
        fileName = "Attendance_Monthly_${endMonth}-${endYear}.xlsx";
      } else {
        fileName = "Attendance_${reportPeriodText}_${startMonth}${startYear}_to_${endMonth}${endYear}.xlsx";
      }

      Directory directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final filePath = "${directory.path}/$fileName";
      final file = File(filePath);
      await file.writeAsBytes(excelFile.encode()!);

      await Share.shareXFiles([XFile(filePath)], text: '$reportPeriod Attendance Report');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$reportPeriod report generated and ready to share!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading report: $e'),
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

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = authProvider.role == 'admin';
    final isManager = authProvider.role == 'manager';
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    if (!isAdmin && !isManager) {
      return Scaffold(
        body: Center(
          child: Text('Access denied: Only admins and managers can view attendance reports'),
        ),
      );
    }

    if (!isAdmin && currentUserId == null) {
      return Scaffold(
        body: Center(
          child: Text('No authenticated user. Please sign in again.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Attendance Reports'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
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
              tooltip: 'Download Monthly Report',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(20),
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.grey[400], size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Filter by Date: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
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
                          icon: Icon(Icons.calendar_today, size: 20, color: Colors.blue[600]),
                          label: Text(
                            '${selectedDate.toLocal()}'.split(' ')[0],
                            style: TextStyle(
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onPressed: () => _selectDate(context),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.file_download, size: 20),
                      label: Text('Download Attendance Report'),
                      onPressed: isDownloading ? null : _showDownloadOptions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: isAdmin
                ? StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where('date', isEqualTo: selectedDate.toIso8601String().split('T')[0])
                  .snapshots(),
              builder: (context, snapshot) {
                return _buildAttendanceList(snapshot);
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
                      .collection('attendance')
                      .where('date', isEqualTo: selectedDate.toIso8601String().split('T')[0])
                      .where('userId', whereIn: employeeIds)
                      .snapshots(),
                  builder: (context, snapshot) {
                    return _buildAttendanceList(snapshot);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) {
      return Center(child: CircularProgressIndicator());
    }

    final attendanceRecords = snapshot.data!.docs;

    if (attendanceRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
            SizedBox(height: 16),
            Text(
              'No attendance records found for this date',
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

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: attendanceRecords.length,
      itemBuilder: (context, index) {
        final record = attendanceRecords[index];
        final data = record.data() as Map<String, dynamic>;
        final userId = data['userId'];
        final checkInTime = data['checkInTime'] != null
            ? data['checkInTime'].toDate().toString().split('.')[0]
            : 'Not Checked In';
        final checkOutTime = data['checkOutTime'] != null
            ? data['checkOutTime'].toDate().toString().split('.')[0]
            : 'Not Checked Out';

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
          builder: (context, userSnapshot) {
            if (!userSnapshot.hasData) {
              return Card(
                child: ListTile(
                  leading: CircularProgressIndicator(),
                ),
              );
            }

            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            final userName = userData?['name'] ?? 'Unknown User';

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: EdgeInsets.only(bottom: 8.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                            style: TextStyle(
                              color: Colors.blue[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            userName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.login, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Check-In: $checkInTime',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.logout, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Check-Out: $checkOutTime',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
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
}