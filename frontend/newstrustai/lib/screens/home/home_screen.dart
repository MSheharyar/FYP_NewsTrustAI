import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../analytics_screen.dart';
import '../history_screen.dart';
import '../chatbot_screen.dart';
import '../profile_screen.dart';
import 'home_tab.dart';

class HomeScreen extends StatefulWidget {
  final String firstName;
  const HomeScreen({super.key, required this.firstName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeTab(firstName: widget.firstName),
      const AnalyticsScreen(),
      const HistoryScreen(),
      const ChatbotScreen(),
      const ProfileScreen(),
    ];
  }

  void _onNavTap(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack( // Using IndexedStack preserves state when switching tabs
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onNavTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.blue[700],
          unselectedItemColor: Colors.grey[400],
          showUnselectedLabels: true,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.barChart3), label: 'Analytics'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.history), label: 'History'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.bot), label: 'Chatbot'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}