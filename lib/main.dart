import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'auth_provider.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'forgot_password_screen.dart';
import 'notification_scheduler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Start the notification scheduler
  NotificationScheduler.startScheduler();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Talnio',
        theme: appTheme(),
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) =>
          auth.isAuthenticated ? PermissionWrapper() : LoginScreen(),
        ),
      ),
    );
  }
}

// Permission wrapper remains the same
class PermissionWrapper extends StatefulWidget {
  @override
  _PermissionWrapperState createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _isCheckingPermissions = true;
  bool _permissionsGranted = false;
  String _permissionStatus = 'Checking permissions...';

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    try {
      setState(() {
        _permissionStatus = 'Checking location services...';
      });

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _permissionStatus = 'Location services are disabled. Please enable them in settings.';
          _isCheckingPermissions = false;
        });
        return;
      }

      setState(() {
        _permissionStatus = 'Checking location permissions...';
      });

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        setState(() {
          _permissionStatus = 'Requesting location permission...';
        });

        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _permissionStatus = 'Location permission denied. Please grant permission to use attendance features.';
            _isCheckingPermissions = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _permissionStatus = 'Location permissions are permanently denied. Please enable them in app settings.';
          _isCheckingPermissions = false;
        });
        return;
      }

      setState(() {
        _permissionStatus = 'Testing location access...';
      });

      try {
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        );

        setState(() {
          _permissionsGranted = true;
          _isCheckingPermissions = false;
          _permissionStatus = 'All permissions granted!';
        });
      } catch (e) {
        setState(() {
          _permissionStatus = 'Failed to access location: ${e.toString()}';
          _isCheckingPermissions = false;
        });
      }
    } catch (e) {
      setState(() {
        _permissionStatus = 'Error checking permissions: ${e.toString()}';
        _isCheckingPermissions = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionsGranted) {
      return HomeScreen();
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.1),
              Theme.of(context).primaryColor.withOpacity(0.05),
              Colors.white,
              Colors.blue.shade50.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).primaryColor.withOpacity(0.3),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.location_on,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 40),
                  Text(
                    'Setting Up Permissions',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'We need location access to track your attendance accurately',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 40),
                  if (_isCheckingPermissions) ...[
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor,
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _permissionsGranted
                          ? Colors.green.shade50
                          : _isCheckingPermissions
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _permissionsGranted
                            ? Colors.green.shade200
                            : _isCheckingPermissions
                            ? Colors.blue.shade200
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _permissionsGranted
                              ? Icons.check_circle
                              : _isCheckingPermissions
                              ? Icons.info_outline
                              : Icons.warning_amber,
                          color: _permissionsGranted
                              ? Colors.green.shade600
                              : _isCheckingPermissions
                              ? Colors.blue.shade600
                              : Colors.orange.shade600,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _permissionStatus,
                            style: TextStyle(
                              color: _permissionsGranted
                                  ? Colors.green.shade700
                                  : _isCheckingPermissions
                                  ? Colors.blue.shade700
                                  : Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isCheckingPermissions && !_permissionsGranted) ...[
                    SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: _checkAndRequestPermissions,
                      icon: Icon(Icons.refresh),
                      label: Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        Geolocator.openAppSettings();
                      },
                      icon: Icon(Icons.settings),
                      label: Text('Open Settings'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Updated LoginScreen with inline error display
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage; // Added for inline error display

  late AnimationController _animationController;
  late AnimationController _pulseController;
  late AnimationController _floatingController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _floatingAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: Duration(milliseconds: 1200),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );

    _floatingController = AnimationController(
      duration: Duration(milliseconds: 3000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Interval(0.2, 0.8, curve: Curves.elasticOut)));

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Interval(0.0, 0.6, curve: Curves.elasticOut)),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _floatingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );

    _animationController.forward();
    _pulseController.repeat(reverse: true);
    _floatingController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _floatingController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email';
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

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null; // Clear any previous error
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      try {
        await authProvider.signIn(
          emailController.text.trim(),
          passwordController.text,
          context,
          onError: (String errorMessage) {
            // Handle error inline instead of SnackBar
            setState(() {
              _errorMessage = errorMessage;
            });
          },
        );
      } catch (e) {
        setState(() {
          _errorMessage = 'Login failed. Please try again.';
        });
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor.withOpacity(0.1),
              theme.primaryColor.withOpacity(0.05),
              Colors.white,
              Colors.blue.shade50.withOpacity(0.3),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Floating background elements
            AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Positioned(
                  top: 100 + (_floatingAnimation.value * 20),
                  right: 50,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Positioned(
                  bottom: 200 + (_floatingAnimation.value * -15),
                  left: 30,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade200.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                );
              },
            ),

            // Main content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 400),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Enhanced App Logo
                                AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _pulseAnimation.value,
                                      child: Container(
                                        height: 120,
                                        width: 120,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              theme.primaryColor,
                                              theme.primaryColor.withOpacity(0.8),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.primaryColor.withOpacity(0.4),
                                              blurRadius: 25,
                                              offset: Offset(0, 10),
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.business_center_rounded,
                                          size: 60,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                SizedBox(height: 40),

                                // Enhanced Welcome Text
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: [theme.primaryColor, Colors.blue.shade700],
                                  ).createShader(bounds),
                                  child: Text(
                                    'Welcome to Talnio',
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),

                                SizedBox(height: 8),

                                Text(
                                  'Your productivity companion',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),

                                SizedBox(height: 48),

                                // Enhanced Email Field
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: TextFormField(
                                    controller: emailController,
                                    validator: _validateEmail,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: 'Email Address',
                                      hintText: 'Enter your email',
                                      prefixIcon: Container(
                                        margin: EdgeInsets.all(12),
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme.primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.email_outlined, color: theme.primaryColor, size: 20),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: theme.primaryColor, width: 2),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: Colors.red.shade400, width: 1),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                                    ),
                                  ),
                                ),

                                SizedBox(height: 20),

                                // Enhanced Password Field
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: TextFormField(
                                    controller: passwordController,
                                    validator: _validatePassword,
                                    obscureText: !_isPasswordVisible,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _handleLogin(),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      hintText: 'Enter your password',
                                      prefixIcon: Container(
                                        margin: EdgeInsets.all(12),
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme.primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.lock_outline, color: theme.primaryColor, size: 20),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Container(
                                          padding: EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            _isPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                            color: Colors.grey.shade600,
                                            size: 20,
                                          ),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isPasswordVisible = !_isPasswordVisible;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: theme.primaryColor, width: 2),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: Colors.red.shade400, width: 1),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                                    ),
                                  ),
                                ),

                                SizedBox(height: 16),

                                // Enhanced Forgot Password
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          pageBuilder: (context, animation, secondaryAnimation) => ForgotPasswordScreen(),
                                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                            return SlideTransition(
                                              position: Tween<Offset>(
                                                begin: Offset(1.0, 0.0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            );
                                          },
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: theme.primaryColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),

                                // Inline Error Message Display - Similar to Add Employee Screen
                                if (_errorMessage != null) ...[
                                  SizedBox(height: 16),
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

                                SizedBox(height: 32),

                                // Enhanced Login Button
                                Container(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.primaryColor.withOpacity(0.3),
                                        blurRadius: 15,
                                        offset: Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.primaryColor,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      disabledBackgroundColor: Colors.grey.shade300,
                                    ),
                                    child: _isLoading
                                        ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Text(
                                          'Signing In...',
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
                                        Icon(Icons.login_rounded, size: 22),
                                        SizedBox(width: 12),
                                        Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                SizedBox(height: 24),

                                // Additional features hint
                                Container(
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.blue.shade100),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Secure login with enterprise-grade encryption',
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
