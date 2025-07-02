import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart';

class AddEmployeeScreen extends StatefulWidget {
  @override
  _AddEmployeeScreenState createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? selectedOfficeLocationId;
  String? selectedEmployeeType; // Changed to nullable with no default
  String? selectedDeveloperType; // Changed to nullable with no default
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _showEmployeeTypeDescription = false;
  bool _showDeveloperTypeDescription = false;

  // Employee type options
  final List<Map<String, dynamic>> employeeTypes = [
    {
      'value': 'employee',
      'label': 'Employee',
      'icon': Icons.person_rounded,
      'description': 'Full-time permanent employee'
    },
    {
      'value': 'intern',
      'label': 'Intern',
      'icon': Icons.school_rounded,
      'description': 'Temporary intern or trainee'
    },
    {
      'value': 'freelancer',
      'label': 'Freelancer',
      'icon': Icons.work_outline_rounded,
      'description': 'Contract-based freelancer'
    },
  ];

  // Developer type options
  final List<Map<String, dynamic>> developerTypes = [
    {
      'value': 'full_stack',
      'label': 'Full Stack Developer',
      'icon': Icons.code_rounded,
      'color': Colors.purple,
      'description': 'Frontend and backend development'
    },
    {
      'value': 'frontend',
      'label': 'Frontend Developer',
      'icon': Icons.desktop_windows_rounded,
      'color': Colors.blue,
      'description': 'User interface and experience'
    },
    {
      'value': 'backend',
      'label': 'Backend Developer',
      'icon': Icons.storage_rounded,
      'color': Colors.green,
      'description': 'Server-side and database'
    },
    {
      'value': 'ui_ux',
      'label': 'UI/UX Designer',
      'icon': Icons.design_services_rounded,
      'color': Colors.orange,
      'description': 'Design and user experience'
    },
  ];

  @override
  void dispose() {
    emailController.dispose();
    nameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Color _getEmployeeTypeColor(String? type) {
    switch (type) {
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

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          'Add New Employee',
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
                          Icons.person_add_rounded,
                          size: 40,
                          color: theme.primaryColor,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Employee Information',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fill in the details below to add a new team member',
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
                      // Name Field
                      _buildInputLabel('Full Name'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        validator: _validateName,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter employee\'s full name',
                          prefixIcon: Icons.person_outline_rounded,
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),

                      SizedBox(height: 20),

                      // Email Field
                      _buildInputLabel('Email Address'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: emailController,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _buildInputDecoration(
                          hintText: 'Enter employee\'s email',
                          prefixIcon: Icons.email_outlined,
                        ),
                      ),

                      SizedBox(height: 20),

                      // Password Field
                      _buildInputLabel('Temporary Password'),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: passwordController,
                        validator: _validatePassword,
                        obscureText: _obscurePassword,
                        decoration: _buildInputDecoration(
                          hintText: 'Create a temporary password',
                          prefixIcon: Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),

                      SizedBox(height: 20),

                      // Employee Type Field - Modified to show "Please select"
                      _buildInputLabel('Employee Type'),
                      SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            decoration: _buildInputDecoration(
                              hintText: 'Select employee type',
                              prefixIcon: Icons.work_rounded,
                            ),
                            value: selectedEmployeeType,
                            isExpanded: true,
                            items: [
                              // Add "Please select" option
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'Please select',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                              ...employeeTypes.map((type) {
                                return DropdownMenuItem<String>(
                                  value: type['value'],
                                  child: Row(
                                    children: [
                                      Icon(
                                        type['icon'],
                                        color: _getEmployeeTypeColor(type['value']),
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          type['label'],
                                          style: TextStyle(fontSize: 16),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedEmployeeType = value;
                                _showEmployeeTypeDescription = false;
                                // Reset developer type when employee type changes
                                if (value != 'employee') {
                                  selectedDeveloperType = null;
                                }
                              });
                            },
                            validator: (value) {
                              return value == null ? 'Please select an employee type' : null;
                            },
                          ),
                          if (selectedEmployeeType != null) ...[
                            SizedBox(height: 8),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _showEmployeeTypeDescription = !_showEmployeeTypeDescription;
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        _showEmployeeTypeDescription
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: Colors.grey[600],
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        _showEmployeeTypeDescription ? 'Hide details' : 'Show details',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_showEmployeeTypeDescription) ...[
                              SizedBox(height: 8),
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _getEmployeeTypeColor(selectedEmployeeType).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _getEmployeeTypeColor(selectedEmployeeType).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  employeeTypes.firstWhere((type) => type['value'] == selectedEmployeeType)['description'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),

                      // Developer Type Field - Only show when Employee is selected - Modified to show "Please select"
                      if (selectedEmployeeType == 'employee') ...[
                        SizedBox(height: 20),
                        _buildInputLabel('Role Type'),
                        SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: _buildInputDecoration(
                                hintText: 'Select developer type',
                                prefixIcon: Icons.code_rounded,
                              ),
                              value: selectedDeveloperType,
                              isExpanded: true,
                              items: [
                                // Add "Please select" option
                                DropdownMenuItem<String>(
                                  value: null,
                                  child: Text(
                                    'Please select',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ),
                                ...developerTypes.map((type) {
                                  final color = type['color'] as Color;
                                  return DropdownMenuItem<String>(
                                    value: type['value'],
                                    child: Row(
                                      children: [
                                        Icon(
                                          type['icon'],
                                          color: color,
                                          size: 20,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            type['label'],
                                            style: TextStyle(fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  selectedDeveloperType = value;
                                  _showDeveloperTypeDescription = false;
                                });
                              },
                              validator: (value) {
                                return selectedEmployeeType == 'employee' && value == null
                                    ? 'Please select a developer type'
                                    : null;
                              },
                            ),
                            if (selectedDeveloperType != null) ...[
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _showDeveloperTypeDescription = !_showDeveloperTypeDescription;
                                      });
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          _showDeveloperTypeDescription
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: Colors.grey[600],
                                          size: 16,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          _showDeveloperTypeDescription ? 'Hide details' : 'Show details',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_showDeveloperTypeDescription) ...[
                                SizedBox(height: 8),
                                Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['color'] as Color).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['color'] as Color).withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['description'],
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ],

                      SizedBox(height: 20),

                      // Office Location Field
                      _buildInputLabel('Office Location'),
                      SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('office_locations')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Container(
                              height: 56,
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      color: Colors.grey[600]),
                                  SizedBox(width: 12),
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Loading locations...',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            );
                          }

                          final locations = snapshot.data!.docs;
                          return DropdownButtonFormField<String>(
                            decoration: _buildInputDecoration(
                              hintText: 'Select office location',
                              prefixIcon: Icons.location_on_outlined,
                            ),
                            value: selectedOfficeLocationId,
                            isExpanded: true,
                            items: locations.map((doc) {
                              return DropdownMenuItem<String>(
                                value: doc['id'],
                                child: Text(
                                  doc['name'],
                                  style: TextStyle(fontSize: 16),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedOfficeLocationId = value;
                              });
                            },
                            validator: (value) {
                              return value == null
                                  ? 'Please select an office location'
                                  : null;
                            },
                          );
                        },
                      ),

                      // Error Message Display
                      if (_errorMessage != null) ...[
                        SizedBox(height: 12),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red[600],
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red[600],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(height: 32),

                // Submit Button - Updated to handle nullable values
                Container(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleAddEmployee,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedEmployeeType == 'employee' && selectedDeveloperType != null
                          ? developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['color']
                          : _getEmployeeTypeColor(selectedEmployeeType),
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
                          _getLoadingText(),
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
                        Icon(
                            _getButtonIcon(),
                            size: 20
                        ),
                        SizedBox(width: 8),
                        Text(
                          _getButtonText(),
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

  String _getLoadingText() {
    if (selectedEmployeeType == 'employee' && selectedDeveloperType != null) {
      return 'Adding ${developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['label']}...';
    } else if (selectedEmployeeType != null) {
      return 'Adding ${employeeTypes.firstWhere((type) => type['value'] == selectedEmployeeType)['label']}...';
    }
    return 'Adding Employee...';
  }

  String _getButtonText() {
    if (selectedEmployeeType == 'employee' && selectedDeveloperType != null) {
      return 'Add ${developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['label']}';
    } else if (selectedEmployeeType != null) {
      return 'Add ${employeeTypes.firstWhere((type) => type['value'] == selectedEmployeeType)['label']}';
    }
    return 'Add Employee';
  }

  IconData _getButtonIcon() {
    if (selectedEmployeeType == 'employee' && selectedDeveloperType != null) {
      return developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['icon'];
    } else if (selectedEmployeeType != null) {
      return employeeTypes.firstWhere((type) => type['value'] == selectedEmployeeType)['icon'];
    }
    return Icons.person_add_rounded;
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

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon: Icon(prefixIcon, color: Colors.grey[600]),
      suffixIcon: suffixIcon,
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

  Future<void> _handleAddEmployee() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Clear any previous error message
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Include developer type only if employee type is 'employee'
      final String employeeTypeToSend = selectedEmployeeType == 'employee'
          ? selectedDeveloperType!  // Use the developer type (full_stack, frontend, etc.)
          : selectedEmployeeType!;  // Use the original type (intern, freelancer)

      await authProvider.addEmployee(
        emailController.text.trim(),
        nameController.text.trim(),
        passwordController.text,
        'employee',
        selectedOfficeLocationId,
        employeeTypeToSend,
        context,
        onSuccess: () {
          // Show success message and navigate back
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text(_getSuccessMessage()),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          // Navigate back to previous screen
          Navigator.of(context).pop();
        },
        onError: (String errorMessage) {
          // Show error below office location field
          setState(() {
            _errorMessage = errorMessage;
          });
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getSuccessMessage() {
    if (selectedEmployeeType == 'employee' && selectedDeveloperType != null) {
      return '${developerTypes.firstWhere((type) => type['value'] == selectedDeveloperType)['label']} added successfully!';
    } else if (selectedEmployeeType != null) {
      return '${employeeTypes.firstWhere((type) => type['value'] == selectedEmployeeType)['label']} added successfully!';
    }
    return 'Employee added successfully!';
  }
}