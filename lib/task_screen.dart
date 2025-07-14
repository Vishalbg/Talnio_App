import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'email_service.dart';
import 'task_card_widget.dart';
import 'edit_task_dialog.dart';

class TaskScreen extends StatefulWidget {
  final bool isManager;
  const TaskScreen({required this.isManager, Key? key}) : super(key: key);

  @override
  _TaskScreenState createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> with SingleTickerProviderStateMixin {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _filterEmployeeSearchController = TextEditingController();

  // Changed from single selectedEmployeeUid to multiple selected employees
  List<String> selectedEmployeeUids = [];
  String? selectedFilterEmployeeUid;

  DateTime? startDate;
  DateTime? endDate;
  DateTime selectedFilterDate = DateTime.now();
  TabController? _tabController;
  String selectedStatusFilter = 'all';
  bool showTodayTasksOnly = false;
  bool _isAddingTask = false;
  bool _isEmployeeSelectorExpanded = false;
  bool _isFilterEmployeeSelectorExpanded = false;
  List<DocumentSnapshot> _allEmployees = [];
  List<DocumentSnapshot> _filteredEmployees = [];
  List<DocumentSnapshot> _allFilterEmployees = [];
  List<DocumentSnapshot> _filteredFilterEmployees = [];
  bool _employeesLoaded = false;
  bool _filterEmployeesLoaded = false;

  // New variables for search functionality
  bool _isSearchEnabled = false;
  bool _isFilterSearchEnabled = false;

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
    _searchController.dispose();
    _filterEmployeeSearchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _filterEmployees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = _allEmployees;
      } else {
        _filteredEmployees = _allEmployees.where((employee) {
          final employeeData = employee.data() as Map<String, dynamic>;
          final employeeName = employeeData['name']?.toString().toLowerCase() ?? '';
          final employeeEmail = employeeData['email']?.toString().toLowerCase() ?? '';
          return employeeName.contains(query.toLowerCase()) ||
              employeeEmail.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _filterFilterEmployees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredFilterEmployees = _allFilterEmployees;
      } else {
        _filteredFilterEmployees = _allFilterEmployees.where((employee) {
          final employeeData = employee.data() as Map<String, dynamic>;
          final employeeName = employeeData['name']?.toString().toLowerCase() ?? '';
          final employeeEmail = employeeData['email']?.toString().toLowerCase() ?? '';
          return employeeName.contains(query.toLowerCase()) ||
              employeeEmail.contains(query.toLowerCase());
        }).toList();
      }
    });
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

  // Updated to support multiple employees
  Future<void> _assignTask() async {
    if (titleController.text.isEmpty ||
        descController.text.isEmpty ||
        startDate == null ||
        endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill all required fields and select dates'),
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

    setState(() {
      _isAddingTask = true;
    });

    final currentUserId = fa.FirebaseAuth.instance.currentUser!.uid;
    try {
      final managerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final managerData = managerDoc.data() as Map<String, dynamic>;
      final managerName = managerData['name'] ?? 'Manager';

      List<Map<String, dynamic>> assignedEmployees = [];
      List<String> employeeEmails = [];
      List<String> employeeNames = [];

      // Create assignedEmployees array
      for (String employeeUid in selectedEmployeeUids) {
        final employeeDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(employeeUid)
            .get();

        if (!employeeDoc.exists || (employeeDoc.data() as Map<String, dynamic>)['managerId'] != currentUserId) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('One or more selected employees are not under your management'),
              backgroundColor: Colors.red[400],
            ),
          );
          setState(() {
            _isAddingTask = false;
          });
          return;
        }

        final employeeData = employeeDoc.data() as Map<String, dynamic>;
        final employeeName = employeeData['name'] ?? 'Unknown';
        final employeeEmail = employeeData['email'] ?? '';

        assignedEmployees.add({
          'employeeId': employeeUid,
          'employeeName': employeeName,
          'employeeEmail': employeeEmail,
          'status': 'assigned',
          'actualStartDate': null,
          'actualEndDate': null,
          'submissionText': null,
        });

        employeeEmails.add(employeeEmail);
        employeeNames.add(employeeName);
      }

      // Calculate overall status
      String overallStatus = selectedEmployeeUids.isEmpty ? 'unassigned' : 'assigned';

      await FirebaseFirestore.instance.collection('tasks').doc(Uuid().v4()).set({
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'assignedEmployees': assignedEmployees,
        'assignedBy': currentUserId,
        'status': overallStatus, // Keep for backward compatibility
        'overallStatus': overallStatus,
        'startDate': startDate!.toIso8601String().split('T')[0],
        'dueDate': endDate!.toIso8601String().split('T')[0],
        'createdAt': FieldValue.serverTimestamp(),
        'delayReasons': [],
        'lastDelayReasonDate': null,
      });

      // Send emails to all assigned employees
      if (assignedEmployees.isNotEmpty) {
        for (int i = 0; i < employeeEmails.length; i++) {
          await EmailService.sendTaskAssignmentEmail(
            employeeEmail: employeeEmails[i],
            employeeName: employeeNames[i],
            taskTitle: titleController.text.trim(),
            taskDescription: descController.text.trim(),
            dueDate: DateFormat('MMM dd, yyyy').format(endDate!),
            managerName: managerName,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Task assigned to ${assignedEmployees.length} employee(s) successfully')),
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
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Unassigned task created successfully'),
              ],
            ),
            backgroundColor: Colors.green[500],
          ),
        );
      }

      titleController.clear();
      descController.clear();
      setState(() {
        selectedEmployeeUids.clear();
        startDate = null;
        endDate = null;
        _isEmployeeSelectorExpanded = false;
        _searchController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating task: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    } finally {
      setState(() {
        _isAddingTask = false;
      });
    }
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? selectedDate,
    required bool isStartDate,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () => _selectDate(context, isStartDate),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Color(0xFFD1D5DB)),
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
                  color: Color(0xFF6B7280),
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
            ],
          ),
        ),
      ),
    );
  }

  // Updated employee selector for multiple selection
  Widget _buildEmployeeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Assign to Employees ${selectedEmployeeUids.isNotEmpty ? "(${selectedEmployeeUids.length} selected)" : "(Optional)"}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isEmployeeSelectorExpanded = !_isEmployeeSelectorExpanded;
                  if (!_isEmployeeSelectorExpanded) {
                    _isSearchEnabled = false;
                    _searchController.clear();
                    _filteredEmployees = _allEmployees;
                  }
                });
              },
              icon: Icon(
                _isEmployeeSelectorExpanded ? Icons.expand_less : Icons.expand_more,
                color: Color(0xFF2563EB),
              ),
              label: Text(
                _isEmployeeSelectorExpanded ? 'Collapse' : 'Expand',
                style: TextStyle(color: Color(0xFF2563EB)),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),

        if (_isEmployeeSelectorExpanded) ...[
          // Search bar with icon
          Row(
            children: [
              if (!_isSearchEnabled) ...[
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people, color: Color(0xFF6B7280), size: 20),
                        SizedBox(width: 12),
                        Text(
                          'Select employees to assign',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isSearchEnabled = true;
                    });
                  },
                  icon: Icon(Icons.search, color: Color(0xFF2563EB)),
                  tooltip: 'Search employees',
                  style: IconButton.styleFrom(
                    backgroundColor: Color(0xFFE0F2FE),
                    padding: EdgeInsets.all(12),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search employees...',
                      prefixIcon: Icon(Icons.search, color: Color(0xFF6B7280)),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _isSearchEnabled = false;
                            _searchController.clear();
                            _filteredEmployees = _allEmployees;
                          });
                        },
                        icon: Icon(Icons.close, color: Color(0xFF6B7280)),
                        tooltip: 'Close search',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: _filterEmployees,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 12),
        ],

        // Show selected employees when collapsed
        if (!_isEmployeeSelectorExpanded && selectedEmployeeUids.isNotEmpty && _employeesLoaded) ...[
          _buildSelectedEmployeeChips(),
          SizedBox(height: 8),
        ],

        if (!_isEmployeeSelectorExpanded && selectedEmployeeUids.isEmpty) ...[
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[400],
                  child: Icon(Icons.person_off, color: Colors.white, size: 16),
                ),
                SizedBox(width: 12),
                Text(
                  'Unassigned Task',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
        ],

        if (_isEmployeeSelectorExpanded) ...[
          Container(
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Select All / Deselect All button
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: ListTile(
                    leading: Icon(
                      selectedEmployeeUids.length == _filteredEmployees.length && _filteredEmployees.isNotEmpty
                          ? Icons.check_box
                          : (selectedEmployeeUids.isEmpty ? Icons.check_box_outline_blank : Icons.indeterminate_check_box),
                      color: Color(0xFF2563EB),
                    ),
                    title: Text(
                      selectedEmployeeUids.length == _filteredEmployees.length && _filteredEmployees.isNotEmpty
                          ? 'Deselect All'
                          : 'Select All',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    subtitle: Text('${selectedEmployeeUids.length} of ${_filteredEmployees.length} selected'),
                    onTap: () {
                      setState(() {
                        if (selectedEmployeeUids.length == _filteredEmployees.length && _filteredEmployees.isNotEmpty) {
                          selectedEmployeeUids.clear();
                        } else {
                          selectedEmployeeUids.clear();
                          for (var employee in _filteredEmployees) {
                            selectedEmployeeUids.add(employee.id);
                          }
                        }
                      });
                    },
                  ),
                ),
                Expanded(
                  child: _filteredEmployees.isEmpty
                      ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        _searchController.text.isNotEmpty
                            ? 'No employees found'
                            : 'No employees available',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                      : ListView.builder(
                    itemCount: _filteredEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = _filteredEmployees[index];
                      final employeeData = employee.data() as Map<String, dynamic>;
                      final employeeId = employee.id;
                      final employeeName = employeeData['name'] ?? 'Unknown';
                      final employeeEmail = employeeData['email'] ?? '';
                      final isSelected = selectedEmployeeUids.contains(employeeId);

                      return Container(
                        decoration: BoxDecoration(
                          color: isSelected ? Color(0xFFE0F2FE) : null,
                          border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Color(0xFF2563EB),
                            child: Text(
                              employeeName.isNotEmpty ? employeeName[0].toUpperCase() : 'U',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            employeeName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            employeeEmail,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? Color(0xFF2563EB) : Colors.grey[400],
                          ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selectedEmployeeUids.remove(employeeId);
                              } else {
                                selectedEmployeeUids.add(employeeId);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Updated to show multiple selected employees
  Widget _buildSelectedEmployeeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: selectedEmployeeUids.map((employeeId) {
        try {
          final selectedEmployee = _allEmployees.firstWhere((emp) => emp.id == employeeId);
          final employeeData = selectedEmployee.data() as Map<String, dynamic>;
          final employeeName = employeeData['name'] ?? 'Unknown';

          return Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Color(0xFF3B82F6).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Color(0xFF2563EB),
                  child: Text(
                    employeeName.isNotEmpty ? employeeName[0].toUpperCase() : 'U',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    employeeName,
                    style: TextStyle(
                      color: Color(0xFF1E40AF),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedEmployeeUids.remove(employeeId);
                    });
                  },
                  child: Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          );
        } catch (e) {
          return Container();
        }
      }).toList(),
    );
  }

  // Filter employee selector remains the same
  Widget _buildFilterEmployeeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isFilterEmployeeSelectorExpanded = !_isFilterEmployeeSelectorExpanded;
              if (!_isFilterEmployeeSelectorExpanded) {
                _isFilterSearchEnabled = false;
                _filterEmployeeSearchController.clear();
                _filteredFilterEmployees = _allFilterEmployees;
              }
            });
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child: Row(
              children: [
                Icon(Icons.person_search, size: 20, color: Color(0xFF6B7280)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selectedFilterEmployeeUid == null
                        ? 'All Employees'
                        : _getSelectedEmployeeName(),
                    style: TextStyle(
                      fontSize: 14,
                      color: selectedFilterEmployeeUid == null
                          ? Colors.grey[600]
                          : Color(0xFF1E40AF),
                      fontWeight: selectedFilterEmployeeUid == null
                          ? FontWeight.normal
                          : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selectedFilterEmployeeUid != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedFilterEmployeeUid = null;
                        _filterEmployeeSearchController.clear();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
                    ),
                  ),
                SizedBox(width: 4),
                Icon(
                  _isFilterEmployeeSelectorExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Color(0xFF6B7280),
                  size: 20,
                ),
              ],
            ),
          ),
        ),

        if (_isFilterEmployeeSelectorExpanded) ...[
          SizedBox(height: 8),
          Row(
            children: [
              if (!_isFilterSearchEnabled) ...[
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people, color: Color(0xFF6B7280), size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Filter by employee',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isFilterSearchEnabled = true;
                    });
                  },
                  icon: Icon(Icons.search, color: Color(0xFF2563EB), size: 18),
                  tooltip: 'Search employees',
                  style: IconButton.styleFrom(
                    backgroundColor: Color(0xFFE0F2FE),
                    padding: EdgeInsets.all(8),
                    minimumSize: Size(32, 32),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: Container(
                    height: 40,
                    child: TextField(
                      controller: _filterEmployeeSearchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search employees...',
                        prefixIcon: Icon(Icons.search, color: Color(0xFF6B7280), size: 18),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _isFilterSearchEnabled = false;
                              _filterEmployeeSearchController.clear();
                              _filteredFilterEmployees = _allFilterEmployees;
                            });
                          },
                          icon: Icon(Icons.close, color: Color(0xFF6B7280), size: 16),
                          tooltip: 'Close search',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                      style: TextStyle(fontSize: 14),
                      onChanged: _filterFilterEmployees,
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 8),

          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: selectedFilterEmployeeUid == null ? Color(0xFFE0F2FE) : null,
                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.grey[400],
                      child: Icon(Icons.people, color: Colors.white, size: 14),
                    ),
                    title: Text(
                      'All Employees',
                      style: TextStyle(
                        fontWeight: selectedFilterEmployeeUid == null ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    trailing: selectedFilterEmployeeUid == null
                        ? Icon(Icons.check_circle, color: Color(0xFF2563EB), size: 18)
                        : null,
                    onTap: () {
                      setState(() {
                        selectedFilterEmployeeUid = null;
                        _isFilterEmployeeSelectorExpanded = false;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: _filteredFilterEmployees.isEmpty
                      ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        _filterEmployeeSearchController.text.isNotEmpty
                            ? 'No employees found'
                            : 'No employees available',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                  )
                      : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _filteredFilterEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = _filteredFilterEmployees[index];
                      final employeeData = employee.data() as Map<String, dynamic>;
                      final employeeId = employee.id;
                      final employeeName = employeeData['name'] ?? 'Unknown';
                      final employeeEmail = employeeData['email'] ?? '';

                      return Container(
                        decoration: BoxDecoration(
                          color: selectedFilterEmployeeUid == employeeId ? Color(0xFFE0F2FE) : null,
                          border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Color(0xFF2563EB),
                            child: Text(
                              employeeName.isNotEmpty ? employeeName[0].toUpperCase() : 'U',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                            ),
                          ),
                          title: Text(
                            employeeName,
                            style: TextStyle(
                              fontWeight: selectedFilterEmployeeUid == employeeId ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            employeeEmail,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: selectedFilterEmployeeUid == employeeId
                              ? Icon(Icons.check_circle, color: Color(0xFF2563EB), size: 18)
                              : null,
                          onTap: () {
                            setState(() {
                              selectedFilterEmployeeUid = employeeId;
                              _isFilterEmployeeSelectorExpanded = false;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _getSelectedEmployeeName() {
    try {
      final selectedEmployee = _allFilterEmployees.firstWhere((emp) => emp.id == selectedFilterEmployeeUid);
      final employeeData = selectedEmployee.data() as Map<String, dynamic>;
      return employeeData['name'] ?? 'Unknown Employee';
    } catch (e) {
      return 'Unknown Employee';
    }
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
                        'Create New Task',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Create tasks and assign to multiple team members or leave unassigned',
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.title, color: Color(0xFF6B7280)),
            ),
          ),
          SizedBox(height: 20),
          TextField(
            controller: descController,
            decoration: InputDecoration(
              labelText: 'Task Description *',
              hintText: 'Provide detailed task requirements...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: Icon(Icons.description, color: Color(0xFF6B7280)),
            ),
            maxLines: 4,
          ),
          SizedBox(height: 20),
          Row(
            children: [
              _buildDateSelector(
                label: 'Start Date *',
                selectedDate: startDate,
                isStartDate: true,
              ),
              SizedBox(width: 16),
              _buildDateSelector(
                label: 'Due Date *',
                selectedDate: endDate,
                isStartDate: false,
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

              _allEmployees = snapshot.data!.docs;
              if (_filteredEmployees.isEmpty && _searchController.text.isEmpty) {
                _filteredEmployees = _allEmployees;
              }

              if (!_employeesLoaded) {
                _employeesLoaded = true;
              }

              return _buildEmployeeSelector();
            },
          ),
          SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (titleController.text.isEmpty ||
                  descController.text.isEmpty ||
                  startDate == null ||
                  endDate == null ||
                  _isAddingTask)
                  ? null
                  : _assignTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              child: _isAddingTask
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Creating Task...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_task, size: 24),
                  SizedBox(width: 8),
                  Text('Create Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskFilters() {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    return Container(
      color: Colors.white,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.filter_list, color: Color(0xFF2563EB)),
        title: Row(
          children: [
            Text(
              'Filters',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            if (selectedStatusFilter != 'all' || showTodayTasksOnly || selectedFilterEmployeeUid != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getActiveFilterCount().toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  showTodayTasksOnly = !showTodayTasksOnly;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: showTodayTasksOnly ? Color(0xFF2563EB) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.today,
                      size: 16,
                      color: showTodayTasksOnly ? Colors.white : Colors.grey[600],
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Today',
                      style: TextStyle(
                        color: showTodayTasksOnly ? Colors.white : Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.expand_more),
          ],
        ),
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('managerId', isEqualTo: currentUserId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Container(
                          height: 40,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      _allFilterEmployees = snapshot.data!.docs;
                      if (_filteredFilterEmployees.isEmpty && _filterEmployeeSearchController.text.isEmpty) {
                        _filteredFilterEmployees = _allFilterEmployees;
                      }

                      if (!_filterEmployeesLoaded) {
                        _filterEmployeesLoaded = true;
                      }

                      return _buildFilterEmployeeSelector();
                    },
                  ),

                  SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 40,
                          child: DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: 14, color: Colors.black),
                            dropdownColor: Colors.white,
                            value: selectedStatusFilter,
                            items: [
                              DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All Statuses', style: TextStyle(color: Colors.black))
                              ),
                              DropdownMenuItem(
                                  value: 'unassigned',
                                  child: Text('Unassigned', style: TextStyle(color: Colors.black))
                              ),
                              DropdownMenuItem(
                                  value: 'assigned',
                                  child: Text('Assigned', style: TextStyle(color: Colors.black))
                              ),
                              DropdownMenuItem(
                                  value: 'in_progress',
                                  child: Text('In Progress', style: TextStyle(color: Colors.black))
                              ),
                              DropdownMenuItem(
                                  value: 'hold',
                                  child: Text('On Hold', style: TextStyle(color: Colors.black))
                              ),
                              DropdownMenuItem(
                                  value: 'completed',
                                  child: Text('Completed', style: TextStyle(color: Colors.black))
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedStatusFilter = value ?? 'all';
                              });
                            },
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      if (selectedStatusFilter != 'all' || showTodayTasksOnly || selectedFilterEmployeeUid != null)
                        Expanded(
                          flex: 1,
                          child: Container(
                            height: 40,
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.clear, size: 16, color: Colors.red[600]),
                              label: Text(
                                'Clear',
                                style: TextStyle(color: Colors.red[600], fontSize: 12),
                              ),
                              onPressed: () {
                                setState(() {
                                  selectedStatusFilter = 'all';
                                  showTodayTasksOnly = false;
                                  selectedFilterEmployeeUid = null;
                                  _filterEmployeeSearchController.clear();
                                  _isFilterEmployeeSelectorExpanded = false;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.red[300]!),
                                padding: EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (selectedStatusFilter != 'all') count++;
    if (showTodayTasksOnly) count++;
    if (selectedFilterEmployeeUid != null) count++;
    return count;
  }

  Stream<QuerySnapshot> _getFilteredTasksStream({required bool isAdmin, String? managerId}) {
    Query query = FirebaseFirestore.instance.collection('tasks');

    if (!isAdmin && managerId != null) {
      query = query.where('assignedBy', isEqualTo: managerId);
    }

    if (showTodayTasksOnly) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      query = query.where('dueDate', isEqualTo: today);
    }

    return query.orderBy('dueDate', descending: false).snapshots();
  }

  // Updated to work with new assignedEmployees structure
  Stream<QuerySnapshot> _getEmployeeFilteredTasksStream(String userId) {
    // Use a simpler approach - get all tasks and filter in the app
    // This is more reliable than complex array_contains queries
    Query query = FirebaseFirestore.instance
        .collection('tasks')
        .orderBy('dueDate', descending: false);

    if (showTodayTasksOnly) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      query = query.where('dueDate', isEqualTo: today);
    }

    return query.snapshots();
  }

  Widget _buildViewTasksTab() {
    final user = fa.FirebaseAuth.instance.currentUser!;
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = authProvider.role == 'admin';

    return Column(
      children: [
        _buildTaskFilters(),
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
                        showTodayTasksOnly
                            ? 'No tasks due today'
                            : 'Try adjusting the filters or create new tasks',
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
        Container(
          color: Colors.white,
          child: ExpansionTile(
            initiallyExpanded: false,
            leading: Icon(Icons.filter_list, color: Color(0xFF2563EB)),
            title: Row(
              children: [
                Text(
                  'Filters',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 8),
                if (selectedStatusFilter != 'all' || showTodayTasksOnly)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getEmployeeActiveFilterCount().toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      showTodayTasksOnly = !showTodayTasksOnly;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: showTodayTasksOnly ? Color(0xFF2563EB) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.today,
                          size: 16,
                          color: showTodayTasksOnly ? Colors.white : Colors.grey[600],
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Today',
                          style: TextStyle(
                            color: showTodayTasksOnly ? Colors.white : Colors.grey[600],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.expand_more),
              ],
            ),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 45,
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            isDense: true,
                          ),
                          style: TextStyle(fontSize: 14, color: Colors.black),
                          dropdownColor: Colors.white,
                          value: selectedStatusFilter,
                          items: [
                            DropdownMenuItem(
                                value: 'all',
                                child: Text('All Statuses', style: TextStyle(color: Colors.black))
                            ),
                            DropdownMenuItem(
                                value: 'assigned',
                                child: Text('Assigned', style: TextStyle(color: Colors.black))
                            ),
                            DropdownMenuItem(
                                value: 'in_progress',
                                child: Text('In Progress', style: TextStyle(color: Colors.black))
                            ),
                            DropdownMenuItem(
                                value: 'hold',
                                child: Text('On Hold', style: TextStyle(color: Colors.black))
                            ),
                            DropdownMenuItem(
                                value: 'completed',
                                child: Text('Completed', style: TextStyle(color: Colors.black))
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedStatusFilter = value ?? 'all';
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    if (selectedStatusFilter != 'all' || showTodayTasksOnly)
                      Expanded(
                        flex: 1,
                        child: Container(
                          height: 45,
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.clear, size: 16, color: Colors.red[600]),
                            label: Text(
                              'Clear',
                              style: TextStyle(color: Colors.red[600], fontSize: 12),
                            ),
                            onPressed: () {
                              setState(() {
                                selectedStatusFilter = 'all';
                                showTodayTasksOnly = false;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.red[300]!),
                              padding: EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                        showTodayTasksOnly
                            ? 'No tasks due today'
                            : 'Try adjusting the filters',
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              final filteredDocs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final assignedEmployees = data['assignedEmployees'] as List<dynamic>? ?? [];

                // Check if current user is assigned to this task (new structure)
                bool isUserAssigned = false;
                String userStatus = 'assigned';

                // First check new assignedEmployees structure
                for (var employee in assignedEmployees) {
                  if (employee['employeeId'] == user.uid) {
                    isUserAssigned = true;
                    userStatus = employee['status'] ?? 'assigned';
                    break;
                  }
                }

                // Fallback to old assignedTo structure for backward compatibility
                if (!isUserAssigned && data['assignedTo'] == user.uid) {
                  isUserAssigned = true;
                  userStatus = data['status'] ?? 'assigned';
                }

                // Only include tasks assigned to current user
                if (!isUserAssigned) {
                  return false;
                }

                if (selectedStatusFilter != 'all' && userStatus != selectedStatusFilter) {
                  return false;
                }

                return data['title'] != null &&
                    data['startDate'] != null &&
                    data['dueDate'] != null;
              }).toList();

              if (filteredDocs.isEmpty) {
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
                        'No tasks match the current filters',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Try adjusting the status filters',
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                padding: EdgeInsets.all(24.0),
                children: filteredDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return TaskCardWidget(
                    data: data,
                    docId: doc.id,
                    isManager: widget.isManager,
                    onRefresh: () => setState(() {}),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  int _getEmployeeActiveFilterCount() {
    int count = 0;
    if (selectedStatusFilter != 'all') count++;
    if (showTodayTasksOnly) count++;
    return count;
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
              'No tasks found',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              showTodayTasksOnly
                  ? 'No tasks due today'
                  : 'Try adjusting the filters or create new tasks',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Apply filters to the results
    final filteredDocs = snapshot.data!.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final overallStatus = data['overallStatus']?.toString() ?? data['status']?.toString() ?? 'assigned';
      final assignedEmployees = data['assignedEmployees'] as List<dynamic>? ?? [];

      // Apply status filter
      if (selectedStatusFilter != 'all' && overallStatus != selectedStatusFilter) {
        return false;
      }

      // Apply employee filter
      if (selectedFilterEmployeeUid != null) {
        bool employeeFound = false;
        for (var employee in assignedEmployees) {
          if (employee['employeeId'] == selectedFilterEmployeeUid) {
            employeeFound = true;
            break;
          }
        }
        if (!employeeFound) {
          return false;
        }
      }

      return data['title'] != null &&
          data['startDate'] != null &&
          data['dueDate'] != null;
    }).toList();

    if (filteredDocs.isEmpty) {
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
              'No tasks match the current filters',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Try adjusting the status or employee filters',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(24.0),
      children: filteredDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return TaskCardWidget(
          data: data,
          docId: doc.id,
          isManager: widget.isManager,
          onRefresh: () => setState(() {}),
        );
      }).toList(),
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
            Tab(text: 'Create Task'),
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