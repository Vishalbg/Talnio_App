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

  final List<String> _leaveTypes = ['Casual', 'Sick', 'Vacation', 'Other'];

  // Helper function to capitalize strings
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? DateTime.now().add(Duration(days: 1)) // Start from tomorrow
          : (_startDate?.add(Duration(days: 1)) ?? DateTime.now().add(Duration(days: 2))), // End date starts from day after start date
      firstDate: isStart
          ? DateTime.now().add(Duration(days: 1)) // Minimum start date is tomorrow
          : (_startDate?.add(Duration(days: 1)) ?? DateTime.now().add(Duration(days: 1))), // Minimum end date is day after start date
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          // Automatically set end date to one day after start date
          _endDate = picked.add(Duration(days: 1));
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.requestLeave(
        userId: user.uid,
        startDate: _startDate!,
        endDate: _endDate!,
        leaveType: _leaveType,
        reason: _reasonController.text.trim(),
        context: context,
      );

      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
        _leaveType = 'Casual';
      });
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
                        Text(
                          leaveType,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
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
                            _capitalize(status), // Fixed: Use the helper function
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
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'From: ${DateFormat('MMM dd, yyyy').format(startDate)}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
        title: Text('Leave Requests', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request a New Leave',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
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
                    ),
                    items: _leaveTypes
                        .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _leaveType = value!;
                      });
                    },
                    validator: (value) => value == null ? 'Please select a leave type' : null,
                  ),
                  SizedBox(height: 16),
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
                      'Submit Leave Request',
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