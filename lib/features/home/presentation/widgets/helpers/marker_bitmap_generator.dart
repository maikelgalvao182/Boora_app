import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';

/// Helper para gerar BitmapDescriptors para markers do Google Maps
class MarkerBitmapGenerator {
  /// Cache de bitmaps de clusters
  static final Map<String, google.BitmapDescriptor> _clusterCache = {};

  /// Cache de bitmaps de emoji pins
  static final Map<String, google.BitmapDescriptor> _emojiPinCache = {};

  static double get _currentDevicePixelRatio {
    final view = ui.PlatformDispatcher.instance.implicitView;
    if (view != null) return view.devicePixelRatio;
    final views = ui.PlatformDispatcher.instance.views;
    return views.isNotEmpty ? views.first.devicePixelRatio : 1.0;
  }

  static google.BitmapDescriptor _descriptorFromPngBytes(Uint8List bytes) {
    return google.BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: _currentDevicePixelRatio,
    );
  }

  /// Gera bitmap de um cluster com emoji e badge de contagem
  /// 
  /// Parâmetros:
  /// - [emoji]: Emoji representativo do cluster
  /// - [count]: Quantidade de eventos no cluster
  /// - [clusterId]: ID do cluster para gerar cor consistente (opcional)
  /// - [size]: Tamanho do container
  /// 
  /// Visual:
  /// - Círculo colorido (via MarkerColorHelper) com emoji central
  /// - Borda branca
  /// - Badge branco no canto superior direito com número preto
  static Future<google.BitmapDescriptor> generateClusterPinForGoogleMaps(
    String emoji,
    int count, {
    String? clusterId,
    int size = 160,
  }) async {
    // Chave de cache baseada no emoji e contagem
    final dprKey = _currentDevicePixelRatio.toStringAsFixed(2);
    final cacheKey = 'cluster_${emoji}_${count}_${clusterId ?? ""}_$size@$dprKey';
    if (_clusterCache.containsKey(cacheKey)) {
      return _clusterCache[cacheKey]!;
    }

    try {
      // Padding extra para acomodar badge e sombra
      final padding = (size * 0.18).round();
      final canvasSize = size + (padding * 2);
      final center = canvasSize / 2;
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Cor do container do emoji (usando MarkerColorHelper)
      final containerColor = clusterId != null
          ? MarkerColorHelper.getColorForId(clusterId)
          : MarkerColorHelper.getColorForId(emoji);
      
      // 1. Sombra
      final shadowPaint = Paint()
        ..color = Colors.black.withAlpha(89)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(
        Offset(center, center + 5),
        size / 2,
        shadowPaint,
      );
      
      // 2. Borda externa branca
      final borderPaint = Paint()
        ..color = Colors.white;
      canvas.drawCircle(
        Offset(center, center),
        size / 2,
        borderPaint,
      );
      
      // 3. Círculo colorido interno (container do emoji)
      final borderWidth = 10.0;
      final containerPaint = Paint()..color = containerColor;
      canvas.drawCircle(
        Offset(center, center),
        (size / 2) - borderWidth,
        containerPaint,
      );

      // 4. Emoji central
      final textPainter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: size * 0.45),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (canvasSize - textPainter.width) / 2,
          (canvasSize - textPainter.height) / 2 + 2, // Ajuste sutil para centralizar visualmente
        ),
      );

      // 5. Badge de contagem (canto superior direito)
      final badgeRadius = size * 0.22;
      final badgeCenterX = center + (size / 2) * 0.55;
      final badgeCenterY = center - (size / 2) * 0.55;
      
      // Sombra do badge
      final badgeShadow = Paint()
        ..color = Colors.black.withAlpha(77)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(badgeCenterX, badgeCenterY + 2),
        badgeRadius,
        badgeShadow,
      );
      
      // Círculo branco do badge
      final badgePaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(badgeCenterX, badgeCenterY),
        badgeRadius,
        badgePaint,
      );
      
      // Texto da contagem (preto)
      final countText = count > 99 ? '99+' : count.toString();
      final countPainter = TextPainter(
        text: TextSpan(
          text: countText,
          style: TextStyle(
            fontSize: badgeRadius * (countText.length > 2 ? 0.7 : 0.9),
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      countPainter.layout();
      countPainter.paint(
        canvas,
        Offset(
          badgeCenterX - countPainter.width / 2,
          badgeCenterY - countPainter.height / 2,
        ),
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasSize, canvasSize);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final uint8list = byteData!.buffer.asUint8List();

      final descriptor = _descriptorFromPngBytes(uint8list);
      
      // Cachear
      _clusterCache[cacheKey] = descriptor;
      
      return descriptor;
    } catch (e) {
      debugPrint('❌ Erro ao gerar cluster pin: $e');
      // Fallback: usar emoji pin padrão
      return generateEmojiPinForGoogleMaps(emoji);
    }
  }

  /// Limpa cache de clusters
  static void clearClusterCache() {
    _clusterCache.clear();
    debugPrint('🗑️ [MarkerBitmapGenerator] Cache de clusters limpo');
  }

  /// Limpa cache de emoji pins
  static void clearEmojiPinCache() {
    _emojiPinCache.clear();
    debugPrint('🗑️ [MarkerBitmapGenerator] Cache de emoji pins limpo');
  }

  /// Limpa todos os caches de bitmaps
  static void clearAllCaches() {
    clearClusterCache();
    clearEmojiPinCache();
    debugPrint('🗑️ [MarkerBitmapGenerator] Todos os caches limpos');
  }

  /// Gera bitmap de um emoji com cor dinâmica (Google Maps)
  /// 
  /// Parâmetros:
  /// - [emoji]: Emoji a ser renderizado
  /// - [eventId]: ID do evento (usado para gerar cor consistente)
  /// - [size]: Tamanho do container
  static Future<google.BitmapDescriptor> generateEmojiPinForGoogleMaps(
    String emoji, {
    String? eventId,
    int size = 150,
  }) async {
    // Cache key baseada no emoji, eventId e size
    final cacheKey = 'emoji_${emoji}_${eventId ?? "default"}_$size';
    if (_emojiPinCache.containsKey(cacheKey)) {
      return _emojiPinCache[cacheKey]!;
    }

    try {
      // Adicionar padding extra para acomodar a sombra
      final padding = (size * 0.16).round();
      final canvasSize = size + (padding * 2);
      final center = canvasSize / 2;
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final backgroundColor = eventId != null
          ? MarkerColorHelper.getColorForId(eventId)
          : const Color(0xFFFFFFFF);
      
      // Sombra
      final shadowPaint = Paint()
        ..color = Colors.black.withAlpha(77)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(
        Offset(center, center + 4),
        size / 2,
        shadowPaint,
      );
      
      // Borda branca
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(center, center),
        size / 2,
        borderPaint,
      );
      
      // Círculo colorido interno
      final borderWidth = 10.0;
      final paint = Paint()..color = backgroundColor;
      canvas.drawCircle(
        Offset(center, center),
        (size / 2) - borderWidth,
        paint,
      );

      // Emoji
      final textPainter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: size * 0.5),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (canvasSize - textPainter.width) / 2,
          (canvasSize - textPainter.height) / 2,
        ),
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasSize, canvasSize);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final uint8list = byteData!.buffer.asUint8List();

      final descriptor = await _descriptorFromPngBytes(uint8list);
      _emojiPinCache[cacheKey] = descriptor;
      return descriptor;
    } catch (e) {
      debugPrint('❌ Erro ao gerar emoji pin: $e');
      return await _generateDefaultAvatarPinForGoogleMaps(size);
    }
  }

  /// Gera bitmap circular de um avatar a partir de URL (Google Maps)
  static Future<google.BitmapDescriptor> generateAvatarPinForGoogleMaps(
    String url, {
    int size = 100,
    fcm.BaseCacheManager? cacheManager,
    String? cacheKey,
  }) async {
    try {
      if (url.contains('placeholder.com') || url.isEmpty) {
        return _generateDefaultAvatarPinForGoogleMaps(size);
      }

      final fcm.BaseCacheManager manager = cacheManager ?? fcm.DefaultCacheManager();
      final File file = cacheKey == null
          ? await manager.getSingleFile(url)
          : await manager.getSingleFile(url, key: cacheKey);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return _generateDefaultAvatarPinForGoogleMaps(size);
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Sem padding extra - sombra removida
      final padding = 0;
      final canvasSize = size + (padding * 2);
      final center = canvasSize / 2;
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Borda branca
      final borderWidth = 8.0;
      final borderPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(center, center),
        size / 2,
        borderPaint,
      );

      // Clip para imagem circular
      final clipPath = Path()
        ..addOval(Rect.fromCircle(
          center: Offset(center, center),
          radius: (size / 2) - borderWidth,
        ));
      canvas.clipPath(clipPath);

      final availableSize = size - (borderWidth * 2);
      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();
      final imageAspect = imageWidth / imageHeight;
      
      Rect srcRect;
      Rect dstRect;
      
      if (imageAspect > 1) {
        final scaledWidth = imageHeight;
        final cropX = (imageWidth - scaledWidth) / 2;
        srcRect = Rect.fromLTWH(cropX, 0, scaledWidth, imageHeight);
      } else if (imageAspect < 1) {
        final scaledHeight = imageWidth;
        final cropY = (imageHeight - scaledHeight) / 2;
        srcRect = Rect.fromLTWH(0, cropY, imageWidth, scaledHeight);
      } else {
        srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
      }
      
      dstRect = Rect.fromLTWH(
        padding + borderWidth,
        padding + borderWidth,
        availableSize,
        availableSize,
      );

      canvas.drawImageRect(
        image,
        srcRect,
        dstRect,
        Paint(),
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasSize, canvasSize);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final uint8list = byteData!.buffer.asUint8List();

      return _descriptorFromPngBytes(uint8list);
    } catch (e) {
      return _generateDefaultAvatarPinForGoogleMaps(size);
    }
  }

  static Future<google.BitmapDescriptor> _generateCircularAvatarFromBytes(
    Uint8List bytes,
    int size,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final padding = 0;
    final canvasSize = size + (padding * 2);
    final center = canvasSize / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final borderWidth = 8.0;
    final borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(center, center),
      size / 2,
      borderPaint,
    );

    final clipPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(center, center),
          radius: (size / 2) - borderWidth,
        ),
      );
    canvas.clipPath(clipPath);

    final availableSize = size - (borderWidth * 2);
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final imageAspect = imageWidth / imageHeight;

    late final Rect srcRect;
    if (imageAspect > 1) {
      final scaledWidth = imageHeight;
      final cropX = (imageWidth - scaledWidth) / 2;
      srcRect = Rect.fromLTWH(cropX, 0, scaledWidth, imageHeight);
    } else if (imageAspect < 1) {
      final scaledHeight = imageWidth;
      final cropY = (imageHeight - scaledHeight) / 2;
      srcRect = Rect.fromLTWH(0, cropY, imageWidth, scaledHeight);
    } else {
      srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    }

    final dstRect = Rect.fromLTWH(
      padding + borderWidth,
      padding + borderWidth,
      availableSize,
      availableSize,
    );

    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint(),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasSize, canvasSize);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final uint8list = byteData!.buffer.asUint8List();

    return _descriptorFromPngBytes(uint8list);
  }

  /// Gera avatar padrão cinza com ícone de pessoa (Google Maps)
  static Future<google.BitmapDescriptor> _generateDefaultAvatarPinForGoogleMaps(int size) async {
    try {
      final byteData = await rootBundle.load('assets/images/empty_avatar2.jpg');
      final bytes = byteData.buffer.asUint8List();
      if (bytes.isNotEmpty) {
        return _generateCircularAvatarFromBytes(bytes, size);
      }
    } catch (_) {
      // Fallback abaixo.
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..color = Colors.grey[400]!;
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2,
      paint,
    );

    final iconPainter = TextPainter(
      text: const TextSpan(
        text: '👤',
        style: TextStyle(fontSize: 24),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(
        (size - iconPainter.width) / 2,
        (size - iconPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final uint8list = byteData!.buffer.asUint8List();

    return _descriptorFromPngBytes(uint8list);
  }
}
