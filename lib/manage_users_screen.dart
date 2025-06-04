import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'edit_manager_screen.dart';
import 'edit_employee_screen.dart';

class ManageUsersScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = authProvider.role == 'admin';
    final isManager = authProvider.role == 'manager';
    final currentUser = fa.FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isAdmin && !isManager) {
      return Scaffold(
        body: Center(
          child: Text('Access denied: Only admins and managers can manage users'),
        ),
      );
    }

    if (!isAdmin && currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text('No authenticated user. Please sign in again.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          'Manage Users',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 4,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdmin ? 'All Users' : 'My Employees',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  isAdmin
                      ? 'Manage all users in your organization'
                      : 'Manage employees in your team',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Users List
          Expanded(
            child: isAdmin
                ? StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                return _buildUsersList(snapshot, currentUser, isAdmin, authProvider, colorScheme, theme);
              },
            )
                : FutureBuilder<List<String>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .where('managerId', isEqualTo: currentUser!.uid)
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
                        Icon(
                          Icons.people_outline_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No employees assigned to you',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('uid', whereIn: employeeIds)
                      .snapshots(),
                  builder: (context, snapshot) {
                    return _buildUsersList(snapshot, currentUser, isAdmin, authProvider, colorScheme, theme);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList(
      AsyncSnapshot<QuerySnapshot> snapshot,
      fa.User? currentUser,
      bool isAdmin,
      AuthProvider authProvider,
      ColorScheme colorScheme,
      ThemeData theme,
      ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              color: colorScheme.primary,
            ),
            SizedBox(height: 16),
            Text(
              'Loading users...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            SizedBox(height: 16),
            Text(
              'Error loading users',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please try again later',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
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
            Icon(
              Icons.people_outline_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 16),
            Text(
              'No users found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 8),
            Text(
              isAdmin ? 'No users have been added yet' : 'No employees found in your team',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final users = snapshot.data!.docs
        .where((doc) {
      final userData = doc.data() as Map<String, dynamic>;
      final userId = userData['uid'];
      return userId != currentUser?.uid;
    })
        .toList();

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 16),
            Text(
              'No other users found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(24),
      itemCount: users.length,
      separatorBuilder: (context, index) => SizedBox(height: 12),
      itemBuilder: (context, index) {
        final userData = users[index].data() as Map<String, dynamic>;
        final userId = userData['uid'];
        final userName = userData['name'] ?? 'Unknown';
        final userRole = userData['role'] ?? 'Unknown';
        final userEmail = userData['email'] ?? '';
        final employeeType = userData['employeeType']; // Get employee type
        final officeLocationId = userData['officeLocationId'] is String && userData['officeLocationId'].isNotEmpty
            ? userData['officeLocationId']
            : null;

        return _UserCard(
          userName: userName,
          userEmail: userEmail,
          userRole: userRole,
          employeeType: employeeType, // Pass employee type
          isAdmin: isAdmin,
          authProvider: authProvider,
          userId: userId,
          userData: userData,
          officeLocationId: officeLocationId,
          colorScheme: colorScheme,
          theme: theme,
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  final String userName;
  final String userEmail;
  final String userRole;
  final String? employeeType; // Add employee type
  final bool isAdmin;
  final AuthProvider authProvider;
  final String userId;
  final Map<String, dynamic> userData;
  final String? officeLocationId;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _UserCard({
    required this.userName,
    required this.userEmail,
    required this.userRole,
    this.employeeType, // Add employee type
    required this.isAdmin,
    required this.authProvider,
    required this.userId,
    required this.userData,
    required this.officeLocationId,
    required this.colorScheme,
    required this.theme,
  });

  Color _getRoleColor() {
    switch (userRole.toLowerCase()) {
      case 'admin':
        return colorScheme.error;
      case 'manager':
        return colorScheme.tertiary;
      case 'employee':
        return colorScheme.primary;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  Color _getEmployeeTypeColor() {
    if (employeeType == null) return Colors.grey;
    switch (employeeType!.toLowerCase()) {
      case 'employee':
        return Colors.blue;
      case 'intern':
        return Colors.green;
      case 'freelancer':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon() {
    switch (userRole.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'manager':
        return Icons.supervisor_account_rounded;
      case 'employee':
        return Icons.person_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  IconData _getEmployeeTypeIcon() {
    if (employeeType == null) return Icons.person_rounded;
    switch (employeeType!.toLowerCase()) {
      case 'employee':
        return Icons.person_rounded;
      case 'intern':
        return Icons.school_rounded;
      case 'freelancer':
        return Icons.work_outline_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  String _getRelationshipDisplayText(String? relation) {
    if (relation == null || relation.isEmpty) return 'Not specified';
    return relation.substring(0, 1).toUpperCase() + relation.substring(1);
  }

  void _showUserInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_getRoleColor().withOpacity(0.8), _getRoleColor()],
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
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _getRoleIcon(),
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              userRole.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (employeeType != null) // Show employee type if available
                              Text(
                                employeeType!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoSection(
                          'Basic Information',
                          Icons.person_outline,
                          [
                            _buildInfoRow('Name', userName),
                            _buildInfoRow('Email', userEmail.isNotEmpty ? userEmail : 'Not provided'),
                            _buildInfoRow('Role', userRole),
                            if (employeeType != null)
                              _buildInfoRow('Employee Type', employeeType!),
                          ],
                        ),

                        if (userData['aadhaarNumber'] != null || userData['panNumber'] != null || userData['bloodGroup'] != null)
                          _buildInfoSection(
                            'Identity Information',
                            Icons.credit_card,
                            [
                              if (userData['aadhaarNumber'] != null)
                                _buildInfoRow('Aadhaar Number', userData['aadhaarNumber']),
                              if (userData['panNumber'] != null)
                                _buildInfoRow('PAN Number', userData['panNumber']),
                              if (userData['bloodGroup'] != null)
                                _buildInfoRow('Blood Group', userData['bloodGroup']),
                            ],
                          ),

                        // Updated Contact Information Section with Relationship
                        if (userData['alternateMobile'] != null)
                          _buildInfoSection(
                            'Contact Information',
                            Icons.contact_phone,
                            [
                              _buildInfoRow('Alternate Mobile', userData['alternateMobile']),
                              _buildInfoRow(
                                  'Relationship',
                                  _getRelationshipDisplayText(userData['alternateContactRelation'])
                              ),
                            ],
                          ),

                        if (userData['permanentAddress'] != null || userData['currentAddress'] != null)
                          _buildInfoSection(
                            'Address Information',
                            Icons.location_on,
                            [
                              if (userData['permanentAddress'] != null)
                                _buildInfoRow('Permanent Address', userData['permanentAddress']),
                              if (userData['currentAddress'] != null)
                                _buildInfoRow('Current Address', userData['currentAddress']),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoSection(String title, IconData icon, List<Widget> children) {
    return Container(
      margin: EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getRoleColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _getRoleColor(), size: 20),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _getRoleColor();
    final employeeTypeColor = _getEmployeeTypeColor();
    final canEdit = (isAdmin && userRole == 'manager') ||
        ((isAdmin || authProvider.role == 'manager') && userRole == 'employee');

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getRoleIcon(),
                    color: roleColor,
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),

                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (userEmail.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          userEmail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Info Icon Button
                IconButton(
                  onPressed: () => _showUserInfoDialog(context),
                  icon: Icon(
                    Icons.info_outline_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                    padding: EdgeInsets.all(8),
                  ),
                  tooltip: 'View Details',
                ),

                SizedBox(width: 8),

                // Role Badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: roleColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    userRole.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: roleColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),

            // Employee Type Badge (if available)
            if (employeeType != null && userRole == 'employee') ...[
              SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _getEmployeeTypeIcon(),
                    color: employeeTypeColor,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: employeeTypeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: employeeTypeColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      employeeType!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: employeeTypeColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Actions
            SizedBox(height: 16),
            Row(
              children: [
                // Edit Button
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: canEdit
                        ? () {
                      if (isAdmin && userRole == 'manager') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditManagerScreen(
                              userId: userId,
                              currentOfficeLocationId: officeLocationId,
                            ),
                          ),
                        );
                      } else if ((isAdmin || authProvider.role == 'manager') &&
                          userRole == 'employee') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditEmployeeScreen(
                              userId: userId,
                              currentOfficeLocationId: officeLocationId,
                            ),
                          ),
                        );
                      }
                    }
                        : null,
                    icon: Icon(Icons.edit_rounded, size: 18),
                    label: Text('Edit'),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                SizedBox(width: 12),

                // Delete Button
                FilledButton.icon(
                  onPressed: () => _showDeleteDialog(context),
                  icon: Icon(Icons.delete_rounded, size: 18),
                  label: Text('Delete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_rounded,
              color: colorScheme.error,
              size: 28,
            ),
            SizedBox(width: 12),
            Text(
              'Delete User',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this user?',
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.error.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    color: colorScheme.error,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.error,
                          ),
                        ),
                        Text(
                          userRole.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                        if (employeeType != null)
                          Text(
                            employeeType!.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.error.withOpacity(0.8),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'This action cannot be undone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      await authProvider.deleteUser(userId, context);
    }
  }
}