import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'platform_page.dart';
import 'download_history_page.dart';

class DownloadsHome extends ConsumerWidget {
  const DownloadsHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Downloader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DownloadHistoryPage()),
              );
            },
            tooltip: 'Download Manager',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Platform',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _PlatformCard(
                    title: 'YouTube',
                    icon: Icons.play_arrow,
                    color: Colors.red,
                    onTap: () => _navigateToPlatform(context, 'YouTube'),
                  ),
                  _PlatformCard(
                    title: 'Instagram',
                    icon: Icons.camera_alt,
                    color: Colors.purple,
                    onTap: () => _navigateToPlatform(context, 'Instagram'),
                  ),
                  _PlatformCard(
                    title: 'Facebook',
                    icon: Icons.facebook,
                    color: Colors.blue,
                    onTap: () => _navigateToPlatform(context, 'Facebook'),
                  ),
                  _PlatformCard(
                    title: 'Terabox',
                    icon: Icons.cloud_download,
                    color: Colors.orange,
                    onTap: () => _navigateToPlatform(context, 'Terabox'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPlatform(BuildContext context, String platform) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlatformPage(platform: platform),
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PlatformCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
