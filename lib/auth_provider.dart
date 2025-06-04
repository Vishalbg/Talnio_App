import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';
import 'employee_details_screen.dart';

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

  Future<void> signIn(String email, String password, BuildContext context) async {
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
          errorMessage = 'No user found for that email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password provided.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        default:
          errorMessage = 'Login failed: ${e.message}';
      }
      debugPrint('Sign-in error: $e, code: ${e.code}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    } catch (e) {
      debugPrint('Unexpected sign-in error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    }
  }

  Future<bool> checkEmailExists(String email) async {
    debugPrint('Starting email existence check for: $email');

    bool authExists = false;
    bool firestoreExists = false;

    // Check Firebase Auth
    try {
      final signInMethods = await _auth.fetchSignInMethodsForEmail(email);
      authExists = signInMethods.isNotEmpty;
      debugPrint('Firebase Auth check for $email: $authExists (methods: $signInMethods)');
    } on fa.FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth exception for $email: ${e.code} - ${e.message}');
      // Don't return false here, continue to check Firestore
    } catch (e) {
      debugPrint('Firebase Auth error for $email: $e');
      // Don't return false here, continue to check Firestore
    }

    // Check Firestore users collection
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      firestoreExists = querySnapshot.docs.isNotEmpty;
      debugPrint('Firestore check for $email: $firestoreExists');

      if (firestoreExists) {
        final userData = querySnapshot.docs.first.data();
        debugPrint('Found user in Firestore: ${userData['name']} (${userData['role']})');
      }
    } catch (e) {
      debugPrint('Firestore error checking email $email: $e');
    }

    // Email exists if found in either Firebase Auth OR Firestore
    bool emailExists = authExists || firestoreExists;
    debugPrint('Final result for $email: $emailExists (Auth: $authExists, Firestore: $firestoreExists)');

    return emailExists;
  }

  Future<bool> _checkEmailInFirestore(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      bool exists = querySnapshot.docs.isNotEmpty;
      debugPrint('Firestore email check for $email: $exists');
      return exists;
    } catch (e) {
      debugPrint('Error checking email in Firestore: $e');
      // If both methods fail, assume email doesn't exist to prevent security issues
      return false;
    }
  }




  // Updated addEmployee method in AuthProvider class
  Future<void> addEmployee(String email, String name, String password, String role, String? officeLocationId, String employeeType, BuildContext context) async {
    final String? currentManagerUid = _auth.currentUser?.uid;

    if (currentManagerUid == null) {
      debugPrint('No authenticated user in primary auth instance');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No authenticated user. Please sign in again.')));
      return;
    }

    debugPrint('Current Manager UID: $currentManagerUid, Role: $_role, Email: ${_auth.currentUser?.email}');

    if (_role != 'admin' && _role != 'manager') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unauthorized: Only admins or managers can add employees')));
      return;
    }

    if (role != 'employee') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid role: Only employee role is allowed')));
      return;
    }

    // Validate employee type
    if (!['employee', 'intern', 'freelancer'].contains(employeeType)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid employee type')));
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
      fa.UserCredential cred = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);

      debugPrint('Created employee UID: ${cred.user!.uid}, Email: ${cred.user!.email}');
      debugPrint('Manager UID being assigned: $currentManagerUid');

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${employeeType.toUpperCase()} added successfully')));

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
          errorMessage = 'Failed to add employee: ${e.message}';
      }
      debugPrint('Firebase Auth error: $e, code: ${e.code}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: $e, code: ${e.code}, message: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Firestore error: ${e.message}')));
    } catch (e, stackTrace) {
      debugPrint('Unexpected error adding employee: $e\nStackTrace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add employee: $e')));
    }
  }

  Future<void> addManager(String email, String name, String password, String? officeLocationId, BuildContext context) async {
    final String? currentAdminUid = _auth.currentUser?.uid;

    if (currentAdminUid == null) {
      debugPrint('No authenticated user in primary auth instance');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No authenticated user. Please sign in again.')));
      return;
    }

    debugPrint('Current Admin UID: $currentAdminUid, Role: $_role, Email: ${_auth.currentUser?.email}');

    if (_role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unauthorized: Only admins can add managers')));
      return;
    }

    debugPrint('Adding manager with email: $email, name: $name, role: manager, officeLocationId: $officeLocationId');

    try {
      fa.FirebaseAuth secondaryAuth = fa.FirebaseAuth.instanceFor(app: Firebase.app());
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

      await secondaryAuth.signOut();

      debugPrint('Manager added successfully for UID: ${cred.user!.uid}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Manager added successfully')));

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: $e, code: ${e.code}, message: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Firestore error: ${e.message}')));
    } catch (e, stackTrace) {
      debugPrint('Unexpected error adding manager: $e\nStackTrace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add manager: $e')));
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

  Future<void> updateProfile(String name, String? password, BuildContext context) async {
    try {
      if (name.isNotEmpty) {
        await _firestore.collection('users').doc(_user!.uid).update({'name': name});
        _name = name;
      }
      if (password != null && password.isNotEmpty) {
        await _user!.updatePassword(password);
      }
      notifyListeners();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    }
  }

  Future<void> updateEmployeeDetails({
    required String userId,
    required String aadhaarNumber,
    required String panNumber,
    required String bloodGroup,
    required String permanentAddress,
    required String currentAddress,
    required String alternateMobile,
    required String alternateContactRelation, // Added new parameter
    required BuildContext context,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'aadhaarNumber': aadhaarNumber,
        'panNumber': panNumber,
        'bloodGroup': bloodGroup,
        'permanentAddress': permanentAddress,
        'currentAddress': currentAddress,
        'alternateMobile': alternateMobile,
        'alternateContactRelation': alternateContactRelation, // Store the relationship
        'lastLogin': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Employee details updated successfully')),
      );
    } catch (e) {
      debugPrint('Error updating employee details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update employee details: $e')),
      );
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
      bool emailExists = await checkEmailExists(email);

      if (!emailExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No account found with this email address'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Send password reset email using Firebase Auth
      await _auth.sendPasswordResetEmail(email: email);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent to $email'),
          backgroundColor: Colors.green,
        ),
      );

      debugPrint('Password reset email sent to: $email');

    } on fa.FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found for that email.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many requests. Please try again later.';
          break;
        default:
          errorMessage = 'Failed to send reset email: ${e.message}';
      }
      debugPrint('Password reset error: $e, code: ${e.code}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('Unexpected error sending password reset email: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}