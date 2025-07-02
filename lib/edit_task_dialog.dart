import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:intl/intl.dart';

class EditTaskDialog extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final String taskId;
  final VoidCallback onTaskUpdated;

  const EditTaskDialog({
    Key? key,
    required this.taskData,
    required this.taskId,
    required this.onTaskUpdated,
  }) : super(key: key);

  @override
  _EditTaskDialogState createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late TextEditingController titleController;
  late TextEditingController descController;
  final TextEditingController _searchController = TextEditingController();
  String? selectedEmployeeUid;
  DateTime? startDate;
  DateTime? endDate;
  bool _isUpdating = false;
  bool _isEmployeeSelectorExpanded = false;
  List<DocumentSnapshot> _allEmployees = [];
  List<DocumentSnapshot> _filteredEmployees = [];
  bool _employeesLoaded = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data
    titleController = TextEditingController(text: widget.taskData['title']?.toString() ?? '');
    descController = TextEditingController(text: widget.taskData['description']?.toString() ?? '');
    selectedEmployeeUid = widget.taskData['assignedTo']?.toString();

    // Parse dates
    try {
      if (widget.taskData['startDate'] != null) {
        startDate = DateTime.parse(widget.taskData['startDate'].toString());
      }
      if (widget.taskData['dueDate'] != null) {
        endDate = DateTime.parse(widget.taskData['dueDate'].toString());
      }
    } catch (e) {
      print('Error parsing dates: $e');
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    _searchController.dispose();
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

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (startDate ?? DateTime.now())
          : (endDate ?? startDate?.add(Duration(days: 1)) ?? DateTime.now().add(Duration(days: 1))),
      firstDate: DateTime(2020),
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
            endDate = startDate!.add(Duration(days: 1));
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

  Future<void> _updateTask() async {
    if (titleController.text.isEmpty ||
        descController.text.isEmpty ||
        startDate == null ||
        endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill all required fields'),
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
      _isUpdating = true;
    });

    final currentUserId = fa.FirebaseAuth.instance.currentUser!.uid;

    try {
      // Check if employee assignment changed
      bool assignmentChanged = selectedEmployeeUid != widget.taskData['assignedTo'];
      String? previousAssignee = widget.taskData['assignedTo']?.toString();

      // Verify employee if selected
      if (selectedEmployeeUid != null) {
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
          setState(() {
            _isUpdating = false;
          });
          return;
        }
      }

      // Prepare update data
      Map<String, dynamic> updateData = {
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'assignedTo': selectedEmployeeUid,
        'startDate': startDate!.toIso8601String().split('T')[0],
        'dueDate': endDate!.toIso8601String().split('T')[0],
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Update status based on assignment
      String currentStatus = widget.taskData['status']?.toString() ?? 'assigned';
      if (assignmentChanged) {
        if (selectedEmployeeUid == null) {
          // Task became unassigned
          updateData['status'] = 'unassigned';
        } else if (previousAssignee == null) {
          // Task was unassigned, now assigned
          updateData['status'] = 'assigned';
        }
        // If changing from one employee to another, keep current status if it's not unassigned
        else if (currentStatus == 'unassigned') {
          updateData['status'] = 'assigned';
        }
      }

      // Update the task
      await FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).update(updateData);

      // Send notification email if newly assigned
      if (assignmentChanged && selectedEmployeeUid != null) {
        try {
          final employeeDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(selectedEmployeeUid)
              .get();
          final employeeData = employeeDoc.data() as Map<String, dynamic>;
          final employeeEmail = employeeData['email'];
          final employeeName = employeeData['name'];

          final managerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .get();
          final managerData = managerDoc.data() as Map<String, dynamic>;
          final managerName = managerData['name'] ?? 'Manager';

          if (employeeEmail != null && employeeName != null) {
            // You can implement email notification here
            // await EmailService.sendTaskAssignmentEmail(...);
          }
        } catch (e) {
          print('Error sending notification: $e');
        }
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Task updated successfully'),
            ],
          ),
          backgroundColor: Colors.green[500],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      widget.onTaskUpdated();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating task: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    } finally {
      setState(() {
        _isUpdating = false;
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
                  Flexible(
                    child: Text(
                      selectedDate == null
                          ? 'Select Date'
                          : DateFormat('MMM dd, yyyy').format(selectedDate),
                      style: TextStyle(
                        color: selectedDate == null ? Color(0xFF9CA3AF) : Color(0xFF374151),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildEmployeeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Assign to Employee ${selectedEmployeeUid != null ? "(1 selected)" : "(Optional)"}',
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
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search employees...',
              prefixIcon: Icon(Icons.search, color: Color(0xFF6B7280)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: _filterEmployees,
          ),
          SizedBox(height: 12),
        ],

        if (!_isEmployeeSelectorExpanded && selectedEmployeeUid != null && _employeesLoaded) ...[
          // Show selected employee
          _buildSelectedEmployeeChip(),
          SizedBox(height: 8),
        ],

        if (!_isEmployeeSelectorExpanded && selectedEmployeeUid != null && !_employeesLoaded) ...[
          // Show loading state for selected employee
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Color(0xFF3B82F6).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading employee...',
                  style: TextStyle(color: Color(0xFF1E40AF)),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
        ],

        if (!_isEmployeeSelectorExpanded && selectedEmployeeUid == null) ...[
          // Show unassigned state
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
                // Unassigned option
                Container(
                  decoration: BoxDecoration(
                    color: selectedEmployeeUid == null ? Color(0xFFE0F2FE) : null,
                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[400],
                      child: Icon(Icons.person_off, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      'Unassigned',
                      style: TextStyle(
                        fontWeight: selectedEmployeeUid == null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('Leave task unassigned'),
                    trailing: selectedEmployeeUid == null
                        ? Icon(Icons.check_circle, color: Color(0xFF2563EB))
                        : null,
                    onTap: () {
                      setState(() {
                        selectedEmployeeUid = null;
                      });
                    },
                  ),
                ),
                // Employee list
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

                      return Container(
                        decoration: BoxDecoration(
                          color: selectedEmployeeUid == employeeId ? Color(0xFFE0F2FE) : null,
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
                              fontWeight: selectedEmployeeUid == employeeId ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            employeeEmail,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selectedEmployeeUid == employeeId
                              ? Icon(Icons.check_circle, color: Color(0xFF2563EB))
                              : null,
                          onTap: () {
                            setState(() {
                              selectedEmployeeUid = employeeId;
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

  Widget _buildSelectedEmployeeChip() {
    DocumentSnapshot? selectedEmployee;
    try {
      selectedEmployee = _allEmployees.firstWhere((emp) => emp.id == selectedEmployeeUid);
    } catch (e) {
      // Employee not found
      return Container(
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
              'No employee assigned',
              style: TextStyle(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    final employeeData = selectedEmployee.data() as Map<String, dynamic>;
    final employeeName = employeeData['name'] ?? 'Unknown';

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFF3B82F6).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFF2563EB),
            child: Text(
              employeeName.isNotEmpty ? employeeName[0].toUpperCase() : 'U',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              employeeName,
              style: TextStyle(
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                selectedEmployeeUid = null;
              });
            },
            icon: Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Task',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white),
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.all(4),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Task Title
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
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 16),

                    // Task Description
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
                      maxLines: 3,
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 16),

                    // Date Selectors
                    Row(
                      children: [
                        _buildDateSelector(
                          label: 'Start Date *',
                          selectedDate: startDate,
                          isStartDate: true,
                        ),
                        SizedBox(width: 12),
                        _buildDateSelector(
                          label: 'Due Date *',
                          selectedDate: endDate,
                          isStartDate: false,
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // Employee Assignment
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .where('managerId', isEqualTo: currentUserId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Container(
                            height: 60,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                              ),
                            ),
                          );
                        }

                        _allEmployees = snapshot.data!.docs;
                        if (_filteredEmployees.isEmpty && _searchController.text.isEmpty) {
                          _filteredEmployees = _allEmployees;
                        }

                        // Mark employees as loaded
                        if (!_employeesLoaded) {
                          _employeesLoaded = true;
                        }

                        return _buildEmployeeSelector();
                      },
                    ),
                    SizedBox(height: 20),

                    // Current Status Info
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Color(0xFF3B82F6).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Current Status: ${widget.taskData['status']?.toString().toUpperCase() ?? 'UNKNOWN'}',
                              style: TextStyle(color: Color(0xFF1E40AF), fontSize: 13, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isUpdating ? null : () => Navigator.pop(context),
                      child: Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (titleController.text.isEmpty ||
                          descController.text.isEmpty ||
                          startDate == null ||
                          endDate == null ||
                          _isUpdating)
                          ? null
                          : _updateTask,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: _isUpdating
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Updating...'),
                        ],
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save, size: 18),
                          SizedBox(width: 6),
                          Text('Update Task'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}