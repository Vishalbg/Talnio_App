import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'edit_manager_screen.dart';
import 'edit_employee_screen.dart';

class ManageUsersScreen extends StatefulWidget {
  @override
  _ManageUsersScreenState createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchActive = false;
  String _searchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (_isSearchActive) {
        _animationController.forward();
      } else {
        _animationController.reverse();
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

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
        title: _isSearchActive
            ? TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search by name or email...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          style: TextStyle(color: colorScheme.onSurface),
        )
            : Text(
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
          icon: Icon(_isSearchActive ? Icons.arrow_back : Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (_isSearchActive) {
              _toggleSearch();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          IconButton(
            icon: AnimatedIcon(
              icon: AnimatedIcons.search_ellipsis,
              progress: _animation,
              color: colorScheme.primary,
            ),
            onPressed: _toggleSearch,
            tooltip: _isSearchActive ? 'Close search' : 'Search users',
          ),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section - Only show when not searching
          if (!_isSearchActive)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAdmin ? 'All Users' : 'My Employees',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 8),
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

          // Search Results Info
          if (_isSearchActive && _searchQuery.isNotEmpty)
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              margin: EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Results for "$_searchQuery"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Loading employees...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final employeeIds = futureSnapshot.data!;
                if (employeeIds.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No employees assigned to you',
                    subtitle: 'You currently don\'t have any team members',
                    colorScheme: colorScheme,
                    theme: theme,
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 50,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 24),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
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
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
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
      return _buildEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Error loading users',
        subtitle: 'Please try again later',
        colorScheme: colorScheme,
        theme: theme,
      );
    }

    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No users found',
        subtitle: isAdmin ? 'No users have been added yet' : 'No employees found in your team',
        colorScheme: colorScheme,
        theme: theme,
      );
    }

    final users = snapshot.data!.docs
        .where((doc) {
      final userData = doc.data() as Map<String, dynamic>;
      final userId = userData['uid'];

      // Filter by search query if active
      if (_searchQuery.isNotEmpty) {
        final name = (userData['name'] ?? '').toString().toLowerCase();
        final email = (userData['email'] ?? '').toString().toLowerCase();
        if (!name.contains(_searchQuery) && !email.contains(_searchQuery)) {
          return false;
        }
      }

      return userId != currentUser?.uid;
    })
        .toList();

    if (users.isEmpty) {
      return _buildEmptyState(
        icon: _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.people_outline_rounded,
        title: _searchQuery.isNotEmpty ? 'No matching users found' : 'No other users found',
        subtitle: _searchQuery.isNotEmpty
            ? 'Try adjusting your search terms'
            : 'There are no other users in the system',
        colorScheme: colorScheme,
        theme: theme,
      );
    }

    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: ListView.separated(
        key: ValueKey<String>(_searchQuery),
        padding: EdgeInsets.all(24),
        itemCount: users.length,
        separatorBuilder: (context, index) => SizedBox(height: 16),
        itemBuilder: (context, index) {
          final userData = users[index].data() as Map<String, dynamic>;
          final userId = userData['uid'];
          final userName = userData['name'] ?? 'Unknown';
          final userRole = userData['role'] ?? 'Unknown';
          final userEmail = userData['email'] ?? '';
          final employeeType = userData['employeeType'];
          final officeLocationId = userData['officeLocationId'] is String && userData['officeLocationId'].isNotEmpty
              ? userData['officeLocationId']
              : null;

          // Add staggered animation for list items
          return AnimatedOpacity(
            opacity: 1.0,
            duration: Duration(milliseconds: 300 + (index * 50)),
            curve: Curves.easeInOut,
            child: AnimatedPadding(
              padding: EdgeInsets.only(top: 0),
              duration: Duration(milliseconds: 300 + (index * 50)),
              curve: Curves.easeInOut,
              child: _UserCard(
                userName: userName,
                userEmail: userEmail,
                userRole: userRole,
                employeeType: employeeType,
                isAdmin: isAdmin,
                authProvider: authProvider,
                userId: userId,
                userData: userData,
                officeLocationId: officeLocationId,
                colorScheme: colorScheme,
                theme: theme,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String userName;
  final String userEmail;
  final String userRole;
  final String? employeeType;
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
    this.employeeType,
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

  void _handleEdit(BuildContext context) {
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
    } else if ((isAdmin || authProvider.role == 'manager') && userRole == 'employee') {
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

  void _showUserInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 8,
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
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          _getRoleIcon(),
                          color: Colors.white,
                          size: 32,
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
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              userRole.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
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
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),
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

                        if (userData['mobileNumber'] != null || userData['alternateMobile'] != null)
                          _buildInfoSection(
                            'Contact Information',
                            Icons.contact_phone,
                            [
                              if (userData['mobileNumber'] != null)
                                _buildInfoRow('Mobile Number', userData['mobileNumber']),
                              if (userData['alternateMobile'] != null)
                                _buildInfoRow('Alternate Mobile', userData['alternateMobile']),
                              if (userData['alternateMobile'] != null)
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
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getRoleColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getRoleColor().withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: _getRoleColor(), size: 22),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
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
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_rounded,
                color: colorScheme.error,
                size: 28,
              ),
            ),
            SizedBox(width: 16),
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
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.error.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.error.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      color: colorScheme.error,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.error,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          userRole.toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.error,
                            letterSpacing: 0.5,
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
            SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.error,
                ),
                SizedBox(width: 8),
                Text(
                  'This action cannot be undone.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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

  @override
  Widget build(BuildContext context) {
    final roleColor = _getRoleColor();
    final employeeTypeColor = _getEmployeeTypeColor();
    final canEdit = (isAdmin && userRole == 'manager') ||
        ((isAdmin || authProvider.role == 'manager') && userRole == 'employee');

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showUserInfoDialog(context),
        borderRadius: BorderRadius.circular(20),
        splashColor: roleColor.withOpacity(0.1),
        highlightColor: roleColor.withOpacity(0.05),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar with gradient
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [roleColor.withOpacity(0.7), roleColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: roleColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getRoleIcon(),
                      color: Colors.white,
                      size: 30,
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
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (userEmail.isNotEmpty) ...[
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  userEmail,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Actions Menu Button
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    position: PopupMenuPosition.under,
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          _showUserInfoDialog(context);
                          break;
                        case 'edit':
                          _handleEdit(context);
                          break;
                        case 'delete':
                          _showDeleteDialog(context);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 20, color: colorScheme.primary),
                            SizedBox(width: 12),
                            Text('View Details'),
                          ],
                        ),
                      ),
                      if (canEdit)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 20, color: colorScheme.tertiary),
                              SizedBox(width: 12),
                              Text('Edit User'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_rounded, size: 20, color: colorScheme.error),
                            SizedBox(width: 12),
                            Text('Delete User', style: TextStyle(color: colorScheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Role and Employee Type Badges
              SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // Role Badge
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [roleColor.withOpacity(0.1), roleColor.withOpacity(0.2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: roleColor.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getRoleIcon(),
                          size: 16,
                          color: roleColor,
                        ),
                        SizedBox(width: 8),
                        Text(
                          userRole.toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: roleColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Employee Type Badge
                  if (employeeType != null && userRole == 'employee')
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: employeeTypeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: employeeTypeColor.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getEmployeeTypeIcon(),
                            color: employeeTypeColor,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            employeeType!.toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: employeeTypeColor,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
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
}