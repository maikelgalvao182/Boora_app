import 'dart:ui' as ui;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:partiu/features/home/presentation/widgets/helpers/marker_color_helper.dart';

/// Helper para gerar BitmapDescriptors para markers do Google Maps
class MarkerBitmapGenerator {
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
