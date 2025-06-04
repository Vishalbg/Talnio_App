import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'email_service.dart'; // Add this import

class TaskScreen extends StatefulWidget {
  final bool isManager;
  const TaskScreen({required this.isManager, Key? key}) : super(key: key);

  @override
  _TaskScreenState createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> with SingleTickerProviderStateMixin {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController descController = TextEditingController();
  final TextEditingController delayReasonController = TextEditingController();
  String? selectedEmployeeUid;
  DateTime? startDate;
  DateTime? endDate;
  DateTime? filterStartDate;
  DateTime? filterEndDate;
  DateTime selectedFilterDate = DateTime.now();
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    if (widget.isManager) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    delayReasonController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (startDate ?? DateTime.now())
          : (endDate ?? startDate?.add(Duration(days: 1)) ?? DateTime.now().add(Duration(days: 1))),
      firstDate: isStartDate ? DateTime.now() : (startDate ?? DateTime.now()),
      lastDate: DateTime(2026),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          startDate = picked;
          if (endDate != null && endDate!.isBefore(startDate!)) {
            endDate = startDate!.add(Duration(days: 7));
          }
        } else {
          if (startDate != null && picked.isBefore(startDate!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('End date cannot be before start date'),
                backgroundColor: Colors.red[400],
              ),
            );
            return;
          }
          endDate = picked;
        }
      });
    }
  }

  Future<void> _selectFilterStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: filterStartDate ?? DateTime.now().subtract(Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        filterStartDate = picked;
        if (filterEndDate != null && filterEndDate!.isBefore(picked)) {
          filterEndDate = picked.add(Duration(days: 7));
        }
      });
    }
  }

  Future<void> _selectFilterEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: filterEndDate ?? DateTime.now(),
      firstDate: filterStartDate ?? DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      if (filterStartDate != null && picked.isBefore(filterStartDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('End date cannot be before start date'),
            backgroundColor: Colors.red[400],
          ),
        );
        return;
      }
      setState(() {
        filterEndDate = picked;
      });
    }
  }

  bool _needsDelayReasonToday(Map<String, dynamic> taskData) {
    final dueDate = DateTime.parse(taskData['dueDate']);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (now.isAfter(dueDate) && taskData['status'] != 'submitted') {
      final delayReasons = taskData['delayReasons'] as List<dynamic>? ?? [];
      for (var reason in delayReasons) {
        if (reason['submittedAt'] != null) {
          final submittedDate = (reason['submittedAt'] as Timestamp).toDate();
          final submittedDay = DateTime(submittedDate.year, submittedDate.month, submittedDate.day);
          if (submittedDay.isAtSameMomentAs(today)) {
            return false;
          }
        }
      }
      return true;
    }
    return false;
  }

  // Modified _assignTask method with email notification
  Future<void> _assignTask() async {
    if (selectedEmployeeUid == null ||
        titleController.text.isEmpty ||
        descController.text.isEmpty ||
        startDate == null ||
        endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill all fields and select dates'),
          backgroundColor: Colors.red[400],
        ),
      );
      return;
    }

    if (endDate!.isBefore(startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('End date must be after start date'),
          backgroundColor: Colors.red[400],
        ),
      );
      return;
    }

    final currentUserId = fa.FirebaseAuth.instance.currentUser!.uid;
    try {
      // Verify that the selected employee is managed by the current user
      final employeeDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(selectedEmployeeUid)
          .get();

      if (!employeeDoc.exists || (employeeDoc.data() as Map<String, dynamic>)['managerId'] != currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected employee is not under your management'),
            backgroundColor: Colors.red[400],
          ),
        );
        return;
      }

      // Get manager details
      final managerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final managerData = managerDoc.data() as Map<String, dynamic>;
      final managerName = managerData['name'] ?? 'Manager';

      // Get employee details
      final employeeData = employeeDoc.data() as Map<String, dynamic>;
      final employeeEmail = employeeData['email'];
      final employeeName = employeeData['name'];

      // Create task
      await FirebaseFirestore.instance.collection('tasks').doc(Uuid().v4()).set({
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'assignedTo': selectedEmployeeUid,
        'assignedBy': currentUserId,
        'status': 'assigned',
        'startDate': startDate!.toIso8601String().split('T')[0],
        'dueDate': endDate!.toIso8601String().split('T')[0],
        'createdAt': FieldValue.serverTimestamp(),
        'delayReasons': [],
        'lastDelayReasonDate': null,
      });

      // Send email notification to employee
      if (employeeEmail != null && employeeName != null) {
        final emailSent = await EmailService.sendTaskAssignmentEmail(
          employeeEmail: employeeEmail,
          employeeName: employeeName,
          taskTitle: titleController.text.trim(),
          taskDescription: descController.text.trim(),
          dueDate: DateFormat('MMM dd, yyyy').format(endDate!),
          managerName: managerName,
        );

        if (emailSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Task assigned and email notification sent successfully')),
                ],
              ),
              backgroundColor: Colors.green[500],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Task assigned but email notification failed')),
                ],
              ),
              backgroundColor: Colors.orange[500],
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Task assigned successfully'),
              ],
            ),
            backgroundColor: Colors.green[500],
          ),
        );
      }

      titleController.clear();
      descController.clear();
      setState(() {
        selectedEmployeeUid = null;
        startDate = null;
        endDate = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error assigning task: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  Future<void> _showSubmissionDialog(String taskId, String taskTitle) async {
    final TextEditingController submissionController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.task_alt, color: Color(0xFF10B981), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Submit Task',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                taskTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              SizedBox(height: 16),
              TextField(
                controller: submissionController,
                decoration: InputDecoration(
                  labelText: 'Submission Comments *',
                  hintText: 'Describe what you accomplished...',
                  errorText: submissionController.text.isEmpty ? 'Comment is required' : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.comment, color: Color(0xFF6B7280)),
                ),
                maxLines: 4,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: submissionController.text.trim().isEmpty
                  ? null
                  : () async {
                try {
                  await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
                    'status': 'submitted',
                    'submissionText': submissionController.text.trim(),
                    'submittedAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Task submitted successfully!'),
                        ],
                      ),
                      backgroundColor: Colors.green[500],
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error submitting task: $e'),
                      backgroundColor: Colors.red[400],
                    ),
                  );
                }
              },
              child: Text('Submit Task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDelayReasonDialog(String taskId, String taskTitle) async {
    delayReasonController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Color(0xFFF59E0B), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Daily Delay Report',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFF59E0B).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This task is overdue. Please provide today\'s delay reason.',
                        style: TextStyle(color: Color(0xFF92400E), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                taskTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              SizedBox(height: 16),
              TextField(
                controller: delayReasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for Today\'s Delay *',
                  hintText: 'Explain why the task is delayed today...',
                  errorText: delayReasonController.text.isEmpty ? 'Reason is required' : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.edit_note, color: Color(0xFF6B7280)),
                ),
                maxLines: 4,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: delayReasonController.text.trim().isEmpty
                  ? null
                  : () async {
                try {
                  final now = DateTime.now();
                  final formattedDate = DateFormat('yyyy-MM-dd').format(now);

                  await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
                    'delayReasons': FieldValue.arrayUnion([
                      {
                        'reason': delayReasonController.text.trim(),
                        'submittedAt': Timestamp.fromDate(now),
                        'date': formattedDate,
                      }
                    ]),
                    'lastDelayReasonDate': formattedDate,
                  });

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Delay reason submitted'),
                        ],
                      ),
                      backgroundColor: Color(0xFFF59E0B),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error submitting delay reason: $e'),
                      backgroundColor: Colors.red[400],
                    ),
                  );
                }
              },
              child: Text('Submit Reason'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? selectedDate,
    required bool isStartDate,
    required String? errorText,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () => _selectDate(context, isStartDate),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: errorText != null ? Colors.red : Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[50],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: errorText != null ? Colors.red : Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: selectedDate == null ? Color(0xFF9CA3AF) : Color(0xFF374151),
                  ),
                  SizedBox(width: 8),
                  Text(
                    selectedDate == null
                        ? 'Select Date'
                        : DateFormat('MMM dd, yyyy').format(selectedDate),
                    style: TextStyle(
                      color: selectedDate == null ? Color(0xFF9CA3AF) : Color(0xFF374151),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                SizedBox(height: 4),
                Text(
                  errorText,
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignTaskTab() {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    return SingleChildScrollView(
      padding: EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.assignment_add, color: Colors.white, size: 32),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign New Task',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Create and assign tasks to team members',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 32),
          TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: 'Task Title *',
              hintText: 'Enter a descriptive task title',
              errorText: titleController.text.isEmpty ? 'Title is required' : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.title, color: Color(0xFF6B7280)),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 20),
          TextField(
            controller: descController,
            decoration: InputDecoration(
              labelText: 'Task Description *',
              hintText: 'Provide detailed task requirements...',
              errorText: descController.text.isEmpty ? 'Description is required' : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.description, color: Color(0xFF6B7280)),
            ),
            maxLines: 4,
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              _buildDateSelector(
                label: 'Start Date *',
                selectedDate: startDate,
                isStartDate: true,
                errorText: startDate == null ? 'Required' : null,
              ),
              SizedBox(width: 16),
              _buildDateSelector(
                label: 'Due Date *',
                selectedDate: endDate,
                isStartDate: false,
                errorText: endDate == null ? 'Required' : null,
              ),
            ],
          ),
          SizedBox(height: 20),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('managerId', isEqualTo: currentUserId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final employees = snapshot.data!.docs;
              if (employees.isEmpty) {
                return Text(
                  'No employees assigned to you',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                );
              }
              return DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Assign to Employee *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: selectedEmployeeUid == null ? 'Please select an employee' : null,
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.person, color: Color(0xFF6B7280)),
                ),
                value: selectedEmployeeUid,
                isExpanded: true,
                items: employees.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(0xFF2563EB),
                          child: Text(
                            data['name'][0].toUpperCase(),
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(data['name']),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedEmployeeUid = value);
                },
              );
            },
          ),
          SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (titleController.text.isEmpty ||
                  descController.text.isEmpty ||
                  selectedEmployeeUid == null ||
                  startDate == null ||
                  endDate == null)
                  ? null
                  : _assignTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_add, size: 24),
                  SizedBox(width: 8),
                  Text('Assign Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> data, String docId, {String? employeeName}) {
    final String title = data['title']?.toString() ?? 'Untitled Task';
    final String description = data['description']?.toString() ?? '';
    final String startDateStr = data['startDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
    final String dueDateStr = data['dueDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
    final String status = data['status']?.toString() ?? 'unknown';
    final String? submissionText = data['submissionText']?.toString();
    final List<dynamic> delayReasons = data['delayReasons'] as List<dynamic>? ?? [];

    DateTime startDate;
    DateTime dueDate;
    try {
      startDate = DateTime.parse(startDateStr);
      dueDate = DateTime.parse(dueDateStr);
    } catch (e) {
      startDate = DateTime.now();
      dueDate = DateTime.now();
    }

    final isOverdue = DateTime.now().isAfter(dueDate) && status != 'submitted';
    final needsDelayReason = _needsDelayReasonToday(data);

    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;

    switch (status) {
      case 'submitted':
        statusColor = Color(0xFF059669);
        statusBgColor = Color(0xFFD1FAE5);
        statusIcon = Icons.check_circle;
        break;
      case 'assigned':
        if (isOverdue) {
          statusColor = Color(0xFFDC2626);
          statusBgColor = Color(0xFFFEE2E2);
          statusIcon = Icons.warning;
        } else {
          statusColor = Color(0xFF2563EB);
          statusBgColor = Color(0xFFDEEBFF);
          statusIcon = Icons.assignment;
        }
        break;
      default:
        statusColor = Color(0xFF6B7280);
        statusBgColor = Color(0xFFF3F4F6);
        statusIcon = Icons.help_outline;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: statusColor,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFF111827),
                          ),
                        ),
                        if (employeeName != null) ...[
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person, size: 16, color: Color(0xFF6B7280)),
                              SizedBox(width: 4),
                              Text(
                                'Assigned to: $employeeName',
                                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        SizedBox(width: 4),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty && !widget.isManager) ...[
                SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                ),
              ],
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.play_arrow, size: 16, color: Color(0xFF059669)),
                              SizedBox(width: 4),
                              Text('Start Date', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            DateFormat('MMM dd, yyyy').format(startDate),
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isOverdue ? Color(0xFFFEE2E2) : Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.flag,
                                size: 16,
                                color: isOverdue ? Color(0xFFDC2626) : Color(0xFFF59E0B),
                              ),
                              SizedBox(width: 4),
                              Text('Due Date', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            DateFormat('MMM dd, yyyy').format(dueDate),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isOverdue ? Color(0xFFDC2626) : Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (submissionText != null) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(0xFF059669).withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 16, color: Color(0xFF059669)),
                          SizedBox(width: 4),
                          Text('Submission', style: TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        submissionText,
                        style: TextStyle(color: Color(0xFF065F46), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
              if (isOverdue && delayReasons.isNotEmpty) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(0xFFF59E0B).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber, size: 16, color: Color(0xFFF59E0B)),
                          SizedBox(width: 4),
                          Text('Latest Delay Reason', style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        delayReasons.last['reason']?.toString() ?? 'No reason provided',
                        style: TextStyle(color: Color(0xFF92400E), fontSize: 14),
                      ),
                      if (delayReasons.last['submittedAt'] != null) ...[
                        SizedBox(height: 4),
                        Text(
                          'Submitted: ${DateFormat('MMM dd, yyyy').format((delayReasons.last['submittedAt'] as Timestamp).toDate())}',
                          style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!widget.isManager) ...[
                SizedBox(height: 16),
                if (needsDelayReason) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showDelayReasonDialog(docId, title),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning_amber, size: 20),
                          SizedBox(width: 8),
                          Text('Submit Today\'s Delay Reason', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ] else if (status == 'assigned') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showSubmissionDialog(docId, title),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.task_alt, size: 20),
                          SizedBox(width: 8),
                          Text('Mark as Complete', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.filter_list, color: Colors.grey[600], size: 24),
              SizedBox(width: 8),
              Text(
                'Filter by Due Date Range:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextButton.icon(
                    icon: Icon(Icons.calendar_today, size: 20, color: Colors.blue[600]),
                    label: Text(
                      filterStartDate != null
                          ? DateFormat('MMM dd, yyyy').format(filterStartDate!)
                          : 'Start Date',
                      style: TextStyle(
                        color: filterStartDate != null ? Colors.blue[600] : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: () => _selectFilterStartDate(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextButton.icon(
                    icon: Icon(Icons.calendar_today, size: 20, color: Colors.blue[600]),
                    label: Text(
                      filterEndDate != null
                          ? DateFormat('MMM dd, yyyy').format(filterEndDate!)
                          : 'End Date',
                      style: TextStyle(
                        color: filterEndDate != null ? Colors.blue[600] : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: () => _selectFilterEndDate(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (filterStartDate != null || filterEndDate != null) ...[
            SizedBox(height: 8),
            TextButton.icon(
              icon: Icon(Icons.clear, size: 18, color: Colors.red[600]),
              label: Text(
                'Clear Filter',
                style: TextStyle(color: Colors.red[600]),
              ),
              onPressed: () {
                setState(() {
                  filterStartDate = null;
                  filterEndDate = null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _getFilteredTasksStream({required bool isAdmin, String? managerId}) {
    Query query = FirebaseFirestore.instance.collection('tasks');

    if (!isAdmin && managerId != null) {
      query = query.where('assignedBy', isEqualTo: managerId);
    }

    if (filterStartDate != null) {
      query = query.where('dueDate', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(filterStartDate!));
    }
    if (filterEndDate != null) {
      query = query.where('dueDate', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(filterEndDate!));
    }

    return query.orderBy('dueDate', descending: false).snapshots();
  }

  Stream<QuerySnapshot> _getEmployeeFilteredTasksStream(String userId) {
    Query query = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedTo', isEqualTo: userId);

    if (filterStartDate != null) {
      query = query.where('dueDate', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(filterStartDate!));
    }
    if (filterEndDate != null) {
      query = query.where('dueDate', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(filterEndDate!));
    }

    return query.orderBy('dueDate', descending: false).snapshots();
  }

  Widget _buildViewTasksTab() {
    final user = fa.FirebaseAuth.instance.currentUser!;
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = authProvider.role == 'admin';

    return Column(
      children: [
        _buildDateRangeFilter(),
        Expanded(
          child: isAdmin
              ? StreamBuilder<QuerySnapshot>(
            stream: _getFilteredTasksStream(isAdmin: true),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              return _buildTaskList(snapshot);
            },
          )
              : StreamBuilder<QuerySnapshot>(
            stream: _getFilteredTasksStream(isAdmin: false, managerId: user.uid),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
              }
              if (snapshot.hasError) {
                print('Query error: ${snapshot.error}');
                return Center(
                  child: Text(
                    'Error loading tasks: ${snapshot.error}',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.task_alt, size: 64, color: Color(0xFF9CA3AF)),
                      SizedBox(height: 16),
                      Text(
                        'No tasks found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        filterStartDate != null || filterEndDate != null
                            ? 'Try adjusting the date filter or assign new tasks'
                            : 'Try assigning new tasks',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _buildTaskList(snapshot);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeTasksView() {
    final user = fa.FirebaseAuth.instance.currentUser!;
    return Column(
      children: [
        _buildDateRangeFilter(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _getEmployeeFilteredTasksStream(user.uid),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text(
                        'Error loading tasks: ${snapshot.error}',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 18),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Color(0xFFF9FAFB),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.task_alt, size: 64, color: Color(0xFF9CA3AF)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No tasks found',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      Text(
                        filterStartDate != null || filterEndDate != null
                            ? 'Try adjusting the date filter'
                            : 'No tasks assigned to you',
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              final validDocs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['title'] != null &&
                    data['startDate'] != null &&
                    data['dueDate'] != null &&
                    data['status'] != null;
              }).toList();

              if (validDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Color(0xFFF9FAFB),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.task_alt, size: 64, color: Color(0xFF9CA3AF)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No valid tasks found',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Ensure tasks have all required fields',
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              final overdueTasks = <QueryDocumentSnapshot>[];
              final regularTasks = <QueryDocumentSnapshot>[];

              for (var doc in validDocs) {
                final data = doc.data() as Map<String, dynamic>;
                if (_needsDelayReasonToday(data)) {
                  overdueTasks.add(doc);
                } else {
                  regularTasks.add(doc);
                }
              }

              return ListView(
                padding: EdgeInsets.all(24.0),
                children: [
                  if (overdueTasks.isNotEmpty) ...[
                    Container(
                      padding: EdgeInsets.all(16),
                      margin: EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Color(0xFFF59E0B).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.priority_high, color: Color(0xFFF59E0B), size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Action Required',
                                  style: TextStyle(
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'You have ${overdueTasks.length} overdue task${overdueTasks.length > 1 ? 's' : ''} requiring daily delay reasons.',
                                  style: TextStyle(color: Color(0xFF92400E), fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  ...overdueTasks.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildTaskCard(data, doc.id);
                  }).toList(),
                  ...regularTasks.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildTaskCard(data, doc.id);
                  }).toList(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTaskList(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
    }

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Error loading tasks: ${snapshot.error}',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 18),
            ),
          ],
        ),
      );
    }

    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFF9FAFB),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt, size: 64, color: Color(0xFF9CA3AF)),
            ),
            SizedBox(height: 16),
            Text(
              'No tasks for selected date',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Try selecting a different date or check Firestore data',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    final validDocs = snapshot.data!.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['title'] != null &&
          data['startDate'] != null &&
          data['dueDate'] != null &&
          data['status'] != null &&
          data['assignedTo'] != null;
    }).toList();

    if (validDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFF9FAFB),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt, size: 64, color: Color(0xFF9CA3AF)),
            ),
            SizedBox(height: 16),
            Text(
              'No valid tasks found',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Ensure tasks have all required fields',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(24.0),
      itemCount: validDocs.length,
      itemBuilder: (context, index) {
        final doc = validDocs[index];
        final data = doc.data() as Map<String, dynamic>;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(data['assignedTo']).get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return Card(
                child: ListTile(
                  leading: CircularProgressIndicator(),
                  title: Text('Loading...'),
                ),
              );
            }
            if (userSnapshot.hasError) {
              return Card(
                child: ListTile(
                  leading: Icon(Icons.error, color: Colors.red),
                  title: Text('Error loading user'),
                ),
              );
            }
            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            final employeeName = userData?['name']?.toString() ?? 'Unknown Employee';

            return _buildTaskCard(data, doc.id, employeeName: employeeName);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = authProvider.role == 'admin';
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    if (!isAdmin && !widget.isManager && authProvider.role != 'employee') {
      return Scaffold(
        body: Center(
          child: Text('Access denied: Only admins, managers, and employees can access tasks'),
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
      backgroundColor: Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          widget.isManager ? 'Task Management' : 'My Tasks',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: widget.isManager
            ? TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Assign Task'),
            Tab(text: 'View Tasks'),
          ],
        )
            : null,
      ),
      body: widget.isManager
          ? TabBarView(
        controller: _tabController,
        children: [
          _buildAssignTaskTab(),
          _buildViewTasksTab(),
        ],
      )
          : _buildEmployeeTasksView(),
    );
  }
}
