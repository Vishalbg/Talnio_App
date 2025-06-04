import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController aadhaarController = TextEditingController();
  final TextEditingController panController = TextEditingController();
  final TextEditingController bloodGroupController = TextEditingController();
  final TextEditingController permanentAddressController = TextEditingController();
  final TextEditingController currentAddressController = TextEditingController();
  final TextEditingController alternateMobileController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasChanges = false;
  bool _isLoadingData = true;
  Map<String, dynamic>? _userData;

  // Added for relationship functionality
  String _selectedRelation = 'father'; // Default relation
  final List<String> _relations = ['father', 'mother', 'brother', 'sister'];

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _setupListeners();
    _loadUserData();
  }

  void _initAnimations() {
    _slideController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutQuart));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideController.forward();
    _fadeController.forward();
  }

  void _setupListeners() {
    nameController.addListener(_checkForChanges);
    passwordController.addListener(_checkForChanges);
    aadhaarController.addListener(_checkForChanges);
    panController.addListener(_checkForChanges);
    bloodGroupController.addListener(_checkForChanges);
    permanentAddressController.addListener(_checkForChanges);
    currentAddressController.addListener(_checkForChanges);
    alternateMobileController.addListener(_checkForChanges);
  }

  Future<void> _loadUserData() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUser?.uid;

      if (userId != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        if (doc.exists) {
          _userData = doc.data() as Map<String, dynamic>?;
          if (_userData != null) {
            _populateFields();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _showSnackBar('Failed to load profile data', isError: true);
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  void _populateFields() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    nameController.text = authProvider.name ?? '';
    aadhaarController.text = _userData?['aadhaarNumber'] ?? '';
    panController.text = _userData?['panNumber'] ?? '';
    bloodGroupController.text = _userData?['bloodGroup'] ?? '';
    permanentAddressController.text = _userData?['permanentAddress'] ?? '';
    currentAddressController.text = _userData?['currentAddress'] ?? '';
    alternateMobileController.text = _userData?['alternateMobile'] ?? '';

    // Set the relation if it exists, otherwise use default
    setState(() {
      _selectedRelation = _userData?['alternateContactRelation'] ?? 'father';
    });
  }

  void _checkForChanges() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    bool hasNameChanged = nameController.text != (authProvider.name ?? '');
    bool hasPasswordChanged = passwordController.text.isNotEmpty;
    bool hasAadhaarChanged = aadhaarController.text != (_userData?['aadhaarNumber'] ?? '');
    bool hasPanChanged = panController.text != (_userData?['panNumber'] ?? '');
    bool hasBloodGroupChanged = bloodGroupController.text != (_userData?['bloodGroup'] ?? '');
    bool hasPermanentAddressChanged = permanentAddressController.text != (_userData?['permanentAddress'] ?? '');
    bool hasCurrentAddressChanged = currentAddressController.text != (_userData?['currentAddress'] ?? '');
    bool hasAlternateMobileChanged = alternateMobileController.text != (_userData?['alternateMobile'] ?? '');
    bool hasRelationChanged = _selectedRelation != (_userData?['alternateContactRelation'] ?? 'father');

    setState(() {
      _hasChanges = hasNameChanged || hasPasswordChanged || hasAadhaarChanged ||
          hasPanChanged || hasBloodGroupChanged || hasPermanentAddressChanged ||
          hasCurrentAddressChanged || hasAlternateMobileChanged || hasRelationChanged;
    });
  }

  // Validation methods
  String? _validateAadhaar(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Aadhaar number is required';
    }
    final aadhaarRegex = RegExp(r'^\d{12}$');
    if (!aadhaarRegex.hasMatch(value.trim())) {
      return 'Aadhaar number must be 12 digits';
    }
    return null;
  }

  String? _validatePan(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'PAN number is required';
    }
    final panRegex = RegExp(r'^[A-Z]{5}\d{4}[A-Z]{1}$');
    if (!panRegex.hasMatch(value.trim().toUpperCase())) {
      return 'Please enter a valid PAN number';
    }
    return null;
  }

  String? _validateBloodGroup(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Blood group is required';
    }
    final validBloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
    if (!validBloodGroups.contains(value.trim().toUpperCase())) {
      return 'Please enter a valid blood group (e.g., A+, B-, O+)';
    }
    return null;
  }

  String? _validateAddress(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (value.trim().length < 10) {
      return '$fieldName must be at least 10 characters';
    }
    return null;
  }

  String? _validateMobileNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Alternate mobile number is required';
    }
    final mobileRegex = RegExp(r'^[6-9]\d{9}$');
    if (!mobileRegex.hasMatch(value.trim())) {
      return 'Please enter a valid 10-digit mobile number';
    }
    return null;
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    nameController.dispose();
    passwordController.dispose();
    aadhaarController.dispose();
    panController.dispose();
    bloodGroupController.dispose();
    permanentAddressController.dispose();
    currentAddressController.dispose();
    alternateMobileController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUser?.uid;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Update basic profile
      await authProvider.updateProfile(
        nameController.text,
        passwordController.text.isEmpty ? null : passwordController.text,
        context,
      );

      // Update employee details with relation
      await authProvider.updateEmployeeDetails(
        userId: userId,
        aadhaarNumber: aadhaarController.text.trim(),
        panNumber: panController.text.trim().toUpperCase(),
        bloodGroup: bloodGroupController.text.trim().toUpperCase(),
        permanentAddress: permanentAddressController.text.trim(),
        currentAddress: currentAddressController.text.trim(),
        alternateMobile: alternateMobileController.text.trim(),
        alternateContactRelation: _selectedRelation, // Pass the selected relation
        context: context,
      );

      _showSnackBar('Profile updated successfully!', isError: false);
      await Future.delayed(Duration(milliseconds: 500));
      Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Failed to update profile: $e', isError: true);
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[800]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Icon(
              Icons.person,
              size: 50,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'My Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            'Manage your personal information',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      margin: EdgeInsets.only(top: 24, bottom: 16),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue[600], size: 20),
          ),
          SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool isPassword = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: validator,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Container(
            margin: EdgeInsets.all(8),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue[600], size: 20),
          ),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              obscureText ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey[600],
            ),
            onPressed: () {
              setState(() => _obscurePassword = !_obscurePassword);
            },
          )
              : null,
          labelStyle: TextStyle(color: Colors.grey[600]),
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.blue[600]!, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red[600]!, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red[600]!, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildAlternateMobileWithRelation() {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alternate Mobile Number',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: alternateMobileController,
                  validator: _validateMobileNumber,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    prefixIcon: Container(
                      margin: EdgeInsets.all(8),
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.phone, color: Colors.blue[600], size: 20),
                    ),
                    labelText: 'Mobile Number',
                    labelStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.blue[600]!, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.red[600]!, width: 2),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.red[600]!, width: 2),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRelation,
                      icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                      elevation: 16,
                      style: TextStyle(color: Colors.grey[800], fontSize: 16),
                      isExpanded: true,
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      borderRadius: BorderRadius.circular(16),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedRelation = newValue!;
                          _checkForChanges();
                        });
                      },
                      items: _relations.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value.substring(0, 1).toUpperCase() + value.substring(1),
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'Relation of alternate contact',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateButton() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading || !_hasChanges ? null : _updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          elevation: _hasChanges ? 8 : 2,
          shadowColor: Colors.blue.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
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
            Text('Updating...', style: TextStyle(fontSize: 16)),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.save, size: 24),
            SizedBox(width: 12),
            Text(
              'Update Profile',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return Container(
      width: double.infinity,
      height: 60,
      margin: EdgeInsets.only(top: 12),
      child: OutlinedButton(
        onPressed: _isLoading ? null : () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[400]!, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: Colors.grey[600]),
            SizedBox(width: 12),
            Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      margin: EdgeInsets.only(bottom: 24),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[200]!, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[600],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.info_outline, color: Colors.white, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                Text(
                  'Update your personal and professional details. Leave password field empty to keep current password.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue[600]),
              SizedBox(height: 16),
              Text(
                'Loading profile data...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header Section
          FadeTransition(
            opacity: _fadeAnimation,
            child: _buildProfileHeader(),
          ),

          // Form Section
          Expanded(
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8),

                      // Info Card
                      _buildInfoCard(),

                      // Basic Information Section
                      _buildSectionHeader('Basic Information', Icons.person_outline),

                      _buildCustomTextField(
                        controller: nameController,
                        label: 'Full Name',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          if (value.trim().length < 2) {
                            return 'Name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),

                      _buildCustomTextField(
                        controller: passwordController,
                        label: 'New Password (Optional)',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        isPassword: true,
                        validator: (value) {
                          if (value != null && value.isNotEmpty && value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),

                      // Identity Information Section
                      _buildSectionHeader('Identity Information', Icons.credit_card),

                      _buildCustomTextField(
                        controller: aadhaarController,
                        label: 'Aadhaar Number',
                        icon: Icons.credit_card,
                        keyboardType: TextInputType.number,
                        validator: _validateAadhaar,
                      ),

                      _buildCustomTextField(
                        controller: panController,
                        label: 'PAN Number',
                        icon: Icons.credit_card,
                        textCapitalization: TextCapitalization.characters,
                        validator: _validatePan,
                      ),

                      _buildCustomTextField(
                        controller: bloodGroupController,
                        label: 'Blood Group',
                        icon: Icons.medical_services,
                        validator: _validateBloodGroup,
                      ),

                      // Contact Information Section
                      _buildSectionHeader('Contact Information', Icons.contact_phone),

                      // Updated alternate mobile field with relationship
                      _buildAlternateMobileWithRelation(),

                      // Address Information Section
                      _buildSectionHeader('Address Information', Icons.location_on),

                      _buildCustomTextField(
                        controller: permanentAddressController,
                        label: 'Permanent Address',
                        icon: Icons.home,
                        maxLines: 3,
                        validator: (value) => _validateAddress(value, 'Permanent Address'),
                      ),

                      _buildCustomTextField(
                        controller: currentAddressController,
                        label: 'Current Address',
                        icon: Icons.location_city,
                        maxLines: 3,
                        validator: (value) => _validateAddress(value, 'Current Address'),
                      ),

                      SizedBox(height: 20),

                      // Update Button
                      _buildUpdateButton(),

                      // Cancel Button
                      _buildCancelButton(),

                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}