import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class LeaveRequestScreen extends StatefulWidget {
  @override
  _LeaveRequestScreenState createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  String _leaveType = 'Casual';
  final _reasonController = TextEditingController();
  bool _isLoading = false;
  String? _editingRequestId;
  int _remainingLeaves = 20;
  int _usedLeaves = 0;

  final List<Map<String, dynamic>> _leaveTypes = [
    {'value': 'Casual', 'label': 'Casual Leave', 'icon': Icons.event_available},
    {'value': 'Sick', 'label': 'Sick Leave', 'icon': Icons.local_hospital},
    {'value': 'Vacation', 'label': 'Vacation Leave', 'icon': Icons.beach_access},
    {'value': 'Other', 'label': 'Other Leave', 'icon': Icons.more_horiz},
  ];

  // Calculate selected days
  int get _selectedDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  @override
  void initState() {
    super.initState();
    _loadLeaveBalance();
  }

  Future<void> _loadLeaveBalance() async {
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Get approved leave requests for current year
      final now = DateTime.now();
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31);

      final snapshot = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'approved')
          .where('startDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfYear))
          .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfYear))
          .get();

      int totalUsedDays = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final startDate = (data['startDate'] as Timestamp).toDate();
        final endDate = (data['endDate'] as Timestamp).toDate();
        totalUsedDays += endDate.difference(startDate).inDays + 1;
      }

      setState(() {
        _usedLeaves = totalUsedDays;
        _remainingLeaves = 20 - totalUsedDays;
      });
    } catch (e) {
      print('Error loading leave balance: $e');
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    DateTime initialDate;
    DateTime firstDate;
    DateTime lastDate = DateTime.now().add(Duration(days: 365));

    if (isStart) {
      // For sick leave, allow past dates (up to 30 days back)
      if (_leaveType == 'Sick') {
        initialDate = DateTime.now();
        firstDate = DateTime.now().subtract(Duration(days: 30));
      } else {
        // For other leave types, allow same day selection
        initialDate = DateTime.now();
        firstDate = DateTime.now(); // Changed from DateTime.now().add(Duration(days: 1))
      }
    } else {
      initialDate = _startDate?.add(Duration(days: 1)) ?? DateTime.now().add(Duration(days: 1));
      firstDate = _startDate ?? DateTime.now(); // Allow end date to be same as start date
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          // Auto-set end date to same day for single day leave
          _endDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _editLeaveRequest(Map<String, dynamic> requestData, String requestId) {
    setState(() {
      _editingRequestId = requestId;
      _startDate = (requestData['startDate'] as Timestamp).toDate();
      _endDate = (requestData['endDate'] as Timestamp).toDate();
      _leaveType = requestData['leaveType'] ?? 'Vacation';
      _reasonController.text = requestData['reason'] ?? '';
    });

    // Scroll to form
    Scrollable.ensureVisible(
      _formKey.currentContext!,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _cancelEdit() {
    setState(() {
      _editingRequestId = null;
      _startDate = null;
      _endDate = null;
      _leaveType = 'Casual';
      _reasonController.clear();
    });
  }

  void _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if user has enough remaining leaves
    final requestedDays = _endDate!.difference(_startDate!).inDays + 1;
    if (_remainingLeaves < requestedDays && _editingRequestId == null) {
      _showSnackBar('Insufficient leave balance. You have $_remainingLeaves days remaining.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (_editingRequestId != null) {
        // Update existing request
        await FirebaseFirestore.instance
            .collection('leave_requests')
            .doc(_editingRequestId)
            .update({
          'startDate': Timestamp.fromDate(_startDate!),
          'endDate': Timestamp.fromDate(_endDate!),
          'leaveType': _leaveType,
          'reason': _reasonController.text.trim(),
          'updatedAt': Timestamp.now(),
        });
        _showSnackBar('Leave request updated successfully!');
      } else {
        // Create new request
        await authProvider.requestLeave(
          userId: user.uid,
          startDate: _startDate!,
          endDate: _endDate!,
          leaveType: _leaveType,
          reason: _reasonController.text.trim(),
          context: context,
        );
      }

      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
        _leaveType = 'Casual';
        _editingRequestId = null;
      });

      // Reload leave balance
      _loadLeaveBalance();
    } catch (e) {
      _showSnackBar('Failed to submit leave request: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildLeaveBalanceCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Leave Balance ${DateTime.now().year}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBalanceItem('Total', '20', Colors.blue),
                _buildBalanceItem('Used', '$_usedLeaves', Colors.orange),
                _buildBalanceItem('Remaining', '$_remainingLeaves', Colors.green),
              ],
            ),
            SizedBox(height: 16),
            LinearProgressIndicator(
              value: _usedLeaves / 20,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _remainingLeaves < 5 ? Colors.red : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveStatusList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leave_requests')
          .where('userId', isEqualTo: userId)
          .orderBy('requestTime', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('StreamBuilder error: ${snapshot.error}');
          _showSnackBar('Error loading leave requests', isError: true);
          return Center(
            child: Text('Error loading requests: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
                SizedBox(height: 16),
                Text(
                  'No leave requests found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final data = request.data() as Map<String, dynamic>;
            final startDate = (data['startDate'] as Timestamp).toDate();
            final endDate = (data['endDate'] as Timestamp).toDate();
            final leaveType = data['leaveType'] ?? 'Unknown';
            final reason = data['reason'] ?? '';
            final status = data['status'] ?? 'pending';
            final rejectionReason = data['rejectionReason'] ?? '';
            final requestTime = (data['requestTime'] as Timestamp?)?.toDate();
            final days = endDate.difference(startDate).inDays + 1;

            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _leaveTypes.firstWhere(
                                    (type) => type['value'] == leaveType,
                                orElse: () => {'icon': Icons.more_horiz},
                              )['icon'],
                              color: Colors.blue[600],
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              leaveType,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: status == 'approved'
                                    ? Colors.green[50]
                                    : status == 'rejected'
                                    ? Colors.red[50]
                                    : Colors.orange[50],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _capitalize(status),
                                style: TextStyle(
                                  color: status == 'approved'
                                      ? Colors.green[700]
                                      : status == 'rejected'
                                      ? Colors.red[700]
                                      : Colors.orange[700],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (status == 'pending') ...[
                              SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.edit, size: 20, color: Colors.blue[600]),
                                onPressed: () => _editLeaveRequest(data, request.id),
                                tooltip: 'Edit Request',
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'From: ${DateFormat('MMM dd, yyyy').format(startDate)}',
                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          ),
                        ),
                        Text(
                          '$days day${days > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[600],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'To: ${DateFormat('MMM dd, yyyy').format(endDate)}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Reason: $reason',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
                      SizedBox(height: 8),
                      Text(
                        'Rejection Reason: $rejectionReason',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    SizedBox(height: 8),
                    Text(
                      'Requested: ${requestTime != null ? DateFormat('MMM dd, yyyy HH:mm').format(requestTime) : 'N/A'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = fa.FirebaseAuth.instance.currentUser;

    if (authProvider.role != 'employee' || currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text('Access denied: Only employees can access leave requests'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Leave Management', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeaveBalanceCard(),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _editingRequestId != null ? 'Edit Leave Request' : 'Request Leave',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                if (_editingRequestId != null)
                  TextButton(
                    onPressed: _cancelEdit,
                    child: Text('Cancel Edit'),
                  ),
              ],
            ),
            SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _leaveType,
                    decoration: InputDecoration(
                      labelText: 'Leave Type',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(
                        _leaveTypes.firstWhere(
                              (type) => type['value'] == _leaveType,
                        )['icon'],
                      ),
                    ),
                    items: _leaveTypes
                        .map<DropdownMenuItem<String>>((type) => DropdownMenuItem<String>(
                      value: type['value'] as String,
                      child: Row(
                        children: [
                          Icon(type['icon'] as IconData, size: 20),
                          SizedBox(width: 8),
                          Text(type['label'] as String),
                        ],
                      ),
                    ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _leaveType = value!;
                        // Reset dates when changing leave type
                        _startDate = null;
                        _endDate = null;
                      });
                    },
                    validator: (value) => value == null ? 'Please select a leave type' : null,
                  ),
                  SizedBox(height: 16),
                  if (_leaveType == 'Sick')
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue[600], size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'For sick leave, you can select past dates (up to 30 days back)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_leaveType == 'Sick') SizedBox(height: 16),
                  InkWell(
                    onTap: () => _selectDate(context, true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Start Date',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        _startDate == null
                            ? 'Select start date'
                            : DateFormat('MMM dd, yyyy').format(_startDate!),
                        style: TextStyle(
                          color: _startDate == null ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  InkWell(
                    onTap: () => _selectDate(context, false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'End Date',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        _endDate == null
                            ? 'Select end date'
                            : DateFormat('MMM dd, yyyy').format(_endDate!),
                        style: TextStyle(
                          color: _endDate == null ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  // Show selected days after end date
                  if (_startDate != null && _endDate != null) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event, color: Colors.blue[600], size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Days Selected: $_selectedDays day${_selectedDays > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[700],
                            ),
                          ),
                          if (_selectedDays > _remainingLeaves) ...[
                            SizedBox(width: 8),
                            Icon(Icons.warning, color: Colors.red[600], size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Exceeds balance!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonController,
                    decoration: InputDecoration(
                      labelText: 'Reason for Leave',
                      hintText: 'Explain why you need this leave...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 4,
                    validator: (value) =>
                    value!.trim().isEmpty ? 'Please provide a reason' : null,
                  ),
                  SizedBox(height: 24),
                  _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                    onPressed: (_startDate == null || _endDate == null)
                        ? null
                        : _submitLeaveRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _editingRequestId != null
                          ? 'Update Leave Request'
                          : 'Submit Leave Request',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),
            Text(
              'Your Leave Requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 16),
            _buildLeaveStatusList(currentUser.uid),
          ],
        ),
      ),
    );
  }
}