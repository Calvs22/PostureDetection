import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// This screen is displayed when a user has signed up or logged in,
/// but their email address has not yet been confirmed via the link.
class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key});

  /// Handles resending the confirmation email using Supabase Auth.
  Future<void> _resendEmail(BuildContext context) async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Please log in again.')),
        );
      }
      return;
    }

    try {
      // Use the resend method for signup confirmation
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Confirmation email re-sent to $email!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend email: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Your Email')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 30),
              const Text(
                'Verify Your Account',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                'We sent a confirmation link to ${Supabase.instance.client.auth.currentUser?.email ?? 'your email'}. Please click the link to continue.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 50),
              ElevatedButton.icon(
                onPressed: () => _resendEmail(context),
                icon: const Icon(Icons.refresh),
                label: const Text('Resend Confirmation Email'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () async {
                  // Sign out. The AuthCheckWrapper will redirect the user to LoginScreen.
                  await Supabase.instance.client.auth.signOut();
                },
                child: const Text('Sign Out / Go Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
