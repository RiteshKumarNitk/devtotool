import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class DevicePage extends ConsumerWidget {
  const DevicePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(devicePerformanceProvider);
    final device = info['device'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Inspector'),
      ),
      body: device == null || device.isEmpty
          ? const Center(child: Text('Waiting for device data...'))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildInfoCard(
                  context,
                  title: 'User Agent',
                  value: device['userAgent']?.toString() ?? 'Unknown',
                  icon: Icons.perm_device_information,
                ),
                _buildInfoCard(
                  context,
                  title: 'Screen Size',
                  value: "${device['screenWidth']} x ${device['screenHeight']}",
                  icon: Icons.screenshot_monitor,
                ),
                _buildInfoCard(
                  context,
                  title: 'Pixel Ratio',
                  value: device['pixelRatio']?.toString() ?? 'Unknown',
                  icon: Icons.aspect_ratio,
                ),
                _buildInfoCard(
                  context,
                  title: 'Platform',
                  value: device['platform']?.toString() ?? 'Unknown',
                  icon: Icons.computer,
                ),
                _buildInfoCard(
                  context,
                  title: 'Language',
                  value: device['language']?.toString() ?? 'Unknown',
                  icon: Icons.language,
                ),
                _buildInfoCard(
                  context,
                  title: 'Timezone',
                  value: device['timezone']?.toString() ?? 'Unknown',
                  icon: Icons.access_time,
                ),
              ],
            ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {required String title, required String value, required IconData icon}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(value, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
