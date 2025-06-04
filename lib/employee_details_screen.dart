import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart';
import 'home_screen.dart';

class EmployeeDetailsScreen extends StatefulWidget {
  @override
  _EmployeeDetailsScreenState createState() => _EmployeeDetailsScreenState();
}

class _EmployeeDetailsScreenState extends State<EmployeeDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController aadhaarController = TextEditingController();
  final TextEditingController panController = TextEditingController();
  final TextEditingController bloodGroupController = TextEditingController();
  final TextEditingController permanentAddressController = TextEditingController();
  final TextEditingController currentAddressController = TextEditingController();
  final TextEditingController alternateMobileController = TextEditingController();
  String _selectedRelation = 'father'; // Default relation
  bool _isLoading = false;

  // List of available relations
  final List<String> _relations = ['father', 'mother', 'brother', 'sister'];

  @override
  void dispose() {
    aadhaarController.dispose();
    panController.dispose();
    bloodGroupController.dispose();
    permanentAddressController.dispose();
    currentAddressController.dispose();
    alternateMobileController.dispose();
    super.dispose();
  }

  // Validation methods remain the same...
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

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon: Icon(prefixIcon, color: Colors.grey[600]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red[400]!),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red[400]!, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey[700],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUser!.uid;

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

      // Navigate to HomeScreen after successful submission
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Failed to save details: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          'Complete Your Profile',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Section
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_rounded,
                          size: 40,
                          color: theme.primaryColor,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Complete Your Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Please provide the following details to complete your profile setup',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Form Section
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Existing fields...
                      _buildInputLabel('Aadhaar Number'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: aadhaarController,
                        validator: _validateAadhaar,
                        keyboardType: TextInputType.number,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter 12-digit Aadhaar number',
                          prefixIcon: Icons.credit_card,
                        ),
                      ),

                      SizedBox(height: 20),

                      _buildInputLabel('PAN Number'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: panController,
                        validator: _validatePan,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter PAN number',
                          prefixIcon: Icons.credit_card,
                        ),
                      ),

                      SizedBox(height: 20),

                      _buildInputLabel('Blood Group'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: bloodGroupController,
                        validator: _validateBloodGroup,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter blood group (e.g., A+, O-)',
                          prefixIcon: Icons.medical_services,
                        ),
                      ),

                      SizedBox(height: 20),

                      _buildInputLabel('Permanent Address'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: permanentAddressController,
                        validator: (value) => _validateAddress(value, 'Permanent Address'),
                        maxLines: 3,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter permanent address',
                          prefixIcon: Icons.home,
                        ),
                      ),

                      SizedBox(height: 20),

                      _buildInputLabel('Current Address'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: currentAddressController,
                        validator: (value) => _validateAddress(value, 'Current Address'),
                        maxLines: 3,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter current address',
                          prefixIcon: Icons.location_city,
                        ),
                      ),

                      SizedBox(height: 20),

                      // Alternate Mobile Number with Relation
                      _buildInputLabel('Alternate Mobile Number'),
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
                              decoration: _buildInputDecoration(
                                hintText: 'Enter alternate mobile number',
                                prefixIcon: Icons.phone,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: Container(
                              height: 56, // Match height with TextFormField
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
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
                                  borderRadius: BorderRadius.circular(12),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedRelation = newValue!;
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
                ),

                SizedBox(height: 32),

                // Submit Button
                Container(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      disabledBackgroundColor: Colors.grey[300],
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Saving Details...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Save Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}