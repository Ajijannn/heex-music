import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.argobeats.music.channel.audio',
    androidNotificationChannelName: 'HEX Playback',
    androidNotificationOngoing: true,
  );
  runApp(const HexAppApp());
}

class TrackItem {
  final String id;
  final String title;
  final String artist;
  String url;
  final String artworkUrl;
  bool isLocal;
  bool isFullTrack;
  int durationSeconds;

  TrackItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    required this.artworkUrl,
    required this.isLocal,
    required this.isFullTrack,
    this.durationSeconds = 210,
  });
}

class HexAppApp extends StatelessWidget {
  const HexAppApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HEEX.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08090D),
        primaryColor: const Color(0xFFFFFFFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          secondary: Color(0xFFFF4D6D),
          surface: Color(0xFF12141C),
        ),
      ),
      home: const ArgoHomeScreen(),
    );
  }
}

class ArgoHomeScreen extends StatefulWidget {
  const ArgoHomeScreen({super.key});

  @override
  State<ArgoHomeScreen> createState() => _ArgoHomeScreenState();
}

class _ArgoHomeScreenState extends State<ArgoHomeScreen> {
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _searchCtrl = TextEditingController();

  int _navIndex = 1; // Default langsung ke tab Explore untuk Native APK
  String _categoryFilter = 'all'; // 'all' | 'full' | 'preview' | 'local' | 'liked'
  String _vibe = 'obsidian'; // 'obsidian' | 'crimson' | 'charcoal'
  bool _isRendering = false;
  String _renderingTitle = '';
  double _renderProgress = 0.0;

  final Set<String> _likedIds = {};
  final List<TrackItem> _queue = [];
  TrackItem? _currentTrack;

  final List<TrackItem> _tracks = [
    TrackItem(
      id: 'full-1',
      title: 'Midnight Study Lo-Fi',
      artist: 'HEEX. Studio',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      artworkUrl: '',
      isLocal: false,
      isFullTrack: true,
      durationSeconds: 192,
    ),
    TrackItem(
      id: 'full-2',
      title: 'Bandung Rainy Breeze',
      artist: 'Pasundan Chill Ensemble',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      artworkUrl: '',
      isLocal: false,
      isFullTrack: true,
      durationSeconds: 204,
    ),
    TrackItem(
      id: 'full-3',
      title: 'Deep Focus Cognitiva',
      artist: 'Synapse Ambient Lab',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      artworkUrl: '',
      isLocal: false,
      isFullTrack: true,
      durationSeconds: 188,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchOnline('Hindia Bernadya Tulus');
  }

  @override
  void dispose() {
    _player.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get _bgColor {
    if (_vibe == 'crimson') return const Color(0xFF120406);
    if (_vibe == 'charcoal') return const Color(0xFF0B0B0C);
    return const Color(0xFF08090D);
  }

  List<TrackItem> get _filteredTracks {
    return _tracks.where((t) {
      if (_categoryFilter == 'full') return t.isFullTrack || t.isLocal;
      if (_categoryFilter == 'preview') return !t.isFullTrack && !t.isLocal;
      if (_categoryFilter == 'local') return t.isLocal;
      if (_categoryFilter == 'liked') return _likedIds.contains(t.id);
      return true;
    }).toList();
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s < 10 ? '0$s' : '$s'}';
  }

  Future<void> _searchOnline(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final uri = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&country=ID&media=music&entity=song&limit=20',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List results = data['results'] ?? [];
        setState(() {
          for (final item in results) {
            final preview = item['previewUrl']?.toString() ?? '';
            if (preview.isEmpty) continue;
            final id = 'itunes-${item['trackId']}';
            if (_tracks.any((t) => t.id == id)) continue;
            _tracks.add(
              TrackItem(
                id: id,
                title: item['trackName']?.toString() ?? 'Track',
                artist: item['artistName']?.toString() ?? 'Artist',
                url: preview,
                artworkUrl: (item['artworkUrl100']?.toString() ?? '')
                    .replaceAll('100x100bb', '300x300bb'),
                isLocal: false,
                isFullTrack: false,
                durationSeconds: 30,
              ),
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _renderAndCacheFullAudio(TrackItem track) async {
    if (track.isFullTrack || track.isLocal) {
      await _playTrack(track);
      return;
    }
    setState(() {
      _isRendering = true;
      _renderingTitle = track.title;
      _renderProgress = 0.25;
    });

    final yt = YoutubeExplode();
    try {
      final results = await yt.search.search('${track.artist} ${track.title} official audio');
      if (results.isNotEmpty) {
        final video = results.first;
        setState(() => _renderProgress = 0.6);
        final manifest = await yt.videos.streamsClient.getManifest(video.id);
        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        final stream = yt.videos.streamsClient.get(audioStreamInfo);

        final dir = await getApplicationDocumentsDirectory();
        final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        final file = File('${dir.path}/argo_$safeId.m4a');
        final output = file.openWrite();
        await stream.pipe(output);
        await output.flush();
        await output.close();

        setState(() {
          track.url = file.path;
          track.isLocal = true;
          track.isFullTrack = true;
          track.durationSeconds = video.duration?.inSeconds ?? 210;
          _renderProgress = 1.0;
          _isRendering = false;
        });
        await _playTrack(track);
      } else {
        setState(() => _isRendering = false);
      }
    } catch (_) {
      setState(() => _isRendering = false);
    } finally {
      yt.close();
    }
  }

  Future<void> _pickLocalFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return;
    TrackItem? firstAdded;
    setState(() {
      for (final f in result.files) {
        if (f.path == null) continue;
        final item = TrackItem(
          id: 'local-${DateTime.now().millisecondsSinceEpoch}-${f.name}',
          title: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
          artist: 'Offline Audio',
          url: f.path!,
          artworkUrl: '',
          isLocal: true,
          isFullTrack: true,
          durationSeconds: 210,
        );
        _tracks.insert(0, item);
        firstAdded ??= item;
      }
    });
    if (firstAdded != null) {
      await _playTrack(firstAdded!);
    }
  }

  Future<void> _playTrack(TrackItem track) async {
    setState(() => _currentTrack = track);
    final mediaItem = MediaItem(
      id: track.id,
      album: track.isFullTrack ? 'HEEX. Full Audio' : 'HEEX. Preview',
      title: track.title,
      artist: track.artist,
      artUri: track.artworkUrl.isNotEmpty ? Uri.parse(track.artworkUrl) : null,
    );
    final source = track.isLocal
        ? AudioSource.file(track.url, tag: mediaItem)
        : AudioSource.uri(Uri.parse(track.url), tag: mediaItem);
    await _player.setAudioSource(source);
    await _player.play();
  }

  Widget _glassBox({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
    double radius = 18,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCategoryPills() {
    final pills = [
      {'id': 'all', 'label': 'Semua'},
      {'id': 'full', 'label': 'Lagu Full'},
      {'id': 'preview', 'label': 'Preview'},
      {'id': 'local', 'label': 'Offline'},
      {'id': 'liked', 'label': 'Disukai'},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: pills.map((p) {
          final active = _categoryFilter == p['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _categoryFilter = p['id']!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? Colors.white : Colors.white.withOpacity(0.14),
                  ),
                ),
                child: Text(
                  p['label']!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? const Color(0xFF090A0F) : Colors.white70,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTrackRow(TrackItem track, int index) {
    final isCurrent = _currentTrack?.id == track.id;
    final isFull = track.isFullTrack || track.isLocal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _glassBox(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        radius: 15,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? const Color(0xFFFF4D6D) : Colors.white38,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _playTrack(track),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isFull
                                ? const Color(0xFF34D399).withOpacity(0.16)
                                : const Color(0xFFFBBF24).withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isFull ? 'FULL' : '30s',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isFull
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFFFBBF24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${track.artist} • ${_formatDuration(track.durationSeconds)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Colors.white60),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!isFull)
              TextButton(
                onPressed: () => _renderAndCacheFullAudio(track),
                child: const Text(
                  '⚡ Render',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            IconButton(
              icon: Icon(
                _likedIds.contains(track.id) ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: _likedIds.contains(track.id) ? const Color(0xFFFF4D6D) : Colors.white54,
              ),
              onPressed: () {
                setState(() {
                  if (_likedIds.contains(track.id)) {
                    _likedIds.remove(track.id);
                  } else {
                    _likedIds.add(track.id);
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredTracks;
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Clean Header (No subtitle clutter, no settings button overlap)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'HEEX',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                            ),
                          ),
                          Text(
                            '.',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFF4D6D),
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF090A0F),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: _pickLocalFiles,
                        child: const Text('+ Impor', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildCategoryPills(),
                ],
              ),
            ),

            if (_isRendering)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: _glassBox(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚡ Merender $_renderingTitle...', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: _renderProgress, color: Colors.white),
                    ],
                  ),
                ),
              ),

            Expanded(
              child: _navIndex == 4
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text('Settings.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        _glassBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Appearance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => setState(() => _vibe = 'obsidian'),
                                      child: const Text('Obsidian'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => setState(() => _vibe = 'crimson'),
                                      child: const Text('Crimson'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => setState(() => _vibe = 'charcoal'),
                                      child: const Text('Charcoal'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      children: [
                        if (_navIndex == 1) ...[
                          TextField(
                            controller: _searchCtrl,
                            onSubmitted: _searchOnline,
                            decoration: InputDecoration(
                              hintText: 'Cari lagu atau artis...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.07),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          const Text('Good Music
Today.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                          const SizedBox(height: 12),
                          _glassBox(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Feel the
Music.', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
                                FloatingActionButton.small(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF090A0F),
                                  onPressed: () {
                                    if (list.isNotEmpty) _playTrack(list.first);
                                  },
                                  child: const Icon(Icons.play_arrow),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        ...List.generate(list.length, (i) => _buildTrackRow(list[i], i)),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        backgroundColor: const Color(0xFF0A0B10),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}
