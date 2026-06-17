import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'payment_service.dart';
import 'state.dart';
import 'models.dart';

/// A premium, beautiful payment screen integrating Stripe.
class StripePaymentScreen extends StatefulWidget {
  final AppState app;

  const StripePaymentScreen({super.key, required this.app});

  @override
  State<StripePaymentScreen> createState() => _StripePaymentScreenState();
}

class _StripePaymentScreenState extends State<StripePaymentScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  String? _launchedUrl;
  String? _sessionId;
  bool _isVerifying = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _startStripeCheckout() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _launchedUrl = null;
      _sessionId = null;
    });

    try {
      // Fetch session from backend with user's email
      final stripeResponse = await PaymentService.createCheckoutSession(
        userEmail: widget.app.savedEmail,
      );

      if (stripeResponse.isRedirect && stripeResponse.url != null) {
        final uri = Uri.parse(stripeResponse.url!);
        _launchedUrl = stripeResponse.url;
        _sessionId = stripeResponse.sessionId;

        // Launch external browser/application for Stripe Redirect Checkout
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched) {
          throw Exception('Could not launch Stripe Checkout page.');
        }

        // Show verification screen state
        setState(() {
          _isLoading = false;
        });
      } else if (stripeResponse.clientSecret != null) {
        _sessionId = stripeResponse.sessionId;
        // Handle Stripe SDK client_secret payment sheet flow
        setState(() {
          _isLoading = false;
        });
        await _handleStripeSdkFlow(stripeResponse.clientSecret!);
      } else {
        throw Exception('Server returned empty Stripe session credentials.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
      _animController.reset();
      _animController.forward();
    }
  }

  Future<void> _handleStripeSdkFlow(String clientSecret) async {
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Pathway App',
          style: ThemeMode.dark,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      _handlePaymentSuccess('SDK Payment Successful');
    } catch (e) {
      setState(() {
        if (e is StripeException) {
          _errorMessage = 'Payment cancelled: ${e.error.localizedMessage}';
        } else {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        }
      });
      _animController.reset();
      _animController.forward();
    }
  }

  void _verifyCheckoutSession() async {
    setState(() {
      _isVerifying = true;
    });

    final verification = await PaymentService.verifyPayment(_sessionId);

    if (mounted) {
      setState(() {
        _isVerifying = false;
      });
      if (verification.isPaid) {
        _handlePaymentSuccess('Redirect Checkout Successful');
      } else {
        setState(() {
          _errorMessage = verification.error ?? 'Payment verification failed. Please try again.';
        });
        _animController.reset();
        _animController.forward();
      }
    }
  }

  void _handlePaymentSuccess(String source) {
    widget.app.setPlan(Plan.premium); // Upgrade the user to premium plan
    setState(() {
      _successMessage = 'Payment Successful! Thank you for subscribing.';
      _errorMessage = null;
      _launchedUrl = null;
    });
    _animController.reset();
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark mode background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Stripe Payment',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _successMessage != null
              ? _buildSuccessView()
              : _errorMessage != null
                  ? _buildErrorView()
                  : _launchedUrl != null
                      ? _buildRedirectPendingView()
                      : _buildInitiateView(),
        ),
      ),
    );
  }

  Widget _buildInitiateView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          // Beautiful Header Gradient Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5), Color(0xFF312E81)],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PREMIUM UPGRADE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Pathway Premium Pass',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Unlock priority PSC appointment bookings, 24/7 personalized immigration assistant support, and verified housing matches.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '\$24.99',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '/ month',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          // Features List
          _buildFeatureRow(Icons.check_circle_outline, 'Priority IIN booking queue slots'),
          _buildFeatureRow(Icons.check_circle_outline, 'Unlimited AI Assistant questions'),
          _buildFeatureRow(Icons.check_circle_outline, 'Pre-verified dorms & apartment access'),
          _buildFeatureRow(Icons.check_circle_outline, 'Document translation help'),
          const SizedBox(height: 50),
          // Pay Button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA6),
                foregroundColor: Colors.black,
                shadowColor: const Color(0xFF00BFA6).withOpacity(0.4),
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _isLoading ? null : _startStripeCheckout,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Pay with Stripe',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 14, color: Colors.white38),
              SizedBox(width: 6),
              Text(
                'Secured & Encrypted by Stripe',
                style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRedirectPendingView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.open_in_browser_rounded,
              color: Color(0xFF6366F1),
              size: 40,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Stripe Checkout Opened',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'We have opened Stripe secure payment page in your browser. Please complete your subscription purchase there.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          if (_isVerifying)
            const Column(
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA6)),
                ),
                SizedBox(height: 16),
                Text(
                  'Verifying payment status...',
                  style: TextStyle(color: Color(0xFF00BFA6), fontWeight: FontWeight.bold),
                )
              ],
            )
          else
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA6),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _verifyCheckoutSession,
                    child: const Text(
                      'I have completed the payment',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _launchedUrl = null;
                    });
                  },
                  child: const Text(
                    'Cancel and Go Back',
                    style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            )
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Payment Successful',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _successMessage ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Get Started',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Payment Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An error occurred during Stripe Checkout.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA6),
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _startStripeCheckout,
                    child: const Text(
                      'Try Again',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00BFA6), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
