import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';

void main() {
  runApp(const ScreenRecApp());
}

const _bg = Color(0xFF0A0A0F);
const _surface = Color(0xFF13131A);
const _card = Color(0xFF1C1C27);
const _accent = Color(0xFFFF3B5C);
const _accentGlow = Color(0x40FF3B5C);
const _textPrimary = Color(0xFFF0F0FF);
const _textSecondary = Color(0xFF8888AA);

class ScreenRecApp extends StatelessWidget {
  const ScreenRecApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScreenRec',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _surface,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

const _channel = MethodChannel('screen_recorder');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _isRecording = false;
  bool _isPreparing = false;
  String _audioSource = 'mic';
  int _selectedResIdx = 1;
  String _outputPath = '';
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  List<Map<String, dynamic>> _resolutions = [];
  Map<String, dynamic>? _screenMetrics;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _recordBtnCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _recordBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _loadScreenMetrics();
    _loadDefaultPath();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _recordBtnCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadScreenMetrics() async {
    try {
      final metrics = await _channel.invokeMapMethod<String, dynamic>('getScreenMetrics');
      if (metrics != null && mounted) {
        setState(() {
          _screenMetrics = metrics;
          _buildResolutionList(metrics['width'] as int, metrics['height'] as int);
        });
      }
    } catch (_) {
      _buildResolutionList(1080, 1920);
    }
  }

  void _buildResolutionList(int maxW, int maxH) {
    final all = [
      {'label': '480p', 'width': 854, 'height': 480},
      {'label': '720p', 'width': 1280, 'height': 720},
      {'label': '1080p', 'width': 1920, 'height': 1080},
      {'label': '1440p', 'width': 2560, 'height': 1440},
      {'label': '4K', 'width': 3840, 'height': 2160},
    ];
    final native = {'label': 'Nativa (${maxW}x$maxH)', 'width': maxW, 'height': maxH};
    final filtered = all
        .where((r) => (r['width'] as int) <= maxW && (r['height'] as int) <= maxH)
        .toList();
    final alreadyHasNative = filtered.any((r) => r['width'] == maxW && r['height'] == maxH);
    if (!alreadyHasNative) filtered.add(native);

    _resolutions = filtered;
    _selectedResIdx = _resolutions.length > 1 ? _resolutions.length - 2 : 0;
  }

  Future<void> _loadDefaultPath() async {
    final dir = await getExternalStorageDirectory();
    final folder = Directory('${dir?.path ?? '/sdcard'}/ScreenRecordings');
    if (!await folder.exists()) await folder.create(recursive: true);
    setState(() => _outputPath = folder.path);
  }

  String _generateFileName() {
    final now = DateTime.now();
    return '$_outputPath/rec_${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}.mp4';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<bool> _requestPermissions() async {
    final perms = [Permission.microphone, Permission.notification];
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted == false) {
        perms.add(Permission.storage);
      }
    }
    final statuses = await perms.request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _stopRecording();
      return;
    }
    setState(() => _isPreparing = true);

    try {
      await _requestPermissions();

      final projResult = await _channel.invokeMapMethod<String, dynamic>('requestMediaProjection');
      if (projResult == null || projResult['granted'] != true) {
        _showSnack('Permiso de captura de pantalla denegado');
        setState(() => _isPreparing = false);
        return;
      }

      final res = _resolutions[_selectedResIdx];
      final metrics = _screenMetrics;
      final dpi = metrics != null ? metrics['density'] as int : 320;
      final filePath = _generateFileName();

      await _channel.invokeMethod('startRecording', {
        'width': res['width'],
        'height': res['height'],
        'dpi': dpi,
        'audioSource': _audioSource,
        'outputPath': filePath,
      });

      setState(() {
        _isRecording = true;
        _isPreparing = false;
        _elapsed = Duration.zero;
      });
      _recordBtnCtrl.forward();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (e) {
      setState(() => _isPreparing = false);
      _showSnack('Error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    await _channel.invokeMethod('stopRecording');
    setState(() {
      _isRecording = false;
      _elapsed = Duration.zero;
    });
    _recordBtnCtrl.reverse();
    _showSnack('✓ Video guardado en $_outputPath');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _textPrimary)),
        backgroundColor: _card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
    return '${_pad(m)}:${_pad(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              _buildRecordButton(),
              const SizedBox(height: 32),
              _buildResolutionCard(),
              const SizedBox(height: 16),
              _buildAudioCard(),
              const SizedBox(height: 16),
              _buildOutputCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _accentGlow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.videocam_rounded, color: _accent, size: 22),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ScreenRec', style: TextStyle(
              color: _textPrimary, fontSize: 20,
              fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
            Text('Grabador de pantalla', style: TextStyle(
              color: _textSecondary, fontSize: 12,
            )),
          ],
        ),
        const Spacer(),
        if (_isRecording)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _accentGlow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulseDot(),
                const SizedBox(width: 6),
                Text(_formatDuration(_elapsed),
                    style: const TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecordButton() {
    return Center(
      child: GestureDetector(
        onTap: _isPreparing ? null : _toggleRecording,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) {
            final scale = _isRecording ? _pulseAnim.value : 1.0;
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _card,
              border: Border.all(
                color: _isRecording ? _accent : _textSecondary.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: _isRecording ? [
                BoxShadow(color: _accentGlow, blurRadius: 30, spreadRadius: 5),
              ] : [],
            ),
            child: _isPreparing
                ? const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _isRecording ? 28 : 48,
                        height: _isRecording ? 28 : 48,
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(_isRecording ? 6 : 24),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isRecording ? 'DETENER' : 'GRABAR',
                        style: TextStyle(
                          color: _isRecording ? _accent : _textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildResolutionCard() {
    return _Card(
      icon: Icons.hd_rounded,
      title: 'Resolución',
      child: _resolutions.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2))
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_resolutions.length, (i) {
                final r = _resolutions[i];
                final selected = i == _selectedResIdx;
                return GestureDetector(
                  onTap: _isRecording ? null : () => setState(() => _selectedResIdx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? _accentGlow : _surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? _accent : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      r['label'] as String,
                      style: TextStyle(
                        color: selected ? _accent : _textSecondary,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }),
            ),
    );
  }

  Widget _buildAudioCard() {
    final options = [
      {'id': 'mic', 'label': 'Micrófono', 'icon': Icons.mic_rounded},
      {'id': 'system', 'label': 'Sistema', 'icon': Icons.speaker_rounded},
      {'id': 'both', 'label': 'Ambos', 'icon': Icons.merge_rounded},
      {'id': 'none', 'label': 'Sin audio', 'icon': Icons.mic_off_rounded},
    ];
    return _Card(
      icon: Icons.headset_rounded,
      title: 'Fuente de audio',
      child: Row(
        children: options.map((opt) {
          final selected = _audioSource == opt['id'];
          return Expanded(
            child: GestureDetector(
              onTap: _isRecording ? null : () => setState(() => _audioSource = opt['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? _accentGlow : _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(opt['icon'] as IconData,
                        color: selected ? _accent : _textSecondary, size: 20),
                    const SizedBox(height: 4),
                    Text(opt['label'] as String,
                        style: TextStyle(
                          color: selected ? _accent : _textSecondary,
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOutputCard() {
    return _Card(
      icon: Icons.folder_rounded,
      title: 'Guardar en',
      child: Row(
        children: [
          Expanded(
            child: Text(
              _outputPath.isEmpty ? 'Cargando...' : _outputPath,
              style: const TextStyle(color: _textSecondary, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isRecording ? null : _pickFolder,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _accentGlow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent, width: 1),
              ),
              child: const Text('Cambiar',
                  style: TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null && mounted) {
        setState(() => _outputPath = '${dir.path}/ScreenRecordings');
        _showSnack('Carpeta: $_outputPath');
      }
    } catch (e) {
      _showSnack('No se pudo cambiar la carpeta');
    }
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: _isPreparing ? null : _toggleRecording,
      backgroundColor: _isRecording ? _accent : _card,
      elevation: _isRecording ? 8 : 4,
      child: Icon(
        _isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
        color: _isRecording ? Colors.white : _accent,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _Card({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _textSecondary, size: 16),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(
              color: _textSecondary, fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 1.2,
            )),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, x) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _accent.withValues(alpha: 0.5 + 0.5 * _ctrl.value),
        ),
      ),
    );
  }
}