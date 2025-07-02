import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'attendance_screen.dart';
import 'attendance_report_screen.dart';
import 'task_screen.dart';
import 'report_screen.dart';
import 'add_employee_screen.dart';
import 'add_manager_screen.dart';
import 'manage_users_screen.dart';
import 'edit_manager_screen.dart';
import 'edit_employee_screen.dart';
import 'profile_screen.dart';
import 'checkout_approval_screen.dart';
import 'LeaveRequestScreen.dart';
import 'LeaveApprovalScreen.dart';
import 'employee_details_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoggingOut = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.role;

    if (role == null) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue.shade50, Colors.white],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Loading...',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade800,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getGreeting(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              role == 'admin'
                  ? 'Admin Dashboard'
                  : role == 'manager'
                  ? 'Manager Dashboard'
                  : 'Employee Dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        actions: [
          // Chat Icon
          Container(
            margin: EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.chat_bubble_outline, size: 20, color: Colors.blue.shade600),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen()),
              ),
              tooltip: 'Team Chat',
            ),
          ),
          // Profile Icon
          Container(
            margin: EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_circle, size: 20),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen()),
              ),
            ),
          ),
          // Logout Icon
          Container(
            margin: EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoggingOut
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade600),
                  ),
                )
                    : Icon(Icons.logout, size: 20, color: Colors.red.shade600),
              ),
              onPressed: _isLoggingOut ? null : () => _showLogoutDialog(context, authProvider),
            ),
          ),
        ],
      ),
      body: role == 'admin'
          ? AdminDashboard()
          : role == 'manager'
          ? ManagerDashboard()
          : EmployeeDashboard(),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 16) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      barrierDismissible: !_isLoggingOut, // Prevent dismissing while logging out
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Sign Out'),
              content: Text('Are you sure you want to sign out?'),
              actions: [
                TextButton(
                  onPressed: _isLoggingOut ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isLoggingOut ? null : () async {
                    setDialogState(() {
                      _isLoggingOut = true;
                    });
                    setState(() {
                      _isLoggingOut = true;
                    });

                    try {
                      await authProvider.signOut();
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e) {
                      if (mounted) {
                        setDialogState(() {
                          _isLoggingOut = false;
                        });
                        setState(() {
                          _isLoggingOut = false;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Logout failed. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoggingOut
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
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
                      Text('Signing Out...'),
                    ],
                  )
                      : Text('Sign Out'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Fixed AdminDashboard with proper constraints
class AdminDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 40, // Account for padding
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(),
                SizedBox(height: 24),
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                SizedBox(height: 16),
                _buildActionGrid(context, [
                  _ActionItem(
                    icon: Icons.chat_bubble_outline,
                    title: 'Team Chat',
                    subtitle: 'Communicate with your team',
                    color: Colors.blue,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.person_add_alt_1,
                    title: 'Add Manager',
                    subtitle: 'Create new manager account',
                    color: Colors.purple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddManagerScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.group,
                    title: 'Manage Users',
                    subtitle: 'Edit user permissions',
                    color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageUsersScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.analytics,
                    title: 'Attendance Reports',
                    subtitle: 'View check-in/out analytics',
                    color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceReportScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.assignment,
                    title: 'Daily Reports',
                    subtitle: 'Review daily summaries',
                    color: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen())),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200,
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage your organization efficiently',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.admin_panel_settings,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

// Fixed ManagerDashboard with proper constraints
class ManagerDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(),
                SizedBox(height: 24),
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                SizedBox(height: 16),
                _buildActionGrid(context, [
                  _ActionItem(
                    icon: Icons.chat_bubble_outline,
                    title: 'Team Chat',
                    subtitle: 'Chat with your team',
                    color: Colors.blue,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.access_time,
                    title: 'Check-In/Out',
                    subtitle: 'Mark your attendance',
                    color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.person_add,
                    title: 'Add Employee',
                    subtitle: 'Register new employee',
                    color: Colors.purple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddEmployeeScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.group,
                    title: 'Manage Team',
                    subtitle: 'Edit employee details',
                    color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageUsersScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.task_alt,
                    title: 'Assign Tasks',
                    subtitle: 'Create and manage tasks',
                    color: Colors.indigo,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskScreen(isManager: true))),
                  ),
                  _ActionItem(
                    icon: Icons.analytics,
                    title: 'Attendance Reports',
                    subtitle: 'View team check-in/out',
                    color: Colors.teal,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceReportScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.assignment,
                    title: 'Daily Reports',
                    subtitle: 'Review daily summaries',
                    color: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.check_circle,
                    title: 'Checkout approval',
                    subtitle: 'View team check-out requests',
                    color: Colors.cyan,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutApprovalScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.approval,
                    title: 'Leave Approvals',
                    subtitle: 'View team leave requests',
                    color: Colors.amber,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveApprovalScreen())),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade600, Colors.purple.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.shade200,
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Lead your team to success',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.supervisor_account,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

// Fixed EmployeeDashboard with proper constraints
class EmployeeDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(),
                SizedBox(height: 24),
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                SizedBox(height: 16),
                _buildActionGrid(context, [
                  _ActionItem(
                    icon: Icons.chat_bubble_outline,
                    title: 'Team Chat',
                    subtitle: 'Chat with your team',
                    color: Colors.blue,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.access_time,
                    title: 'Check-In/Out',
                    subtitle: 'Mark your attendance',
                    color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.task_alt,
                    title: 'My Tasks',
                    subtitle: 'View assigned tasks',
                    color: Colors.purple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskScreen(isManager: false))),
                  ),
                  _ActionItem(
                    icon: Icons.assignment,
                    title: 'Daily Report',
                    subtitle: 'Submit your daily report',
                    color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen())),
                  ),
                  _ActionItem(
                    icon: Icons.event,
                    title: 'Manage Leaves',
                    subtitle: 'Manage Absents',
                    color: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveRequestScreen())),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade600, Colors.teal.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.shade200,
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Have a productive day ahead',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.person,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _ActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

// Fixed action grid with proper responsive layout
Widget _buildActionGrid(BuildContext context, List<_ActionItem> items) {
  return LayoutBuilder(
    builder: (context, constraints) {
      // Calculate cross axis count based on screen width
      int crossAxisCount = 2;
      if (constraints.maxWidth > 600) {
        crossAxisCount = 3;
      }
      if (constraints.maxWidth > 900) {
        crossAxisCount = 4;
      }

      // Calculate aspect ratio to prevent overflow
      double aspectRatio = 0.85;
      if (constraints.maxWidth < 400) {
        aspectRatio = 0.75; // Make cards taller on small screens
      }

      return GridView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: aspectRatio,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildActionCard(item);
        },
      );
    },
  );
}

Widget _buildActionCard(_ActionItem item) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              offset: Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(16), // Reduced padding to prevent overflow
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(12), // Reduced padding
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.icon,
                  color: item.color,
                  size: 28, // Slightly smaller icon
                ),
              ),
              SizedBox(height: 8), // Reduced spacing
              Flexible(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 14, // Slightly smaller font
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 4),
              Flexible(
                child: Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 11, // Smaller subtitle
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}