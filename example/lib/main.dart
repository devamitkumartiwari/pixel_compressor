import 'package:flutter/material.dart';

import 'pages/batch_page.dart';
import 'pages/cache_page.dart';
import 'pages/capabilities_page.dart';
import 'pages/image_page.dart';
import 'pages/metadata_page.dart';
import 'pages/thumbnails_page.dart';
import 'pages/video_page.dart';

void main() {
  runApp(const PixelCompressorExampleApp());
}

class PixelCompressorExampleApp extends StatelessWidget {
  const PixelCompressorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pixel_compressor demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const _HomeShell(),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  static final _destinations = [
    _Destination('Image', Icons.image_outlined, (_) => const ImagePage()),
    _Destination('Video', Icons.videocam_outlined, (_) => const VideoPage()),
    _Destination('Batch', Icons.collections_outlined, (_) => const BatchPage()),
    _Destination(
      'Thumbnails',
      Icons.grid_view_outlined,
      (_) => const ThumbnailsPage(),
    ),
    _Destination('Metadata', Icons.info_outline, (_) => const MetadataPage()),
    _Destination('Capabilities', Icons.memory, (_) => const CapabilitiesPage()),
    _Destination('Cache', Icons.folder_outlined, (_) => const CachePage()),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final destination = _destinations[_selected];

    return Scaffold(
      appBar: AppBar(title: Text('pixel_compressor — ${destination.label}')),
      drawer: NavigationDrawer(
        selectedIndex: _selected,
        onDestinationSelected: (index) {
          setState(() => _selected = index);
          Navigator.of(context).pop();
        },
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 8),
            child: Text(
              'pixel_compressor',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          for (final d in _destinations)
            NavigationDrawerDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      ),
      body: destination.builder(context),
    );
  }
}
