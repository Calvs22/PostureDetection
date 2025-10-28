import 'package:flutter/material.dart';
import '../main.dart'; // Import to access globalSupabaseService

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Helper widget to style the text fields for the dark background
  Widget _buildAuthTextField({
    required TextEditingController controller,
    required String labelText,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool isVisible = false,
    required void Function(bool) toggleVisibility,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white), // Input text color
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: const TextStyle(color: Colors.white70), // Label color
        filled: true,
        fillColor: Colors.white.withOpacity(0.1), // Slightly transparent background
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white54),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white70,
                ),
                onPressed: () => toggleVisibility(!isVisible),
              )
            : null,
      ),
    );
  }

  Future<void> _handleSignUp() async {
    // 1. Basic validation: Check if passwords match
    if (_passwordController.text.trim() != _confirmPasswordController.text.trim()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration Failed: Passwords do not match.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 2. Call Supabase sign-up
      await globalSupabaseService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        // 3. Success: Show message and pop to Login Screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please sign in to continue.'),
            backgroundColor: Colors.green,
          ),
        );
        // Pop back to the LoginScreen
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration Failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Sign Up', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent, // Transparent AppBar
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white), // Back button color
      ),
      body: Stack(
        children: <Widget>[
          // 1. Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/bg.jpeg', // <--- Background image added here
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.4), // Dark overlay for contrast
              colorBlendMode: BlendMode.darken,
            ),
          ),
          
          // 2. Sign Up Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // Email Field
                    _buildAuthTextField(
                      controller: _emailController,
                      labelText: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      toggleVisibility: (_) {}, // Not applicable for email
                    ),
                    const SizedBox(height: 16),
                    
                    // Password Field
                    _buildAuthTextField(
                      controller: _passwordController,
                      labelText: 'Password',
                      obscureText: !_isPasswordVisible,
                      isPassword: true,
                      isVisible: _isPasswordVisible,
                      toggleVisibility: (val) {
                        setState(() {
                          _isPasswordVisible = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Confirm Password Field
                    _buildAuthTextField(
                      controller: _confirmPasswordController,
                      labelText: 'Confirm Password',
                      obscureText: !_isConfirmPasswordVisible,
                      isPassword: true,
                      isVisible: _isConfirmPasswordVisible,
                      toggleVisibility: (val) {
                        setState(() {
                          _isConfirmPasswordVisible = val;
                        });
                      },
                    ),
                    const SizedBox(height: 32),
                    
                    // Sign Up Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600], // Primary button color
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Sign Up'),
                    ),
                    const SizedBox(height: 20),
                    
                    // Login Link
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(), // Go back to Login
                      child: const Text(
                        'Already have an account? Log In',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}