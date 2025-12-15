import 'dart:ui' as ui;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';

/// Helper para gerar BitmapDescriptors para markers do Google Maps
class MarkerBitmapGenerator {
  /// Cache de bitmaps de clusters
  static final Map<String, google.BitmapDescriptor> _clusterCache = {};

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
    int size = 230,
  }) async {
    // Chave de cache baseada no emoji e contagem
    final cacheKey = 'cluster_${emoji}_$count';
    if (_clusterCache.containsKey(cacheKey)) {
      return _clusterCache[cacheKey]!;
    }

    try {
      // Padding extra para acomodar badge e sombra
      final padding = 40;
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
        ..color = Colors.black.withOpacity(0.35)
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
        ..color = Colors.black.withOpacity(0.3)
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

      final descriptor = google.BitmapDescriptor.fromBytes(uint8list);
      
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

  /// Gera bitmap de um emoji com cor dinâmica (Google Maps)
  /// 
  /// Parâmetros:
  /// - [emoji]: Emoji a ser renderizado
  /// - [eventId]: ID do evento (usado para gerar cor consistente)
  /// - [size]: Tamanho do container
  static Future<google.BitmapDescriptor> generateEmojiPinForGoogleMaps(
    String emoji, {
    String? eventId,
    int size = 230,
  }) async {
    try {
      // Adicionar padding extra para acomodar a sombra
      final padding = 30;
      final canvasSize = size + (padding * 2);
      final center = canvasSize / 2;
      
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final backgroundColor = eventId != null
          ? MarkerColorHelper.getColorForId(eventId)
          : const Color(0xFFFFFFFF);
      
      // Sombra
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
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

      return google.BitmapDescriptor.fromBytes(uint8list);
    } catch (e) {
      debugPrint('❌ Erro ao gerar emoji pin: $e');
      return await _generateDefaultAvatarPinForGoogleMaps(size);
    }
  }

  /// Gera bitmap circular de um avatar a partir de URL (Google Maps)
  static Future<google.BitmapDescriptor> generateAvatarPinForGoogleMaps(
    String url, {
    int size = 100,
  }) async {
    try {
      if (url.contains('placeholder.com') || url.isEmpty) {
        return _generateDefaultAvatarPinForGoogleMaps(size);
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        return _generateDefaultAvatarPinForGoogleMaps(size);
      }

      final codec = await ui.instantiateImageCodec(response.bodyBytes);
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

      return google.BitmapDescriptor.fromBytes(uint8list);
    } catch (e) {
      return _generateDefaultAvatarPinForGoogleMaps(size);
    }
  }

  /// Gera avatar padrão cinza com ícone de pessoa (Google Maps)
  static Future<google.BitmapDescriptor> _generateDefaultAvatarPinForGoogleMaps(int size) async {
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

    return google.BitmapDescriptor.fromBytes(uint8list);
  }
}
