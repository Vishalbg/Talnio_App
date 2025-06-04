import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:uuid/uuid.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'auth_provider.dart';
import 'report_screen.dart';
import 'dart:typed_data';

class AttendanceScreen extends StatefulWidget {
  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  double? officeLat;
  double? officeLong;
  double? radius;
  String? officeName;
  bool _isCheckedIn = false;
  bool _isLoading = false;
  bool _isLocationLoading = true;
  bool _isOfficeDataLoading = true;
  Position? _currentPosition;
  double? _currentDistance;
  DateTime? _checkInTime;
  DateTime? _checkOutTime;
  Map<String, dynamic>? _checkoutRequestStatus;
  bool _isNfcScanning = false;
  String? _scannedNfcId;
  final String _expectedNfcId = "12345678"; // Hardcoded NFC ID
  bool _mounted = true; // Track if widget is mounted

  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkTodayAttendanceStatus();
    await Future.wait([
      _loadUserOfficeLocation(),
      _checkCurrentLocation(),
      _checkCheckoutRequestStatus(),
    ]);
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.elasticOut));

    _slideController.forward();
  }

  @override
  void dispose() {
    _mounted = false; // Mark as unmounted
    _pulseController.dispose();
    _slideController.dispose();
    // Make sure to cancel any ongoing NFC sessions
    NfcManager.instance.stopSession();
    super.dispose();
  }

  // Safe setState that checks if widget is still mounted
  void _safeSetState(Function() fn) {
    if (_mounted) {
      setState(fn);
    }
  }

  Future<bool> _checkNfcAvailability() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable && _mounted) {
      _showSnackBar('NFC is not available on this device', isError: true);
      return false;
    }
    return isAvailable;
  }

  Future<bool> _scanNfcCard() async {
    if (!await _checkNfcAvailability()) {
      return false;
    }

    if (_mounted) {
      setState(() => _isNfcScanning = true);
    } else {
      return false;
    }

    bool scanResult = false;

    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            String nfcData = "";

            // First try to read NDEF data (which contains your "12345678")
            if (tag.data.containsKey('ndef')) {
              final ndef = tag.data['ndef'];
              if (ndef != null && ndef['cachedMessage'] != null) {
                final cachedMessage = ndef['cachedMessage'];
                if (cachedMessage['records'] != null) {
                  final records = cachedMessage['records'] as List;

                  for (var record in records) {
                    if (record['payload'] != null) {
                      final payload = record['payload'] as List<int>;

                      // Convert payload to string
                      String payloadString = String.fromCharCodes(payload);
                      debugPrint('Raw payload string: $payloadString');

                      // For text records, skip the first few bytes (language code, etc.)
                      if (payload.length > 3) {
                        // Skip the first 3 bytes (0x02 0x65 0x6E) to get "12345678"
                        nfcData = String.fromCharCodes(payload.skip(3));
                        debugPrint('Extracted NFC data: $nfcData');
                        break;
                      }
                    }
                  }
                }
              }
            }

            // Fallback: try to get tag identifier if NDEF reading fails
            if (nfcData.isEmpty) {
              debugPrint('NDEF data not found, trying tag identifier...');

              if (tag.data.containsKey('nfca')) {
                final nfca = tag.data['nfca'];
                if (nfca['identifier'] != null) {
                  nfcData = nfca['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              } else if (tag.data.containsKey('nfcb')) {
                final nfcb = tag.data['nfcb'];
                if (nfcb['identifier'] != null) {
                  nfcData = nfcb['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              } else if (tag.data.containsKey('nfcf')) {
                final nfcf = tag.data['nfcf'];
                if (nfcf['identifier'] != null) {
                  nfcData = nfcf['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              } else if (tag.data.containsKey('nfcv')) {
                final nfcv = tag.data['nfcv'];
                if (nfcv['identifier'] != null) {
                  nfcData = nfcv['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              }
            }

            debugPrint('Final NFC data: $nfcData');
            debugPrint('Expected NFC ID: $_expectedNfcId');

            // Validate the extracted NFC data
            if (nfcData.isNotEmpty && nfcData.trim().length >= 4) {
              if (_mounted) {
                setState(() => _scannedNfcId = nfcData.trim());
              }

              // Compare with expected ID
              if (_scannedNfcId == _expectedNfcId) {
                scanResult = true;
                if (_mounted) {
                  _showSnackBar('NFC Card scanned successfully!', isError: false);
                }
              } else {
                scanResult = false;
                if (_mounted) {
                  _showSnackBar('Invalid NFC card. Please use the correct card.', isError: true);
                }
              }
            } else {
              scanResult = false;
              if (_mounted) {
                _showSnackBar('Failed to read NFC card data. Please try again.', isError: true);
              }
            }

            await NfcManager.instance.stopSession();
          } catch (e) {
            debugPrint('Error reading NFC tag: $e');
            if (_mounted) {
              _showSnackBar('Error reading NFC card: $e', isError: true);
            }
            await NfcManager.instance.stopSession();
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
      if (_mounted) {
        _showSnackBar('NFC scanning failed: $e', isError: true);
      }
    } finally {
      if (_mounted) {
        setState(() => _isNfcScanning = false);
      }
    }

    return scanResult;
  }

  Future<void> _scanNfcCardWithDialog(VoidCallback onSuccess) async {
    if (!await _checkNfcAvailability()) {
      if (_mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    if (_mounted) {
      setState(() => _isNfcScanning = true);
    } else {
      return;
    }

    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            String nfcData = "";

            // First try to read NDEF data (which contains your "12345678")
            if (tag.data.containsKey('ndef')) {
              final ndef = tag.data['ndef'];
              if (ndef != null && ndef['cachedMessage'] != null) {
                final cachedMessage = ndef['cachedMessage'];
                if (cachedMessage['records'] != null) {
                  final records = cachedMessage['records'] as List;

                  for (var record in records) {
                    if (record['payload'] != null) {
                      final payload = record['payload'] as List<int>;

                      // Convert payload to string
                      String payloadString = String.fromCharCodes(payload);
                      debugPrint('Raw payload string: $payloadString');

                      // For text records, skip the first few bytes (language code, etc.)
                      if (payload.length > 3) {
                        // Skip the first 3 bytes (0x02 0x65 0x6E) to get "12345678"
                        nfcData = String.fromCharCodes(payload.skip(3));
                        debugPrint('Extracted NFC data: $nfcData');
                        break;
                      }
                    }
                  }
                }
              }
            }

            // Fallback: try to get tag identifier if NDEF reading fails
            if (nfcData.isEmpty) {
              debugPrint('NDEF data not found, trying tag identifier...');

              if (tag.data.containsKey('nfca')) {
                final nfca = tag.data['nfca'];
                if (nfca['identifier'] != null) {
                  nfcData = nfca['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              } else if (tag.data.containsKey('nfcb')) {
                final nfcb = tag.data['nfcb'];
                if (nfcb['identifier'] != null) {
                  nfcData = nfcb['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              } else if (tag.data.containsKey('nfcf')) {
                final nfcf = tag.data['nfcf'];
                if (nfcf['identifier'] != null) {
                  nfcData = nfcf['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              } else if (tag.data.containsKey('nfcv')) {
                final nfcv = tag.data['nfcv'];
                if (nfcv['identifier'] != null) {
                  nfcData = nfcv['identifier']
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join('')
                      .toUpperCase();
                }
              }
            }

            debugPrint('Final NFC data: $nfcData');
            debugPrint('Expected NFC ID: $_expectedNfcId');

            await NfcManager.instance.stopSession();

            // Validate the extracted NFC data
            if (nfcData.isNotEmpty && nfcData.trim().length >= 4) {
              if (_mounted) {
                setState(() => _scannedNfcId = nfcData.trim());
              } else {
                return;
              }

              // Compare with expected ID
              if (_scannedNfcId == _expectedNfcId) {
                if (_mounted) {
                  Navigator.of(context).pop();
                  onSuccess();
                }
              } else {
                if (_mounted) {
                  Navigator.of(context).pop();
                  _showSnackBar('Invalid NFC card. Please use the correct card.\nScanned: "$nfcData"\nExpected: "$_expectedNfcId"', isError: true);
                }
              }
            } else {
              if (_mounted) {
                Navigator.of(context).pop();
                _showSnackBar('Failed to read NFC card data. Please try again.', isError: true);
              }
            }
          } catch (e) {
            debugPrint('Error reading NFC tag: $e');
            await NfcManager.instance.stopSession();
            if (_mounted) {
              Navigator.of(context).pop();
              _showSnackBar('Error reading NFC card: $e', isError: true);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
      if (_mounted) {
        Navigator.of(context).pop();
        _showSnackBar('NFC scanning failed: $e', isError: true);
      }
    } finally {
      if (_mounted) {
        setState(() => _isNfcScanning = false);
      }
    }
  }

  void _showNfcScanDialog({required VoidCallback onSuccess}) {
    if (!_mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.nfc, color: Colors.blue[600]),
                  SizedBox(width: 12),
                  Text('Scan NFC Card'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: _scannedNfcId != null ? Colors.green[50] : Colors.blue[50],
                      borderRadius: BorderRadius.circular(60),
                      border: Border.all(
                        color: _scannedNfcId != null ? Colors.green[200]! : Colors.blue[200]!,
                        width: 2,
                      ),
                    ),
                    child: _isNfcScanning
                        ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Scanning...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[600],
                          ),
                        ),
                      ],
                    )
                        : _scannedNfcId != null
                        ? Icon(
                      Icons.check_circle,
                      size: 60,
                      color: Colors.green[600],
                    )
                        : Icon(
                      Icons.nfc,
                      size: 60,
                      color: Colors.blue[600],
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    _scannedNfcId != null
                        ? 'Card scanned successfully!'
                        : 'Hold your NFC card near the device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      fontWeight: _scannedNfcId != null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (_scannedNfcId != null) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Card ID: $_scannedNfcId',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _isNfcScanning
                      ? null
                      : () {
                    Navigator.of(context).pop();
                  },
                  child: Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Clean up NFC session if dialog is dismissed
      if (_isNfcScanning) {
        NfcManager.instance.stopSession();
        if (_mounted) {
          setState(() => _isNfcScanning = false);
        }
      }
    });

    // Start NFC scanning automatically when dialog opens
    Future.delayed(Duration(milliseconds: 500), () async {
      await _scanNfcCardWithDialog(onSuccess);
    });
  }

  Future<void> _checkTodayAttendanceStatus() async {
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final attendanceDocRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc('${user.uid}_$todayDate');

      final attendanceDoc = await attendanceDocRef.get();

      if (attendanceDoc.exists) {
        final attendanceData = attendanceDoc.data() as Map<String, dynamic>;
        final checkInTime = attendanceData['checkInTime'] as Timestamp?;
        final checkOutTime = attendanceData['checkOutTime'] as Timestamp?;

        if (_mounted) {
          setState(() {
            if (checkInTime != null) {
              _checkInTime = checkInTime.toDate();
            }
            if (checkOutTime != null) {
              _checkOutTime = checkOutTime.toDate();
            }
            _isCheckedIn = checkInTime != null && checkOutTime == null;
          });
        }

        debugPrint('Today\'s attendance status loaded: checkedIn=$_isCheckedIn, checkInTime=$_checkInTime, checkOutTime=$_checkOutTime');
      } else {
        if (_mounted) {
          setState(() {
            _isCheckedIn = false;
            _checkInTime = null;
            _checkOutTime = null;
          });
        }
        debugPrint('No attendance record found for today');
      }
    } catch (e) {
      debugPrint('Error checking today\'s attendance status: $e');
    }
  }

  Future<void> _checkCheckoutRequestStatus() async {
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final status = await authProvider.getCheckoutRequestStatus(user.uid);

      if (_mounted) {
        setState(() {
          _checkoutRequestStatus = status;
        });
      }
      debugPrint('Checkout request status: $_checkoutRequestStatus');
    } catch (e) {
      debugPrint('Error checking checkout request status: $e');
    }
  }

  Future<void> _loadUserOfficeLocation() async {
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user == null) return;

      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final officeLocationId = userData['officeLocationId'] as String?;
        if (officeLocationId != null) {
          DocumentSnapshot locationDoc = await FirebaseFirestore.instance
              .collection('office_locations')
              .doc(officeLocationId)
              .get();
          if (locationDoc.exists) {
            final locationData = locationDoc.data() as Map<String, dynamic>;

            // Check if widget is still mounted before calling setState
            if (_mounted) {
              setState(() {
                officeLat = (locationData['latitude'] as num?)?.toDouble() ?? 0.0;
                officeLong = (locationData['longitude'] as num?)?.toDouble() ?? 0.0;
                radius = (locationData['radius'] as num?)?.toDouble() ?? 100.0;
                officeName = locationData['name'] as String? ?? 'Unknown Office';
                _isOfficeDataLoading = false;
                debugPrint('Loaded office: name=$officeName, lat=$officeLat, long=$officeLong, radius=$radius');
              });

              if (_currentPosition != null) {
                _calculateDistance();
              }
            }
          }
        }
      }
    } catch (e) {
      if (_mounted) {
        setState(() => _isOfficeDataLoading = false);
        _showSnackBar('Failed to load office location: $e', isError: true);
      }
    }
  }

  Future<void> _checkCurrentLocation() async {
    try {
      Position position = await _getCurrentPosition();

      if (_mounted) {
        setState(() {
          _currentPosition = position;
          _isLocationLoading = false;
        });

        if (officeLat != null && officeLong != null) {
          _calculateDistance();
        }
      }

      debugPrint('Current location loaded: lat=${position.latitude}, long=${position.longitude}');
    } catch (e) {
      if (_mounted) {
        setState(() => _isLocationLoading = false);
        debugPrint('Error getting current location: $e');
        _showSnackBar('Failed to get location: ${e.toString()}', isError: true);
      }
    }
  }

  void _calculateDistance() {
    if (!_mounted) return;

    if (_currentPosition != null && officeLat != null && officeLong != null) {
      double distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        officeLat!,
        officeLong!,
      );
      setState(() {
        _currentDistance = distance;
      });
      debugPrint('Distance calculated: ${distance}m');
    }
  }

  Future<Position> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: Duration(seconds: 30),
    );
  }

  Future<bool> _checkLocation({int retryCount = 0, int maxRetries = 3}) async {
    if (!_mounted) return false;

    if (_isLoading || officeLat == null || officeLong == null || radius == null) {
      _showSnackBar('Office location not loaded yet', isError: true);
      return false;
    }

    setState(() => _isLoading = true);

    try {
      Position position = await _getCurrentPosition();

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLat!,
        officeLong!,
      );

      if (_mounted) {
        setState(() {
          _currentPosition = position;
          _currentDistance = distance;
          _isLocationLoading = false;
        });
      } else {
        return false;
      }

      debugPrint('Location Check:');
      debugPrint('Device: lat=${position.latitude}, long=${position.longitude}');
      debugPrint('Office: lat=$officeLat, long=$officeLong');
      debugPrint('Distance: ${distance}m, Allowed: ${radius}m');
      debugPrint('Within range: ${distance <= radius!}');

      if (distance <= radius!) {
        return true;
      } else {
        if (_mounted) {
          _showSnackBar(
            'You are ${distance.toInt()}m away from $officeName. Required: within ${radius!.toInt()}m',
            isError: true,
            duration: 4,
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Location error (attempt ${retryCount + 1}): $e');

      if (retryCount < maxRetries) {
        await Future.delayed(Duration(seconds: 2));
        return _checkLocation(retryCount: retryCount + 1, maxRetries: maxRetries);
      }

      if (_mounted) {
        _showSnackBar('Failed to get location: ${e.toString()}', isError: true, duration: 4);
      }
      return false;
    } finally {
      if (_mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkIn() async {
    if (!_mounted) return;

    if (_checkOutTime != null) {
      _showSnackBar('You have already completed attendance for today', isError: true, duration: 4);
      return;
    }

    if (await _checkLocation()) {
      // Reset scanned NFC ID
      setState(() => _scannedNfcId = null);

      // Show NFC scan dialog
      _showNfcScanDialog(
        onSuccess: () async {
          try {
            final user = fa.FirebaseAuth.instance.currentUser;
            if (user == null) {
              _showSnackBar('User not authenticated', isError: true);
              return;
            }

            final todayDate = DateTime.now().toIso8601String().split('T')[0];
            final attendanceDocRef = FirebaseFirestore.instance
                .collection('attendance')
                .doc('${user.uid}_$todayDate');

            final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
            final userData = userDoc.data() as Map<String, dynamic>?;
            final officeLocationId = userData?['officeLocationId'];

            await attendanceDocRef.set({
              'userId': user.uid,
              'date': todayDate,
              'checkInTime': FieldValue.serverTimestamp(),
              'locationCheckIn': {
                'lat': _currentPosition?.latitude ?? officeLat,
                'long': _currentPosition?.longitude ?? officeLong,
              },
              'distance': _currentDistance,
              'officeLocationId': officeLocationId,
              'nfcCardId': _scannedNfcId, // Store NFC card ID
            }, SetOptions(merge: true));

            if (_mounted) {
              setState(() {
                _isCheckedIn = true;
                _checkInTime = DateTime.now();
              });
              _showSnackBar('Checked in successfully! Have a great day!', isError: false);
            }
          } catch (e) {
            debugPrint('Error during check-in: $e');
            if (_mounted) {
              _showSnackBar('Failed to check in: $e', isError: true);
            }
          }
        },
      );
    }
  }

  Future<void> _checkOut() async {
    if (!_mounted) return;

    if (await _checkLocation()) {
      // Reset scanned NFC ID
      setState(() => _scannedNfcId = null);

      // Show NFC scan dialog
      _showNfcScanDialog(
        onSuccess: () async {
          try {
            final user = fa.FirebaseAuth.instance.currentUser;
            if (user == null) {
              _showSnackBar('User not authenticated', isError: true);
              return;
            }

            final todayDate = DateTime.now().toIso8601String().split('T')[0];
            final attendanceDocRef = FirebaseFirestore.instance
                .collection('attendance')
                .doc('${user.uid}_$todayDate');

            await attendanceDocRef.update({
              'checkOutTime': FieldValue.serverTimestamp(),
              'locationCheckOut': {
                'lat': _currentPosition?.latitude ?? officeLat,
                'long': _currentPosition?.longitude ?? officeLong,
              },
              'distanceCheckOut': _currentDistance,
              'nfcCardIdCheckOut': _scannedNfcId, // Store NFC card ID for checkout
            });

            if (_mounted) {
              setState(() {
                _isCheckedIn = false;
                _checkOutTime = DateTime.now();
                _checkoutRequestStatus = null;
              });
              _showSnackBar('Checked out successfully! Please submit your daily report.', isError: false, duration: 4);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen()));
            }
          } catch (e) {
            debugPrint('Error during check-out: $e');
            if (_mounted) {
              _showSnackBar('Failed to check out: $e', isError: true);
            }
          }
        },
      );
    }
  }

  Future<void> _requestManagerCheckout() async {
    if (!_mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.role != 'employee') {
      _showSnackBar('Only employees can request manager checkout', isError: true);
      return;
    }

    if (_checkOutTime != null) {
      _showSnackBar('You have already checked out today', isError: true, duration: 4);
      return;
    }

    if (_checkoutRequestStatus != null && _checkoutRequestStatus!['status'] == 'pending') {
      _showSnackBar('Checkout request already pending', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        return;
      }

      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final attendanceId = '${user.uid}_$todayDate';
      final attendanceDocRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendanceId);

      // Fetch the attendance record to get check-in time
      final attendanceDoc = await attendanceDocRef.get();
      if (!attendanceDoc.exists) {
        if (_mounted) {
          _showSnackBar('No check-in record found for today', isError: true);
          setState(() => _isLoading = false);
        }
        return;
      }

      final attendanceData = attendanceDoc.data() as Map<String, dynamic>?;
      final checkInTime = attendanceData?['checkInTime'] as Timestamp?;
      if (checkInTime == null) {
        if (_mounted) {
          _showSnackBar('No check-in time recorded for today', isError: true);
          setState(() => _isLoading = false);
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final officeLocationId = userData?['officeLocationId'];
      final managerId = userData?['managerId'] ?? '';

      // Write to checkout_requests with checkInTime
      await FirebaseFirestore.instance.collection('checkout_requests').doc('${user.uid}_$todayDate').set({
        'userId': user.uid,
        'attendanceId': attendanceId,
        'date': todayDate,
        'status': 'pending',
        'officeLocationId': officeLocationId,
        'requestTime': FieldValue.serverTimestamp(),
        'managerId': managerId,
        'distance': _currentDistance ?? 0.0,
        'location': {
          'lat': _currentPosition?.latitude ?? 0.0,
          'long': _currentPosition?.longitude ?? 0.0,
        },
        'checkInTime': checkInTime, // Ensure checkInTime is included
      });

      await _checkCheckoutRequestStatus();
      if (_mounted) {
        _showSnackBar('Checkout request submitted successfully with check-in time', isError: false);
      }
    } catch (e) {
      debugPrint('Error requesting manager checkout: $e');
      if (_mounted) {
        _showSnackBar('Failed to request manager checkout: $e', isError: true);
      }
    } finally {
      if (_mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshAttendanceStatus() async {
    if (!_mounted) return;

    setState(() {
      _isLoading = true;
      _isLocationLoading = true;
      _isOfficeDataLoading = true;
    });

    await Future.wait([
      _checkTodayAttendanceStatus(),
      _loadUserOfficeLocation(),
      _checkCurrentLocation(),
      _checkCheckoutRequestStatus(),
    ]);

    if (_mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false, int duration = 3}) {
    if (!_mounted) return;

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
        duration: Duration(seconds: duration),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildLocationCard() {
    bool isWithinRange = _currentDistance != null &&
        radius != null &&
        _currentDistance! <= radius!;
    bool isDataLoaded = !_isLocationLoading && !_isOfficeDataLoading;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDataLoaded
              ? (isWithinRange
              ? [Colors.green[50]!, Colors.green[100]!]
              : [Colors.orange[50]!, Colors.orange[100]!])
              : [Colors.grey[50]!, Colors.grey[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDataLoaded
                        ? (isWithinRange ? Colors.green[600] : Colors.orange[600])
                        : Colors.grey[400],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        isDataLoaded
                            ? (isWithinRange ? 'You\'re at the office' : 'Outside office range')
                            : 'Checking location...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            if (_isOfficeDataLoading) ...[
              _buildLoadingRow(Icons.business, 'Loading office details...'),
              SizedBox(height: 12),
            ] else if (officeName != null) ...[
              _buildInfoRow(Icons.business, 'Office', officeName!),
              SizedBox(height: 12),
            ],
            if (_isLocationLoading) ...[
              _buildLoadingRow(Icons.location_searching, 'Fetching your location...'),
              SizedBox(height: 12),
            ] else if (_currentDistance != null && radius != null) ...[
              _buildInfoRow(
                Icons.straighten,
                'Distance',
                '${_currentDistance!.toInt()}m from office',
              ),
              SizedBox(height: 12),
              _buildInfoRow(
                Icons.radio_button_unchecked,
                'Required Range',
                'Within ${radius!.toInt()}m',
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isWithinRange ? Colors.green[600] : Colors.orange[600],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isWithinRange ? Icons.check_circle : Icons.warning,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      isWithinRange ? 'Within Range' : 'Outside Range',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_checkInTime != null || _checkOutTime != null || _checkoutRequestStatus != null) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (_checkInTime != null)
                      _buildInfoRow(
                        Icons.login,
                        'Check-in Time',
                        '${_checkInTime!.hour.toString().padLeft(2, '0')}:${_checkInTime!.minute.toString().padLeft(2, '0')}',
                      ),
                    if (_checkInTime != null && _checkOutTime != null)
                      SizedBox(height: 8),
                    if (_checkOutTime != null)
                      _buildInfoRow(
                        Icons.logout,
                        'Check-out Time',
                        '${_checkOutTime!.hour.toString().padLeft(2, '0')}:${_checkOutTime!.minute.toString().padLeft(2, '0')}',
                      ),
                    if (_checkoutRequestStatus != null && _checkOutTime == null) ...[
                      if (_checkInTime != null) SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.pending_actions,
                        'Checkout Request',
                        _checkoutRequestStatus!['status'] == 'pending'
                            ? 'Pending Manager Approval'
                            : _checkoutRequestStatus!['status'] == 'approved'
                            ? 'Approved by Manager'
                            : 'Declined by Manager',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingRow(IconData icon, String message) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        SizedBox(width: 12),
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    bool isLoading = false,
  }) {
    bool isDisabled = _isLocationLoading || _isOfficeDataLoading || onPressed == null;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: double.infinity,
      height: 60,
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: ElevatedButton(
        onPressed: isLoading || isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDisabled ? Colors.grey[300] : color,
          foregroundColor: isDisabled ? Colors.grey[600] : Colors.white,
          elevation: (!isDisabled && onPressed != null) ? 8 : 2,
          shadowColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
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
            Text('Processing...', style: TextStyle(fontSize: 16)),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24),
            SizedBox(width: 12),
            Text(
              isDisabled && (_isLocationLoading || _isOfficeDataLoading)
                  ? 'Loading...'
                  : label,
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

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    bool isAttendanceCompleted = _checkOutTime != null;
    bool isEmployee = authProvider.role == 'employee';
    bool hasPendingRequest = _checkoutRequestStatus != null && _checkoutRequestStatus!['status'] == 'pending';
    bool isRequestDeclined = _checkoutRequestStatus != null && _checkoutRequestStatus!['status'] == 'declined';
    bool isRequestApproved = _checkoutRequestStatus != null && _checkoutRequestStatus!['status'] == 'approved';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Attendance Tracker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.refresh, color: Colors.blue[600]),
              ),
              onPressed: _refreshAttendanceStatus,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              SizedBox(height: 20),
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: _isCheckedIn
                                ? [Colors.green[300]!, Colors.green[600]!]
                                : [Colors.blue[300]!, Colors.blue[600]!],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isCheckedIn ? Colors.green : Colors.blue).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isCheckedIn ? Icons.work : Icons.work_outline,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                      if (_isLoading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.1),
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                margin: EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      isAttendanceCompleted
                          ? 'Attendance Completed Today'
                          : _isCheckedIn
                          ? 'You\'re Checked In!'
                          : 'Ready to Check In?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      isAttendanceCompleted
                          ? 'You have already checked in and out today'
                          : _isCheckedIn
                          ? 'Have a productive day at work!'
                          : (_isLocationLoading || _isOfficeDataLoading)
                          ? 'Setting up your attendance...'
                          : 'Make sure you\'re within office premises',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 30),
              _buildLocationCard(),
              SizedBox(height: 30),
              _buildAttendanceButton(
                label: 'Check In',
                icon: Icons.login,
                onPressed: isAttendanceCompleted || _isCheckedIn ? null : _checkIn,
                color: Colors.green[600]!,
                isLoading: _isLoading,
              ),
              _buildAttendanceButton(
                label: 'Check Out',
                icon: Icons.logout,
                onPressed: isAttendanceCompleted || !_isCheckedIn || hasPendingRequest || isRequestApproved ? null : _checkOut,
                color: Colors.red[600]!,
                isLoading: _isLoading,
              ),
              if (isEmployee && _isCheckedIn && !isAttendanceCompleted && !hasPendingRequest && !isRequestApproved)
                _buildAttendanceButton(
                  label: isRequestDeclined ? 'Retry Manager Request' : 'Request Manager for Checkout',
                  icon: Icons.pending_actions,
                  onPressed: _requestManagerCheckout,
                  color: Colors.blue[600]!,
                  isLoading: _isLoading,
                ),
              SizedBox(height: 20),
              Container(
                margin: EdgeInsets.symmetric(horizontal: 20),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule, color: Colors.grey[600]),
                    SizedBox(width: 8),
                    StreamBuilder(
                      stream: Stream.periodic(Duration(seconds: 1)),
                      builder: (context, snapshot) {
                        return Text(
                          DateTime.now().toString().substring(11, 19),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to debug NFC tag structure
  void _debugNfcTag(NfcTag tag) {
    debugPrint('=== NFC TAG DEBUG ===');
    debugPrint('Tag data keys: ${tag.data.keys}');

    tag.data.forEach((key, value) {
      debugPrint('$key: $value');

      if (key == 'ndef' && value != null) {
        debugPrint('  NDEF details: $value');
        if (value['cachedMessage'] != null) {
          debugPrint('  Cached message: ${value['cachedMessage']}');
          if (value['cachedMessage']['records'] != null) {
            final records = value['cachedMessage']['records'] as List;
            for (int i = 0; i < records.length; i++) {
              debugPrint('  Record $i: ${records[i]}');
              if (records[i]['payload'] != null) {
                final payload = records[i]['payload'] as List<int>;
                debugPrint('  Payload bytes: $payload');
                debugPrint('  Payload string: ${String.fromCharCodes(payload)}');
                debugPrint('  Payload hex: ${payload.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
              }
            }
          }
        }
      }
    });
    debugPrint('=== END DEBUG ===');
  }
}
