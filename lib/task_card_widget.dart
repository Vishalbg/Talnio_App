import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'edit_task_dialog.dart'; // Import for edit dialog

class TaskCardWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isManager;
  final String? employeeName;
  final VoidCallback onRefresh;
  final bool showEditButton;

  const TaskCardWidget({
    Key? key,
    required this.data,
    required this.docId,
    required this.isManager,
    this.employeeName,
    required this.onRefresh,
    this.showEditButton = true, // Default to true, but can be disabled for completed tasks
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

    if (widget.data['status'] == 'assigned' && !widget.isManager) {
      _pulseController.repeat(reverse: true);
    }

    _checkIfNeedsQuickActionsAfterStart();
  }

  void _checkIfNeedsQuickActionsAfterStart() {
    try {
      final String dueDateStr = widget.data['dueDate']?.toString() ?? '';

      if (dueDateStr.isNotEmpty) {
        final dueDate = DateTime.parse(dueDateStr);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

        if (dueDateOnly.isAtSameMomentAs(today) && widget.data['status'] == 'assigned') {
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

    if (today.isAfter(dueDateOnly) && taskData['status'] != 'completed') {
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

  // Add delete confirmation dialog
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
              // Check if still mounted before proceeding
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

  // Add delete task method with mounted check
  Future<void> _deleteTask() async {
    try {
      await FirebaseFirestore.instance.collection('tasks').doc(widget.docId).delete();

      // Check if the widget is still mounted before accessing context
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
      // Check if the widget is still mounted before accessing context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting task: $e'),
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

      await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
        'status': 'in_progress',
        'actualStartDate': DateTime.now().toIso8601String().split('T')[0],
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.rocket_launch, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Task started successfully! 🚀')),
            ],
          ),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      widget.onRefresh();

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
    try {
      await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
        'status': 'completed',
        'submittedAt': FieldValue.serverTimestamp(),
        'actualEndDate': DateTime.now().toIso8601String().split('T')[0],
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.celebration, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Task completed successfully! 🎉')),
            ],
          ),
          backgroundColor: Colors.green[500],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing task: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
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
                  final now = DateTime.now();
                  final formattedDate = DateFormat('yyyy-MM-dd').format(now);

                  await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
                    'status': 'hold',
                    'delayReasons': FieldValue.arrayUnion([
                      {
                        'reason': holdReasonController.text.trim(),
                        'submittedAt': Timestamp.fromDate(now),
                        'date': formattedDate,
                        'type': 'hold',
                      }
                    ]),
                    'lastDelayReasonDate': formattedDate,
                  });

                  Navigator.pop(context);

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.pause_circle, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(child: Text('Task put on hold successfully')),
                        ],
                      ),
                      backgroundColor: Color(0xFFF59E0B),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                  widget.onRefresh();
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
                  Map<String, dynamic> updateData = {
                    'status': 'completed',
                    'submittedAt': FieldValue.serverTimestamp(),
                    'actualEndDate': DateTime.now().toIso8601String().split('T')[0],
                  };

                  if (submissionController.text.trim().isNotEmpty) {
                    updateData['submissionText'] = submissionController.text.trim();
                  }

                  await FirebaseFirestore.instance.collection('tasks').doc(taskId).update(updateData);

                  Navigator.pop(context);

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.celebration, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(child: Text('Task completed successfully! 🎉')),
                        ],
                      ),
                      backgroundColor: Colors.green[500],
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                  widget.onRefresh();
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
                  final now = DateTime.now();
                  final formattedDate = DateFormat('yyyy-MM-dd').format(now);
                  final delayReason = delayReasonController.text.trim();

                  await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
                    'delayReasons': FieldValue.arrayUnion([
                      {
                        'reason': delayReason,
                        'submittedAt': Timestamp.fromDate(now),
                        'date': formattedDate,
                        'type': 'delay',
                      }
                    ]),
                    'lastDelayReasonDate': formattedDate,
                  });

                  Navigator.pop(context);
                  _showDelayReasonOptionsDialog(taskId, taskTitle, delayReason);

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
                        await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
                          'status': 'hold',
                        });

                        Navigator.pop(context);

                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.pause_circle, color: Colors.white),
                                SizedBox(width: 8),
                                Expanded(child: Text('Task put on hold')),
                              ],
                            ),
                            backgroundColor: Color(0xFFF59E0B),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                        widget.onRefresh();
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

  @override
  Widget build(BuildContext context) {
    final String title = widget.data['title']?.toString() ?? 'Untitled Task';
    final String description = widget.data['description']?.toString() ?? '';
    final String startDateStr = widget.data['startDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
    final String dueDateStr = widget.data['dueDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
    final String? actualStartDateStr = widget.data['actualStartDate']?.toString();
    final String? actualEndDateStr = widget.data['actualEndDate']?.toString();
    final String status = widget.data['status']?.toString() ?? 'assigned';
    final String? submissionText = widget.data['submissionText']?.toString();
    final List<dynamic> delayReasons = widget.data['delayReasons'] as List<dynamic>? ?? [];
    final String? assignedBy = widget.data['assignedBy']?.toString(); // Get the manager ID

    DateTime startDate;
    DateTime dueDate;
    DateTime? actualStartDate;
    DateTime? actualEndDate;

    try {
      startDate = DateTime.parse(startDateStr);
      dueDate = DateTime.parse(dueDateStr);
      if (actualStartDateStr != null) actualStartDate = DateTime.parse(actualStartDateStr);
      if (actualEndDateStr != null) actualEndDate = DateTime.parse(actualEndDateStr);
    } catch (e) {
      startDate = DateTime.now();
      dueDate = DateTime.now();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

    final isOverdue = today.isAfter(dueDateOnly) && status != 'completed';
    final isDueToday = dueDateOnly.isAtSameMomentAs(today);
    final needsDelayReason = _needsDelayReasonToday(widget.data);

    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
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

                        // Show employee name for managers only
                        if (widget.isManager && widget.employeeName != null) ...[
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person, size: 16, color: Color(0xFF6B7280)),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Assigned to: ${widget.employeeName}',
                                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ] else if (widget.isManager && status == 'unassigned') ...[
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person_off, size: 16, color: Color(0xFF9CA3AF)),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Unassigned Task',
                                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, fontStyle: FontStyle.italic),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
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
                      // Edit and Delete buttons for managers (only if showEditButton is true)
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

              Column(
                children: [
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
                                      'Planned Start',
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
                              if (startDate.isAtSameMomentAs(today)) ...[
                                SizedBox(height: 2),
                                Text(
                                  'Today',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF0EA5E9),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
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
                                      'Planned End',
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
                              if (isDueToday) ...[
                                SizedBox(height: 2),
                                Text(
                                  'Today',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFF59E0B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ] else if (isOverdue) ...[
                                SizedBox(height: 2),
                                Text(
                                  'Overdue',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: actualStartDate != null ? Color(0xFFE0F2FE) : Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(8),
                            border: actualStartDate != null
                                ? Border.all(color: Color(0xFF0EA5E9).withOpacity(0.3))
                                : Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                      Icons.schedule,
                                      size: 16,
                                      color: actualStartDate != null ? Color(0xFF0EA5E9) : Color(0xFF6B7280)
                                  ),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Actual Start',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: actualStartDate != null ? Color(0xFF0EA5E9) : Color(0xFF6B7280)
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                actualStartDate != null
                                    ? DateFormat('MMM dd, yyyy').format(actualStartDate)
                                    : 'Not started',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: actualStartDate != null ? Color(0xFF0C4A6E) : Color(0xFF6B7280),
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
                            color: actualEndDate != null ? Color(0xFFD1FAE5) : Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(8),
                            border: actualEndDate != null
                                ? Border.all(color: Color(0xFF059669).withOpacity(0.3))
                                : Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: actualEndDate != null ? Color(0xFF059669) : Color(0xFF6B7280)
                                  ),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Actual End',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: actualEndDate != null ? Color(0xFF059669) : Color(0xFF6B7280)
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                actualEndDate != null
                                    ? DateFormat('MMM dd, yyyy').format(actualEndDate)
                                    : 'Not completed',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: actualEndDate != null ? Color(0xFF065F46) : Color(0xFF6B7280),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
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
              ],

              // Show manager name for employees - moved to bottom after submission and delay reasons
              if (!widget.isManager && assignedBy != null) ...[
                SizedBox(height: 16),
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
              ],

              // Enhanced action buttons for employees
              if (!widget.isManager) ...[
                SizedBox(height: 16),
                if (needsDelayReason && status != 'assigned') ...[
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
                ] else if (status == 'assigned') ...[
                  _buildSlideToStart(),
                ] else if (status == 'in_progress') ...[
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
                ] else if (status == 'hold') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _startTask(widget.docId),
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
