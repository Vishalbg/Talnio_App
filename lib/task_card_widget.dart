import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:intl/intl.dart';
import 'edit_task_dialog.dart';

class TaskCardWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isManager;
  final VoidCallback onRefresh;
  final bool showEditButton;

  const TaskCardWidget({
    Key? key,
    required this.data,
    required this.docId,
    required this.isManager,
    required this.onRefresh,
    this.showEditButton = true,
  }) : super(key: key);

  @override
  _TaskCardWidgetState createState() => _TaskCardWidgetState();
}

class _TaskCardWidgetState extends State<TaskCardWidget> with TickerProviderStateMixin {
  final TextEditingController delayReasonController = TextEditingController();
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<Color?> _colorAnimation;

  double _dragPosition = 0.0;
  bool _isSliding = false;
  bool _isStarting = false;
  final double _slideThreshold = 0.7;
  bool _showQuickActionsAfterStart = false;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _colorAnimation = ColorTween(
      begin: Color(0xFF3B82F6),
      end: Color(0xFF10B981),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    // Check if current user's status is assigned and start pulse animation
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && !widget.isManager) {
      final userStatus = _getCurrentUserStatus(currentUserId);
      if (userStatus == 'assigned') {
        _pulseController.repeat(reverse: true);
      }
    }

    _checkIfNeedsQuickActionsAfterStart();
  }

  // Get current user's status from assignedEmployees array
  String _getCurrentUserStatus(String userId) {
    final assignedEmployees = widget.data['assignedEmployees'] as List<dynamic>? ?? [];
    for (var employee in assignedEmployees) {
      if (employee['employeeId'] == userId) {
        return employee['status'] ?? 'assigned';
      }
    }
    return 'assigned';
  }

  // Get current user's employee data from assignedEmployees array
  Map<String, dynamic>? _getCurrentUserEmployeeData(String userId) {
    final assignedEmployees = widget.data['assignedEmployees'] as List<dynamic>? ?? [];
    for (var employee in assignedEmployees) {
      if (employee['employeeId'] == userId) {
        return employee as Map<String, dynamic>;
      }
    }
    return null;
  }

  // Calculate overall task status from individual employee statuses
  String _calculateOverallStatus(List<dynamic> assignedEmployees) {
    if (assignedEmployees.isEmpty) return 'unassigned';

    int completed = 0;
    int inProgress = 0;
    int onHold = 0;
    int assigned = 0;

    for (var employee in assignedEmployees) {
      final status = employee['status'] ?? 'assigned';
      switch (status) {
        case 'completed':
          completed++;
          break;
        case 'in_progress':
          inProgress++;
          break;
        case 'hold':
          onHold++;
          break;
        case 'assigned':
          assigned++;
          break;
      }
    }

    // If all employees completed, task is completed
    if (completed == assignedEmployees.length) {
      return 'completed';
    }

    // If any employee is in progress, task is in progress
    if (inProgress > 0) {
      return 'in_progress';
    }

    // If any employee is on hold, task is on hold
    if (onHold > 0) {
      return 'hold';
    }

    // Otherwise, task is assigned
    return 'assigned';
  }

  void _checkIfNeedsQuickActionsAfterStart() {
    try {
      final String dueDateStr = widget.data['dueDate']?.toString() ?? '';
      final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

      if (dueDateStr.isNotEmpty && currentUserId != null) {
        final dueDate = DateTime.parse(dueDateStr);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

        final userStatus = _getCurrentUserStatus(currentUserId);
        if (dueDateOnly.isAtSameMomentAs(today) && userStatus == 'assigned') {
          _showQuickActionsAfterStart = true;
        }
      }
    } catch (e) {
      print('Error checking dates: $e');
    }
  }

  @override
  void dispose() {
    delayReasonController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool _needsDelayReasonToday(Map<String, dynamic> taskData) {
    final dueDate = DateTime.parse(taskData['dueDate']);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    if (today.isAfter(dueDateOnly) && currentUserId != null) {
      final userStatus = _getCurrentUserStatus(currentUserId);
      if (userStatus != 'completed') {
        final delayReasons = taskData['delayReasons'] as List<dynamic>? ?? [];
        for (var reason in delayReasons) {
          if (reason['submittedAt'] != null && reason['employeeId'] == currentUserId) {
            final submittedDate = (reason['submittedAt'] as Timestamp).toDate();
            final submittedDay = DateTime(submittedDate.year, submittedDate.month, submittedDate.day);
            if (submittedDay.isAtSameMomentAs(today)) {
              return false;
            }
          }
        }
        return true;
      }
    }
    return false;
  }

  Future<void> _showDeleteConfirmationDialog() async {
    final String taskTitle = widget.data['title']?.toString() ?? 'Untitled Task';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Color(0xFFDC2626), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Task',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                overflow: TextOverflow.ellipsis,
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
                color: Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Color(0xFFDC2626).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. The task will be permanently deleted.',
                      style: TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Are you sure you want to delete this task?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                taskTitle,
                style: TextStyle(fontSize: 14, color: Colors.grey[700], fontStyle: FontStyle.italic),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (mounted) {
                await _deleteTask();
              }
            },
            child: Text('Delete Task'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTask() async {
    try {
      await FirebaseFirestore.instance.collection('tasks').doc(widget.docId).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Task deleted successfully')),
            ],
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting task: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  // Updated to work with individual employee status
  Future<void> _updateIndividualStatus(String taskId, String newStatus) async {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final taskDoc = await FirebaseFirestore.instance.collection('tasks').doc(taskId).get();
      if (!taskDoc.exists) return;

      final taskData = taskDoc.data() as Map<String, dynamic>;
      final assignedEmployees = List<Map<String, dynamic>>.from(taskData['assignedEmployees'] ?? []);

      // Update current user's status
      for (int i = 0; i < assignedEmployees.length; i++) {
        if (assignedEmployees[i]['employeeId'] == currentUserId) {
          assignedEmployees[i]['status'] = newStatus;

          // Update timestamps based on status
          if (newStatus == 'in_progress') {
            assignedEmployees[i]['actualStartDate'] = DateTime.now().toIso8601String().split('T')[0];
          } else if (newStatus == 'completed') {
            assignedEmployees[i]['actualEndDate'] = DateTime.now().toIso8601String().split('T')[0];
          }
          break;
        }
      }

      // Calculate new overall status
      final overallStatus = _calculateOverallStatus(assignedEmployees);

      // Update the task
      await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
        'assignedEmployees': assignedEmployees,
        'overallStatus': overallStatus,
        'status': overallStatus, // Keep for backward compatibility
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      String message;
      Color backgroundColor;
      IconData icon;

      switch (newStatus) {
        case 'in_progress':
          message = 'Task started successfully! 🚀';
          backgroundColor = Color(0xFF10B981);
          icon = Icons.rocket_launch;
          break;
        case 'completed':
          message = 'Task completed successfully! 🎉';
          backgroundColor = Colors.green[500]!;
          icon = Icons.celebration;
          break;
        case 'hold':
          message = 'Task put on hold';
          backgroundColor = Color(0xFFF59E0B);
          icon = Icons.pause_circle;
          break;
        default:
          message = 'Status updated successfully';
          backgroundColor = Color(0xFF3B82F6);
          icon = Icons.check_circle;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  Future<void> _startTask(String taskId) async {
    if (_isStarting) return;

    setState(() {
      _isStarting = true;
    });

    try {
      _pulseController.stop();
      await _slideController.forward();

      await _updateIndividualStatus(taskId, 'in_progress');

      if (_showQuickActionsAfterStart) {
        Future.delayed(Duration(milliseconds: 1500), () {
          if (mounted) {
            _showQuickActionsDialog(taskId, widget.data['title'] ?? 'Task');
          }
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Error starting task: $e')),
            ],
          ),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _dragPosition = 0.0;
        });
        _slideController.reset();
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _isSliding = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, double maxWidth) {
    setState(() {
      _dragPosition += details.delta.dx;
      _dragPosition = _dragPosition.clamp(0.0, maxWidth - 60);

      double progress = _dragPosition / (maxWidth - 60);
      _slideController.value = progress;
    });
  }

  void _onPanEnd(DragEndDetails details, double maxWidth) {
    double progress = _dragPosition / (maxWidth - 60);

    if (progress >= _slideThreshold && !_isStarting) {
      _startTask(widget.docId);
    } else {
      _slideController.animateBack(0.0);
      setState(() {
        _dragPosition = 0.0;
        _isSliding = false;
      });
    }
  }

  Widget _buildSlideToStart() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final buttonWidth = 60.0;
        final trackWidth = maxWidth - 8;

        return Container(
          height: 70,
          margin: EdgeInsets.symmetric(vertical: 8),
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _slideAnimation,
                builder: (context, child) {
                  return Container(
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF3B82F6).withOpacity(0.1),
                          Color(0xFF10B981).withOpacity(_slideAnimation.value * 0.3),
                        ],
                        stops: [0.0, _slideAnimation.value.clamp(0.3, 1.0)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(35),
                      border: Border.all(
                        color: _colorAnimation.value ?? Color(0xFF3B82F6),
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: (_dragPosition + buttonWidth) * 1.1,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF3B82F6).withOpacity(0.2),
                                  Color(0xFF10B981).withOpacity(0.2),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(35),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _slideAnimation,
                              builder: (context, child) {
                                String text;
                                IconData icon;
                                Color textColor;

                                if (_isStarting) {
                                  text = 'Starting Task...';
                                  icon = Icons.hourglass_empty;
                                  textColor = Color(0xFF10B981);
                                } else if (_slideAnimation.value >= _slideThreshold) {
                                  text = 'Release to Start! 🚀';
                                  icon = Icons.rocket_launch;
                                  textColor = Color(0xFF10B981);
                                } else if (_slideAnimation.value > 0.3) {
                                  text = 'Keep sliding...';
                                  icon = Icons.trending_flat;
                                  textColor = Color(0xFF3B82F6);
                                } else {
                                  text = 'Slide to Start Task';
                                  icon = Icons.swipe_right;
                                  textColor = Color(0xFF6B7280);
                                }

                                return AnimatedSwitcher(
                                  duration: Duration(milliseconds: 200),
                                  child: Row(
                                    key: ValueKey(text),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, color: textColor, size: 20),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          text,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              AnimatedBuilder(
                animation: Listenable.merge([_slideAnimation, _pulseAnimation]),
                builder: (context, child) {
                  return Positioned(
                    left: 4 + _dragPosition,
                    top: 4,
                    child: Transform.scale(
                      scale: _isSliding ? 1.05 : _pulseAnimation.value,
                      child: GestureDetector(
                        onPanStart: _onPanStart,
                        onPanUpdate: (details) => _onPanUpdate(details, trackWidth),
                        onPanEnd: (details) => _onPanEnd(details, trackWidth),
                        child: Container(
                          width: buttonWidth,
                          height: 62,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isStarting
                                  ? [Color(0xFF10B981), Color(0xFF059669)]
                                  : [
                                _colorAnimation.value ?? Color(0xFF3B82F6),
                                (_colorAnimation.value ?? Color(0xFF3B82F6)).withOpacity(0.8),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(31),
                            boxShadow: [
                              BoxShadow(
                                color: (_colorAnimation.value ?? Color(0xFF3B82F6)).withOpacity(0.4),
                                blurRadius: _isSliding ? 12 : 8,
                                offset: Offset(0, _isSliding ? 4 : 2),
                                spreadRadius: _isSliding ? 2 : 0,
                              ),
                            ],
                          ),
                          child: _isStarting
                              ? Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          )
                              : Icon(
                            _slideAnimation.value >= _slideThreshold
                                ? Icons.rocket_launch
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showQuickActionsDialog(String taskId, String taskTitle) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.today, color: Color(0xFF3B82F6), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Task Due Today',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                overflow: TextOverflow.ellipsis,
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
                      'This task is due today. What would you like to do?',
                      style: TextStyle(color: Color(0xFF1E40AF), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              taskTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _completeTaskDirectly(taskId);
                    },
                    icon: Icon(Icons.check_circle, size: 20),
                    label: Text('Complete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showOnHoldDialog(taskId, taskTitle);
                    },
                    icon: Icon(Icons.pause_circle, size: 20),
                    label: Text('On Hold'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Continue Working', style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  Future<void> _completeTaskDirectly(String taskId) async {
    await _updateIndividualStatus(taskId, 'completed');
  }

  Future<void> _showOnHoldDialog(String taskId, String taskTitle) async {
    final TextEditingController holdReasonController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.pause_circle, color: Color(0xFFF59E0B), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Put Task On Hold',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  overflow: TextOverflow.ellipsis,
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
                        'Please provide a reason for putting this task on hold.',
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
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
              SizedBox(height: 16),
              TextField(
                controller: holdReasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for Hold *',
                  hintText: 'Explain why you need to put this task on hold...',
                  errorText: holdReasonController.text.isEmpty ? 'Reason is required' : null,
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
              onPressed: holdReasonController.text.trim().isEmpty
                  ? null
                  : () async {
                try {
                  await _addDelayReason(taskId, holdReasonController.text.trim(), 'hold');
                  await _updateIndividualStatus(taskId, 'hold');
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error putting task on hold: $e'),
                      backgroundColor: Colors.red[400],
                    ),
                  );
                }
              },
              child: Text('Put On Hold'),
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
                  'Complete Task',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  overflow: TextOverflow.ellipsis,
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
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
              SizedBox(height: 16),
              TextField(
                controller: submissionController,
                decoration: InputDecoration(
                  labelText: 'Completion Comments (Optional)',
                  hintText: 'Add any comments about the task completion...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.comment, color: Color(0xFF6B7280)),
                ),
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _updateIndividualSubmission(taskId, submissionController.text.trim());
                  await _updateIndividualStatus(taskId, 'completed');
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error completing task: $e'),
                      backgroundColor: Colors.red[400],
                    ),
                  );
                }
              },
              child: Text('Complete Task'),
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

  Future<void> _updateIndividualSubmission(String taskId, String submissionText) async {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final taskDoc = await FirebaseFirestore.instance.collection('tasks').doc(taskId).get();
      if (!taskDoc.exists) return;

      final taskData = taskDoc.data() as Map<String, dynamic>;
      final assignedEmployees = List<Map<String, dynamic>>.from(taskData['assignedEmployees'] ?? []);

      // Update current user's submission text
      for (int i = 0; i < assignedEmployees.length; i++) {
        if (assignedEmployees[i]['employeeId'] == currentUserId) {
          assignedEmployees[i]['submissionText'] = submissionText;
          break;
        }
      }

      await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
        'assignedEmployees': assignedEmployees,
      });
    } catch (e) {
      print('Error updating submission: $e');
    }
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
                  overflow: TextOverflow.ellipsis,
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
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
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
                  await _addDelayReason(taskId, delayReasonController.text.trim(), 'delay');
                  Navigator.pop(context);
                  _showDelayReasonOptionsDialog(taskId, taskTitle, delayReasonController.text.trim());
                } catch (e) {
                  if (!mounted) return;
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

  Future<void> _addDelayReason(String taskId, String reason, String type) async {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final now = DateTime.now();
      final formattedDate = DateFormat('yyyy-MM-dd').format(now);

      await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
        'delayReasons': FieldValue.arrayUnion([
          {
            'reason': reason,
            'submittedAt': Timestamp.fromDate(now),
            'date': formattedDate,
            'type': type,
            'employeeId': currentUserId,
          }
        ]),
        'lastDelayReasonDate': formattedDate,
      });
    } catch (e) {
      print('Error adding delay reason: $e');
    }
  }

  Future<void> _showDelayReasonOptionsDialog(String taskId, String taskTitle, String delayReason) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF3B82F6), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'What Next?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                overflow: TextOverflow.ellipsis,
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
                      'Delay reason submitted. What would you like to do with this task?',
                      style: TextStyle(color: Color(0xFF1E40AF), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              taskTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Color(0xFFFEF3C7).withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Color(0xFFF59E0B).withOpacity(0.2)),
              ),
              child: Text(
                'Reason: $delayReason',
                style: TextStyle(fontSize: 13, color: Color(0xFF92400E), fontStyle: FontStyle.italic),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
            SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _completeTaskDirectly(taskId);
                    },
                    icon: Icon(Icons.check_circle, size: 20),
                    label: Text('Complete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await _updateIndividualStatus(taskId, 'hold');
                        Navigator.pop(context);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error updating task: $e'),
                            backgroundColor: Colors.red[400],
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.pause_circle, size: 20),
                    label: Text('On Hold'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  // Build assigned employees display
  Widget _buildAssignedEmployeesDisplay() {
    final assignedEmployees = widget.data['assignedEmployees'] as List<dynamic>? ?? [];

    if (assignedEmployees.isEmpty) {
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
              'Unassigned Task',
              style: TextStyle(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assigned Employees (${assignedEmployees.length})',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        SizedBox(height: 8),
        ...assignedEmployees.map((employee) {
          final employeeName = employee['employeeName'] ?? 'Unknown';
          final employeeStatus = employee['status'] ?? 'assigned';
          final actualStartDate = employee['actualStartDate']?.toString();
          final actualEndDate = employee['actualEndDate']?.toString();

          Color statusColor;
          Color statusBgColor;
          IconData statusIcon;
          String statusText;

          switch (employeeStatus) {
            case 'completed':
              statusColor = Color(0xFF059669);
              statusBgColor = Color(0xFFD1FAE5);
              statusIcon = Icons.check_circle;
              statusText = 'COMPLETED';
              break;
            case 'in_progress':
              statusColor = Color(0xFF3B82F6);
              statusBgColor = Color(0xFFDEEBFF);
              statusIcon = Icons.play_arrow;
              statusText = 'IN PROGRESS';
              break;
            case 'hold':
              statusColor = Color(0xFFF59E0B);
              statusBgColor = Color(0xFFFEF3C7);
              statusIcon = Icons.pause;
              statusText = 'ON HOLD';
              break;
            default:
              statusColor = Color(0xFF6B7280);
              statusBgColor = Color(0xFFF3F4F6);
              statusIcon = Icons.assignment;
              statusText = 'ASSIGNED';
          }

          return Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (actualStartDate != null || actualEndDate != null) ...[
                        SizedBox(height: 4),
                        Row(
                          children: [
                            if (actualStartDate != null) ...[
                              Icon(Icons.play_arrow, size: 12, color: Color(0xFF059669)),
                              SizedBox(width: 4),
                              Text(
                                DateFormat('MMM dd').format(DateTime.parse(actualStartDate)),
                                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                              ),
                            ],
                            if (actualStartDate != null && actualEndDate != null) ...[
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 10, color: Color(0xFF9CA3AF)),
                              SizedBox(width: 8),
                            ],
                            if (actualEndDate != null) ...[
                              Icon(Icons.check_circle, size: 12, color: Color(0xFF059669)),
                              SizedBox(width: 4),
                              Text(
                                DateFormat('MMM dd').format(DateTime.parse(actualEndDate)),
                                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.data['title']?.toString() ?? 'Untitled Task';
    final String description = widget.data['description']?.toString() ?? '';
    final String startDateStr = widget.data['startDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
    final String dueDateStr = widget.data['dueDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
    final String? assignedBy = widget.data['assignedBy']?.toString();
    final List<dynamic> assignedEmployees = widget.data['assignedEmployees'] as List<dynamic>? ?? [];
    final List<dynamic> delayReasons = widget.data['delayReasons'] as List<dynamic>? ?? [];

    // Get overall status
    final overallStatus = widget.data['overallStatus']?.toString() ??
        widget.data['status']?.toString() ??
        _calculateOverallStatus(assignedEmployees);

    DateTime startDate;
    DateTime dueDate;

    try {
      startDate = DateTime.parse(startDateStr);
      dueDate = DateTime.parse(dueDateStr);
    } catch (e) {
      startDate = DateTime.now();
      dueDate = DateTime.now();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

    final isOverdue = today.isAfter(dueDateOnly) && overallStatus != 'completed';
    final isDueToday = dueDateOnly.isAtSameMomentAs(today);

    // Get current user's status and data for employees
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
    String currentUserStatus = 'assigned';
    Map<String, dynamic>? currentUserData;
    bool needsDelayReason = false;

    if (currentUserId != null && !widget.isManager) {
      currentUserStatus = _getCurrentUserStatus(currentUserId);
      currentUserData = _getCurrentUserEmployeeData(currentUserId);
      needsDelayReason = _needsDelayReasonToday(widget.data);
    }

    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;
    String statusText;

    // Display status based on overall status or user status for employees
    final displayStatus = widget.isManager ? overallStatus : currentUserStatus;

    switch (displayStatus) {
      case 'completed':
        statusColor = Color(0xFF059669);
        statusBgColor = Color(0xFFD1FAE5);
        statusIcon = Icons.check_circle;
        statusText = 'COMPLETED';
        break;
      case 'in_progress':
        statusColor = Color(0xFF3B82F6);
        statusBgColor = Color(0xFFDEEBFF);
        statusIcon = Icons.play_arrow;
        statusText = 'IN PROGRESS';
        break;
      case 'hold':
        statusColor = Color(0xFFF59E0B);
        statusBgColor = Color(0xFFFEF3C7);
        statusIcon = Icons.pause;
        statusText = 'ON HOLD';
        break;
      case 'unassigned':
        statusColor = Color(0xFF9CA3AF);
        statusBgColor = Color(0xFFF3F4F6);
        statusIcon = Icons.person_off;
        statusText = 'UNASSIGNED';
        break;
      case 'assigned':
        if (isOverdue) {
          statusColor = Color(0xFFDC2626);
          statusBgColor = Color(0xFFFEE2E2);
          statusIcon = Icons.warning;
          statusText = 'OVERDUE';
        } else if (isDueToday) {
          statusColor = Color(0xFFF59E0B);
          statusBgColor = Color(0xFFFEF3C7);
          statusIcon = Icons.today;
          statusText = 'DUE TODAY';
        } else {
          statusColor = Color(0xFF6B7280);
          statusBgColor = Color(0xFFF3F4F6);
          statusIcon = Icons.assignment;
          statusText = 'ASSIGNED';
        }
        break;
      default:
        statusColor = Color(0xFF6B7280);
        statusBgColor = Color(0xFFF3F4F6);
        statusIcon = Icons.help_outline;
        statusText = 'UNKNOWN';
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
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.isManager
                              ? 'Overall Progress: ${assignedEmployees.length} employee(s)'
                              : 'Your Task Status',
                          style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Column(
                    children: [
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
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.isManager && widget.showEditButton) ...[
                        SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => EditTaskDialog(
                                    taskData: widget.data,
                                    taskId: widget.docId,
                                    onTaskUpdated: widget.onRefresh,
                                  ),
                                );
                              },
                              icon: Icon(Icons.edit, color: Color(0xFF3B82F6), size: 20),
                              tooltip: 'Edit Task',
                              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.all(4),
                            ),
                            IconButton(
                              onPressed: _showDeleteConfirmationDialog,
                              icon: Icon(Icons.delete, color: Color(0xFFDC2626), size: 20),
                              tooltip: 'Delete Task',
                              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.all(4),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              if (description.isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                ),
              ],

              SizedBox(height: 16),

              // Date information
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: startDate.isAtSameMomentAs(today) ? Color(0xFFE0F2FE) : Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: startDate.isAtSameMomentAs(today)
                            ? Border.all(color: Color(0xFF0EA5E9).withOpacity(0.3))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                  startDate.isAtSameMomentAs(today) ? Icons.today : Icons.play_arrow,
                                  size: 16,
                                  color: startDate.isAtSameMomentAs(today) ? Color(0xFF0EA5E9) : Color(0xFF059669)
                              ),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Start Date',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: startDate.isAtSameMomentAs(today) ? Color(0xFF0EA5E9) : Color(0xFF6B7280)
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            DateFormat('MMM dd, yyyy').format(startDate),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: startDate.isAtSameMomentAs(today) ? Color(0xFF0C4A6E) : Color(0xFF111827),
                            ),
                            overflow: TextOverflow.ellipsis,
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
                        color: isDueToday
                            ? Color(0xFFFEF3C7)
                            : (isOverdue ? Color(0xFFFEE2E2) : Color(0xFFF9FAFB)),
                        borderRadius: BorderRadius.circular(8),
                        border: isDueToday || isOverdue
                            ? Border.all(
                            color: isDueToday
                                ? Color(0xFFF59E0B).withOpacity(0.3)
                                : Color(0xFFDC2626).withOpacity(0.3)
                        )
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isDueToday ? Icons.today : (isOverdue ? Icons.warning : Icons.flag),
                                size: 16,
                                color: isDueToday ? Color(0xFFF59E0B) : (isOverdue ? Color(0xFFDC2626) : Color(0xFF6B7280)),
                              ),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Due Date',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isDueToday ? Color(0xFFF59E0B) : (isOverdue ? Color(0xFFDC2626) : Color(0xFF6B7280))
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            DateFormat('MMM dd, yyyy').format(dueDate),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDueToday ? Color(0xFF92400E) : (isOverdue ? Color(0xFFDC2626) : Color(0xFF111827)),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),

              // Show assigned employees for managers or individual submission for employees
              if (widget.isManager) ...[
                _buildAssignedEmployeesDisplay(),
              ] else if (currentUserData != null) ...[
                // Show individual employee's submission text if completed
                if (currentUserData!['submissionText'] != null) ...[
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
                            Text('Your Submission', style: TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          currentUserData!['submissionText'],
                          style: TextStyle(color: Color(0xFF065F46), fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                ],
              ],

              // Show delay reasons if overdue
              if (isOverdue && delayReasons.isNotEmpty) ...[
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
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
                      ),
                      if (delayReasons.last['submittedAt'] != null) ...[
                        SizedBox(height: 4),
                        Text(
                          'Submitted: ${DateFormat('MMM dd, yyyy').format((delayReasons.last['submittedAt'] as Timestamp).toDate())}',
                          style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12),
              ],

              // Show manager info for employees
              if (!widget.isManager && assignedBy != null) ...[
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(0xFFE2E8F0)),
                  ),
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(assignedBy).get(),
                    builder: (context, managerSnapshot) {
                      if (managerSnapshot.connectionState == ConnectionState.waiting) {
                        return Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B7280)),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Loading creator info...',
                              style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                            ),
                          ],
                        );
                      }

                      if (managerSnapshot.hasError || !managerSnapshot.hasData) {
                        return Row(
                          children: [
                            Icon(Icons.admin_panel_settings, size: 18, color: Color(0xFF6B7280)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Created by: Unknown Manager',
                                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      }

                      final managerData = managerSnapshot.data!.data() as Map<String, dynamic>?;
                      final managerName = managerData?['name']?.toString() ?? 'Unknown Manager';
                      final managerRole = managerData?['role']?.toString() ?? 'Manager';

                      return Row(
                        children: [
                          Icon(
                              managerRole == 'admin' ? Icons.admin_panel_settings : Icons.supervisor_account,
                              size: 18,
                              color: managerRole == 'admin' ? Color(0xFF7C3AED) : Color(0xFF059669)
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Created by: $managerName${managerRole == 'admin' ? ' (Admin)' : ''}',
                              style: TextStyle(
                                color: managerRole == 'admin' ? Color(0xFF7C3AED) : Color(0xFF059669),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(height: 16),
              ],

              // Employee action buttons
              if (!widget.isManager && currentUserId != null) ...[
                if (needsDelayReason && currentUserStatus != 'assigned') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showDelayReasonDialog(widget.docId, title),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber, size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Submit Today\'s Delay Reason',
                              style: TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (currentUserStatus == 'assigned') ...[
                  _buildSlideToStart(),
                ] else if (currentUserStatus == 'in_progress') ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showSubmissionDialog(widget.docId, title),
                          icon: Icon(Icons.check_circle, size: 18),
                          label: Text('Mark Complete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Color(0xFF10B981),
                            side: BorderSide(color: Color(0xFF10B981)),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showOnHoldDialog(widget.docId, title),
                          icon: Icon(Icons.pause_circle, size: 18),
                          label: Text('On Hold'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Color(0xFFF59E0B),
                            side: BorderSide(color: Color(0xFFF59E0B)),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (currentUserStatus == 'hold') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _updateIndividualStatus(widget.docId, 'in_progress'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Resume Task',
                              style: TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
}