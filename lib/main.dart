import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  
  CameraDescription? backCamera;
  for (var camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.back) {
      backCamera = camera;
      break; 
    }
  }

  // Jika kamera belakang tidak ditemukan, pakai kamera yang ada
  final selectedCamera = backCamera ?? cameras.first; 

  runApp(MyApp(camera: selectedCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kamera Stabilizer',
      theme: ThemeData.dark(),
      home: CameraScreen(camera: camera),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  
  bool _isRecording = false;
  bool _isProcessing = false;
  String _statusText = "Siap merekam";

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium, 
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      XFile videoFile = await _controller.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _statusText = "Mulai menstabilkan video...";
        _isProcessing = true;
      });
      
      await _stabilizeVideo(videoFile.path);
      
    } else {
      await _controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _statusText = "Merekam... (Tangan jangan terlalu goyang)";
      });
    }
  }

  Future<void> _stabilizeVideo(String inputPath) async {
    try {
      Directory tempDir = await getTemporaryDirectory();
      Directory appDocDir = await getApplicationDocumentsDirectory();
      
      String trfPath = '${tempDir.path}/transforms.trf';
      String outputPath = '${appDocDir.path}/video_stabil_${DateTime.now().millisecondsSinceEpoch}.mp4';

      setState(() => _statusText = "Tahap 1: Menganalisa getaran...");

      String cmd1 = "-y -i $inputPath -vf vidstabdetect=shakiness=10:accuracy=15:result=$trfPath -f null -";
      var session1 = await FFmpegKit.execute(cmd1);
      var returnCode1 = await session1.getReturnCode();

      if (ReturnCode.isSuccess(returnCode1)) {
        setState(() => _statusText = "Tahap 2: Merender video stabil...");

        String cmd2 = "-y -i $inputPath -vf vidstabtransform=input=$trfPath:smoothing=30:relative=1:zoom=0 -c:a copy $outputPath";
        var session2 = await FFmpegKit.execute(cmd2);
        var returnCode2 = await session2.getReturnCode();

        if (ReturnCode.isSuccess(returnCode2)) {
          setState(() {
            _statusText = "Selesai! Tersimpan di:\n$outputPath";
            _isProcessing = false;
          });
        } else {
          _showError("Gagal merender video.");
        }
      } else {
        _showError("Gagal menganalisa video.");
      }
    } catch (e) {
      _showError("Terjadi kesalahan: $e");
    }
  }

  void _showError(String message) {
    setState(() {
      _statusText = message;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kamera Anti Goyang')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: CameraPreview(_controller),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 20),
                          Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: _isProcessing 
          ? null 
          : FloatingActionButton(
              backgroundColor: _isRecording ? Colors.red : Colors.white,
              onPressed: () async {
                try {
                  await _initializeControllerFuture;
                  _toggleRecording();
                } catch (e) {
                  print(e);
                }
              },
              child: Icon(
                _isRecording ? Icons.stop : Icons.videocam,
                color: _isRecording ? Colors.white : Colors.black,
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomAppBar(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}