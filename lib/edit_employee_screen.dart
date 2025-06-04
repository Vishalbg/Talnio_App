import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart';

class EditEmployeeScreen extends StatefulWidget {
  final String userId;
  final String? currentOfficeLocationId; // Allow null

  EditEmployeeScreen({required this.userId, required this.currentOfficeLocationId});

  @override
  _EditEmployeeScreenState createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  String? selectedOfficeLocationId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Only set selectedOfficeLocationId if currentOfficeLocationId is non-empty and valid
    selectedOfficeLocationId = widget.currentOfficeLocationId != null && widget.currentOfficeLocationId!.isNotEmpty
        ? widget.currentOfficeLocationId
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: Text('Edit Employee')),
      body: SingleChildScrollView( // Prevent overflow
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('office_locations').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('Error loading office locations: ${snapshot.error}');
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text('No office locations available');
                }

                final locations = snapshot.data!.docs;
                // Ensure selectedOfficeLocationId is valid
                if (selectedOfficeLocationId != null &&
                    !locations.any((doc) => doc['id'] == selectedOfficeLocationId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() {
                      selectedOfficeLocationId = null;
                    });
                  });
                }

                return DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Select Office Location',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  value: selectedOfficeLocationId,
                  isExpanded: true,
                  items: locations.map((doc) {
                    return DropdownMenuItem<String>(
                      value: doc['id'],
                      child: Text(doc['name'] ?? 'Unnamed Location'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedOfficeLocationId = value);
                  },
                  validator: (value) => value == null ? 'Please select an office location' : null,
                );
              },
            ),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton.icon(
              icon: Icon(Icons.save),
              label: Text('Update Office Location'),
              onPressed: () async {
                if (selectedOfficeLocationId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please select an office location')),
                  );
                  return;
                }
                setState(() => _isLoading = true);
                await authProvider.updateUserOfficeLocation(
                  widget.userId,
                  selectedOfficeLocationId,
                  context,
                );
                setState(() => _isLoading = false);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}