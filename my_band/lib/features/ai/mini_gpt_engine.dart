import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class MiniGptEngine {
  late OrtSession _session;
  late OnnxRuntime _ort;
  Map<String, int> _stoi = {};
  Map<int, String> _itos = {};
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Загрузка словаря
    final vocabData = await _loadJson('assets/models/vocab.json');
    _stoi = Map<String, int>.from(vocabData['stoi']);
    _itos = (vocabData['itos'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(int.parse(key), value as String),
    );

    // 2. Инициализация ONNX
    _ort = OnnxRuntime();
    
    try {
      // Пытаемся загрузить как ассет (для Android/iOS)
      _session = await _ort.createSessionFromAsset('assets/models/minigpt.onnx');
    } catch (e) {
      // Если упало (значит мы в Web), грузим по прямому URL
      _session = await _ort.createSession('assets/models/minigpt.onnx');
    }

    _isInitialized = true;
  }

  // Универсальная загрузка JSON (работает везде)
  Future<Map<String, dynamic>> _loadJson(String path) async {
    String jsonString;
    try {
      // Пытаемся взять из assets (Android)
      jsonString = await rootBundle.loadString(path);
    } catch (e) {
      // Если мы в браузере, скачиваем через HTTP
      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200) {
        throw Exception('Не удалось загрузить $path: HTTP ${response.statusCode}');
      }
      jsonString = response.body;
    }
    return jsonDecode(jsonString);
  }

  List<int> _encode(String text) {
    final ids = <int>[];
    for (int i = 0; i < text.length; i++) {
      if (_stoi.containsKey(text[i])) ids.add(_stoi[text[i]]!);
    }
    return ids;
  }

  String _decode(List<int> ids) {
    return ids.map((id) => _itos[id] ?? '').join();
  }

  Future<String> generate(String prompt, {int maxNewTokens = 50}) async {
    await init();

    List<int> context = _encode(prompt);
    if (context.isEmpty) return "Модель не знает таких символов.";

    final blockSize = 32;

    for (int i = 0; i < maxNewTokens; i++) {
      final startIdx = max(0, context.length - blockSize);
      final inputIds = context.sublist(startIdx);

      // Создаем тензор
      final inputTensor = await OrtValue.fromList(
        Int64List.fromList(inputIds),
        [1, inputIds.length],
      );

      final inputs = {'input_ids': inputTensor};

      // Запускаем модель
      final outputs = await _session.run(inputs);

      final outputTensor = outputs['logits'];
      if (outputTensor == null) throw Exception("Выходной тензор 'logits' не найден");

      final logitsData = await outputTensor.asFlattenedList();
      final vocabSize = _stoi.length;

      final lastStepStart = logitsData.length - vocabSize;
      int bestId = 0;
      double maxLogit = double.negativeInfinity;

      for (int j = 0; j < vocabSize; j++) {
        double val = (logitsData[lastStepStart + j] as num).toDouble();
        if (val > maxLogit) {
          maxLogit = val;
          bestId = j;
        }
      }

      context.add(bestId);

      await inputTensor.dispose();
      for (var out in outputs.values) {
        await out.dispose();
      }
    }

    return _decode(context);
  }
}