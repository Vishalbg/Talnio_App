import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';
import 'employee_details_screen.dart';
import 'email_service.dart';
import 'otp_verification_screen.dart';

class AuthProvider with ChangeNotifier {
  final fa.FirebaseAuth _auth = fa.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  fa.User? _user;
  String? _role;
  String? _name;

  bool get isAuthenticated => _user != null;
  String? get role => _role;
  String? get name => _name;

  fa.User? get currentUser => _user;

  AuthProvider() {
    _auth.authStateChanges().listen((user) async {
      if (user != null && user.uid != _user?.uid) {
        _user = user;
        try {
          DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              _role = data['role'] is String ? data['role'] : null;
              _name = data['name'] is String ? data['name'] : null;
              debugPrint('Auth state changed: role=$_role, name=$_name, uid=${user.uid}');
            } else {
              debugPrint('User document data is null for uid=${user.uid}');
              _role = null;
              _name = null;
            }
          } else {
            debugPrint('User document does not exist for uid=${user.uid}');
            _role = null;
            _name = null;
          }
        } catch (e) {
          debugPrint('Error fetching user document: $e');
          _role = null;
          _name = null;
        }
        notifyListeners();
      } else if (user == null) {
        _user = null;
        _role = null;
        _name = null;
        debugPrint('User signed out');
        notifyListeners();
      }
    });
  }

  Future<void> signIn(String email, String password, BuildContext context, {Function(String)? onError}) async {
    try {
      fa.UserCredential credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      debugPrint('Signed in user: ${credential.user!.uid}, email: ${credential.user!.email}');

      // Check if this is the first login
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(credential.user!.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        if (data != null && data['lastLogin'] == null && data['role'] == 'employee') {
          // Redirect to EmployeeDetailsScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => EmployeeDetailsScreen()),
          );
        } else {
          // Update lastLogin
          await _firestore.collection('users').doc(credential.user!.uid).update({
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }
      }
    } on fa.FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found for that email address.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password provided.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password. Please check your credentials.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection.';
          break;
        default:
          errorMessage = 'Login failed: ${e.message ?? 'Unknown error occurred'}';
      }
      debugPrint('Sign-in error: $e, code: ${e.code}');

      // Use callback if provided, otherwise show SnackBar
      if (onError != null) {
        onError(errorMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      debugPrint('Unexpected sign-in error: $e');
      String errorMessage = 'An unexpected error occurred. Please try again.';

      // Use callback if provided, otherwise show SnackBar
      if (onError != null) {
        onError(errorMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  Future<bool> checkEmailExists(String email) async {
    debugPrint('Starting email existence check for: $email');

    // Check Firestore users collection
    bool firestoreExists = await _checkEmailInFirestore(email);

    if (firestoreExists) {
      debugPrint('Email found in Firestore: $email');
      return true;
    }

    // If not found in Firestore, check Firebase Auth
    try {
      final signInMethods = await _auth.fetchSignInMethodsForEmail(email);
      bool authExists = signInMethods.isNotEmpty;
      debugPrint('Firebase Auth check for $email: $authExists (methods: $signInMethods)');
      return authExists;
    } on fa.FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth exception for $email: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Firebase Auth error for $email: $e');
      return false;
    }
  }

// Improve the _checkEmailInFirestore method
  Future<bool> _checkEmailInFirestore(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      bool exists = querySnapshot.docs.isNotEmpty;
      debugPrint('Firestore email check for $email: $exists');

      if (exists) {
        final userData = querySnapshot.docs.first.data();
        debugPrint('Found user in Firestore: ${userData['name']} (${userData['role']})');
      } else {
        debugPrint('No user found in Firestore with email: $email');
      }

      return exists;
    } catch (e) {
      debugPrint('Error checking email in Firestore: $e');
      return false;
    }
  }

  Future<void> addEmployee(
      String email,
      String name,
      String password,
      String role,
      String? officeLocationId,
      String employeeType,
      BuildContext context, {
        Function()? onSuccess,
        Function(String)? onError,
      }) async {
    final String? currentManagerUid = _auth.currentUser?.uid;

    if (currentManagerUid == null) {
      debugPrint('No authenticated user in primary auth instance');
      if (onError != null) {
        onError('No authenticated user. Please sign in again.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No authenticated user. Please sign in again.'))
        );
      }
      return;
    }

    debugPrint('Current Manager UID: $currentManagerUid, Role: $_role, Email: ${_auth.currentUser?.email}');

    if (_role != 'admin' && _role != 'manager') {
      if (onError != null) {
        onError('Unauthorized: Only admins or managers can add employees');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unauthorized: Only admins or managers can add employees'))
        );
      }
      return;
    }

    if (role != 'employee') {
      if (onError != null) {
        onError('Invalid role: Only employee role is allowed');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid role: Only employee role is allowed'))
        );
      }
      return;
    }

    // Validate employee type - now includes developer types
    final validEmployeeTypes = [
      'employee', 'intern', 'freelancer',
      'full_stack', 'frontend', 'backend', 'ui_ux'
    ];

    if (!validEmployeeTypes.contains(employeeType)) {
      if (onError != null) {
        onError('Invalid employee type');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid employee type'))
        );
      }
      return;
    }

    debugPrint('Adding employee with email: $email, name: $name, role: $role, employeeType: $employeeType, officeLocationId: $officeLocationId');

    try {
      // Store current user info before creating secondary auth
      final currentUserEmail = _auth.currentUser?.email;
      final currentUserUid = _auth.currentUser?.uid;

      // Create a completely separate Firebase app instance for employee creation
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('secondary');
      } catch (e) {
        secondaryApp = await Firebase.initializeApp(
          name: 'secondary',
          options: Firebase.app().options,
        );
      }

      fa.FirebaseAuth secondaryAuth = fa.FirebaseAuth.instanceFor(app: secondaryApp);

      // Create the employee account using secondary auth
      fa.UserCredential cred = await secondaryAuth.createUserWithEmailAndPassword(
          email: email,
          password: password
      );

      debugPrint('Created employee UID: ${cred.user!.uid}, Email: ${cred.user!.email}');
      debugPrint('Manager UID being assigned: $currentManagerUid');

      // Prepare user data with enhanced employee type information
      final userData = {
        'uid': cred.user!.uid,
        'email': email,
        'name': name,
        'role': role,
        'employeeType': employeeType,
        'officeLocationId': officeLocationId ?? FieldValue.delete(),
        'managerId': currentManagerUid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': null,
      };

      // Add additional fields based on employee type
      if (['full_stack', 'frontend', 'backend', 'ui_ux'].contains(employeeType)) {
        userData['isDeveloper'] = true;
        userData['developerType'] = employeeType;

        // Add developer-specific fields
        switch (employeeType) {
          case 'full_stack':
            userData['skills'] = ['Frontend', 'Backend', 'Database', 'DevOps'];
            userData['department'] = 'Engineering';
            break;
          case 'frontend':
            userData['skills'] = ['HTML', 'CSS', 'JavaScript', 'React', 'Vue', 'Angular'];
            userData['department'] = 'Engineering';
            break;
          case 'backend':
            userData['skills'] = ['Server Development', 'Database', 'API Design', 'Cloud Services'];
            userData['department'] = 'Engineering';
            break;
          case 'ui_ux':
            userData['skills'] = ['UI Design', 'UX Research', 'Prototyping', 'User Testing'];
            userData['department'] = 'Design';
            break;
        }
      } else {
        userData['isDeveloper'] = false;
        userData['department'] = employeeType == 'intern' ? 'Internship Program' : 'General';
      }

      debugPrint('Writing user data to Firestore: $userData');
      await _firestore.collection('users').doc(cred.user!.uid).set(userData);

      // Sign out from secondary auth to avoid conflicts
      await secondaryAuth.signOut();

      // Verify current user is still authenticated in primary auth
      if (_auth.currentUser?.uid != currentUserUid) {
        debugPrint('Primary auth state changed unexpectedly, attempting to restore');
        // If somehow the primary auth was affected, we don't re-authenticate here
        // as it would require the password. Instead, we'll let the auth state listener handle it.
      }

      debugPrint('Employee added successfully for UID: ${cred.user!.uid} with Manager UID: $currentManagerUid');

      if (onSuccess != null) {
        onSuccess();
      } else {
        // Display a more specific message based on the employee type
        String displayType = _getDisplayTypeForEmployeeType(employeeType);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$displayType added successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            )
        );
      }

    } on fa.FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'The email is already registered.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'weak-password':
          errorMessage = 'The password is too weak.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password accounts are not enabled.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your connection.';
          break;
        default:
          errorMessage = 'Failed to add employee: ${e.message}';
      }
      debugPrint('Firebase Auth error: $e, code: ${e.code}');

      if (onError != null) {
        onError(errorMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            )
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: $e, code: ${e.code}, message: ${e.message}');
      String errorMessage = 'Database error: ${e.message ?? 'Unknown error occurred'}';

      if (onError != null) {
        onError(errorMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            )
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error adding employee: $e\nStackTrace: $stackTrace');
      String errorMessage = 'An unexpected error occurred. Please try again.';

      if (onError != null) {
        onError(errorMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            )
        );
      }
    }
  }

// Helper method to get display-friendly employee type names
  String _getDisplayTypeForEmployeeType(String employeeType) {
    switch (employeeType) {
      case 'full_stack':
        return 'Full Stack Developer';
      case 'frontend':
        return 'Frontend Developer';
      case 'backend':
        return 'Backend Developer';
      case 'ui_ux':
        return 'UI/UX Designer';
      case 'employee':
        return 'Employee';
      case 'intern':
        return 'Intern';
      case 'freelancer':
        return 'Freelancer';
      default:
        return employeeType.toUpperCase();
    }
  }

  // Updated addManager method with callback support
// Updated addManager method with proper secondary auth implementation
  Future<void> addManager(
      String email,
      String name,
      String password,
      String? officeLocationId,
      BuildContext context, {
        Function()? onSuccess,
        Function(String)? onError,
      }) async {
    final String? currentAdminUid = _auth.currentUser?.uid;

    if (currentAdminUid == null) {
      debugPrint('No authenticated user in primary auth instance');
      if (onError != null) {
        onError('No authenticated user. Please sign in again.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No authenticated user. Please sign in again.')));
      }
      return;
    }

    debugPrint('Current Admin UID: $currentAdminUid, Role: $_role, Email: ${_auth.currentUser?.email}');

    if (_role != 'admin') {
      if (onError != null) {
        onError('Unauthorized: Only admins can add managers');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unauthorized: Only admins can add managers')));
      }
      return;
    }

    debugPrint('Adding manager with email: $email, name: $name, role: manager, officeLocationId: $officeLocationId');

    try {
      // Store current user info before creating secondary auth
      final currentUserEmail = _auth.currentUser?.email;
      final currentUserUid = _auth.currentUser?.uid;

      // Create a completely separate Firebase app instance for manager creation
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('secondary');
      } catch (e) {
        secondaryApp = await Firebase.initializeApp(
          name: 'secondary',
          options: Firebase.app().options,
        );
      }

      fa.FirebaseAuth secondaryAuth = fa.FirebaseAuth.instanceFor(app: secondaryApp);
      fa.UserCredential cred = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);

      debugPrint('Created manager UID: ${cred.user!.uid}, Email: ${cred.user!.email}');

      final userData = {
        'uid': cred.user!.uid,
        'email': email,
        'name': name,
        'role': 'manager',
        'officeLocationId': officeLocationId ?? FieldValue.delete(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': null, // Initialize lastLogin as null
      };

      debugPrint('Writing manager data to Firestore: $userData');
      await _firestore.collection('users').doc(cred.user!.uid).set(userData);

      // Sign out from secondary auth to avoid conflicts
      await secondaryAuth.signOut();

      // Verify current user is still authenticated in primary auth
      if (_auth.currentUser?.uid != currentUserUid) {
        debugPrint('Primary auth state changed unexpectedly, attempting to restore');
        // If somehow the primary auth was affected, we don't re-authenticate here
        // as it would require the password. Instead, we'll let the auth state listener handle it.
      }

      debugPrint('Manager added successfully for UID: ${cred.user!.uid}');

      if (onSuccess != null) {
        onSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Manager added successfully')));
      }

    } on fa.FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'The email is already registered.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'weak-password':
          errorMessage = 'The password is too weak.';
          break;
        default:
          errorMessage = 'Failed to add manager: ${e.message}';
      }
      debugPrint('Firebase Auth error: $e, code: ${e.code}');

      if (onError != null) {
        onError(errorMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: $e, code: ${e.code}, message: ${e.message}');

      if (onError != null) {
        onError('Firestore error: ${e.message}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Firestore error: ${e.message}')));
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error adding manager: $e\nStackTrace: $stackTrace');

      if (onError != null) {
        onError('Failed to add manager: $e');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add manager: $e')));
      }
    }
  }

  Future<void> updateUserOfficeLocation(String userId, String? officeLocationId, BuildContext context) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'officeLocationId': officeLocationId,
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Office location updated successfully')));
    } catch (e) {
      debugPrint('Error updating office location: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update office location: $e')));
    }
  }

  Future<void> deleteUser(String userId, BuildContext context) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User deleted successfully')));
    } catch (e) {
      debugPrint('Error deleting user: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete user: $e')));
    }
  }

  Future<void> updateProfile(
      String name,
      String? password,
      BuildContext context,
      {bool silent = false} // Add silent parameter
      ) async {
    try {
      if (name.isNotEmpty) {
        await _firestore.collection('users').doc(_user!.uid).update({'name': name});
        _name = name;
      }
      if (password != null && password.isNotEmpty) {
        await _user!.updatePassword(password);
      }
      notifyListeners();

      // Only show SnackBar if not silent
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Profile updated successfully'))
        );
      }
    } catch (e) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update profile: $e'))
        );
      }
      throw e; // Re-throw to allow caller to handle
    }
  }

  // Modified updateEmployeeDetails method with silent parameter
  Future<void> updateEmployeeDetails({
    required String userId,
    required String aadhaarNumber,
    required String panNumber,
    required String bloodGroup,
    required String permanentAddress,
    required String currentAddress,
    required String mobileNumber,
    required String alternateMobile,
    required String alternateContactRelation,
    required BuildContext context,
    bool silent = false, // Add silent parameter
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'aadhaarNumber': aadhaarNumber,
        'panNumber': panNumber,
        'bloodGroup': bloodGroup,
        'permanentAddress': permanentAddress,
        'currentAddress': currentAddress,
        'mobileNumber': mobileNumber,
        'alternateMobile': alternateMobile,
        'alternateContactRelation': alternateContactRelation,
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // Only show SnackBar if not silent
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Employee details updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error updating employee details: $e');

      // Only show SnackBar if not silent
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update employee details: $e')),
        );
      }
      throw e; // Re-throw to allow caller to handle
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> requestCheckout({
    required String userId,
    required String officeLocationId,
    required double distance,
    required Map<String, double> location,
    required BuildContext context,
  }) async {
    try {
      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final managerId = userData?['managerId'] ?? '';

      await _firestore.collection('checkout_requests').doc('${userId}_$todayDate').set({
        'userId': userId,
        'date': todayDate,
        'status': 'pending',
        'officeLocationId': officeLocationId,
        'requestTime': FieldValue.serverTimestamp(),
        'managerId': managerId,
        'distance': distance,
        'location': location,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout request submitted successfully')),
      );
    } catch (e) {
      debugPrint('Error requesting checkout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request checkout: $e')),
      );
      throw Exception('Failed to request checkout: $e');
    }
  }

  Future<void> respondToCheckoutRequest({
    required String requestId,
    required String status,
    required BuildContext context,
  }) async {
    try {
      await _firestore.collection('checkout_requests').doc(requestId).update({
        'status': status,
        'responseTime': FieldValue.serverTimestamp(),
      });

      if (status == 'approved') {
        final requestDoc = await _firestore.collection('checkout_requests').doc(requestId).get();
        final requestData = requestDoc.data() as Map<String, dynamic>;
        final userId = requestData['userId'];
        final date = requestData['date'];
        final officeLocationId = requestData['officeLocationId'];
        final location = requestData['location'];
        final distance = requestData['distance'];

        final attendanceDocRef = _firestore.collection('attendance').doc('${userId}_$date');
        await attendanceDocRef.update({
          'checkOutTime': FieldValue.serverTimestamp(),
          'locationCheckOut': location,
          'distanceCheckOut': distance,
          'officeLocationId': officeLocationId,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout request $status successfully')),
      );
    } catch (e) {
      debugPrint('Error responding to checkout request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update checkout request: $e')),
      );
      throw Exception('Failed to update checkout request: $e');
    }
  }

  Future<Map<String, dynamic>?> getCheckoutRequestStatus(String userId) async {
    try {
      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final doc = await _firestore.collection('checkout_requests').doc('${userId}_$todayDate').get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching checkout request status: $e');
      return null;
    }
  }

  Future<void> requestLeave({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required String leaveType,
    required String reason,
    required BuildContext context,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final managerId = userData?['managerId'] ?? '';
      final requestId = Uuid().v4();

      await _firestore.collection('leave_requests').doc(requestId).set({
        'userId': userId,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'leaveType': leaveType,
        'reason': reason,
        'status': 'pending',
        'requestTime': FieldValue.serverTimestamp(),
        'managerId': managerId,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave request submitted successfully')),
      );
    } catch (e) {
      debugPrint('Error requesting leave: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request leave: $e')),
      );
      throw Exception('Failed to request leave: $e');
    }
  }

  Future<void> respondToLeaveRequest({
    required String requestId,
    required String status,
    required String rejectionReason,
    required BuildContext context,
  }) async {
    try {
      final updates = {
        'status': status,
        'responseTime': FieldValue.serverTimestamp(),
      };
      if (status == 'rejected' && rejectionReason.isNotEmpty) {
        updates['rejectionReason'] = rejectionReason;
      }
      await _firestore.collection('leave_requests').doc(requestId).update(updates);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave request $status successfully')),
      );
    } catch (e) {
      debugPrint('Error responding to leave request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update leave request: $e')),
      );
      throw Exception('Failed to update leave request: $e');
    }
  }

  Future<void> sendPasswordResetEmail(String email, BuildContext context) async {
    try {
      // First check if email exists in Firestore
      bool emailExists = await _checkEmailInFirestore(email);

      if (!emailExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No account found with this email address'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Get user name from Firestore
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error retrieving user information'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final userData = querySnapshot.docs.first.data();
      final userName = userData['name'] ?? 'User';

      // Send OTP email
      final otp = await EmailService.sendOTPEmail(
        email: email,
        name: userName,
      );

      if (otp != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification code sent to $email'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to OTP verification screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPVerificationScreen(email: email),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send verification code. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      debugPrint('OTP sent to: $email');

    } catch (e) {
      debugPrint('Unexpected error sending OTP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

// Add a method to verify OTP and reset password
  Future<bool> verifyOTPAndResetPassword(String email, String otp, String newPassword, BuildContext context) async {
    try {
      bool isValid = await EmailService.verifyOTP(email: email, otp: otp);

      if (!isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid or expired verification code'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      // Get user from Firestore
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User not found'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      final userData = querySnapshot.docs.first.data();
      final userId = userData['uid'];

      // Create a secondary auth instance to reset password
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('secondary');
      } catch (e) {
        secondaryApp = await Firebase.initializeApp(
          name: 'secondary',
          options: Firebase.app().options,
        );
      }

      fa.FirebaseAuth secondaryAuth = fa.FirebaseAuth.instanceFor(app: secondaryApp);

      // Sign in with custom token or email link would be ideal here, but we'll use a workaround
      // This is a simplified approach - in production, you might want a more secure method
      try {
        // Generate a temporary password reset token in Firestore
        await _firestore.collection('password_resets').doc(userId).set({
          'email': email,
          'timestamp': FieldValue.serverTimestamp(),
          'completed': false
        });

        // Update the password in Firebase Auth
        await fa.FirebaseAuth.instance.sendPasswordResetEmail(email: email);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset link sent to your email. Please check your inbox to complete the process.'),
            backgroundColor: Colors.green,
          ),
        );

        return true;
      } catch (e) {
        debugPrint('Error resetting password: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset password: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    } catch (e) {
      debugPrint('Error in verifyOTPAndResetPassword: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }
}
