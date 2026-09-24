import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/mock_path_provider.dart';

void main() {
  group('MessageAttachmentStore', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupMockPathProvider();

    final store = MessageAttachmentStore.instance;

    test('fetchBytes returns response bytes for a 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), equals('http://host/file.png'));
        return http.Response.bytes([1, 2, 3, 4], 200);
      });

      final bytes = await MessageAttachmentStore.instance
          .fetchBytes('http://host/file.png', client: client);

      expect(bytes, equals([1, 2, 3, 4]));
    });

    test('fetchBytes decodes a base64 data URL without a network call', () async {
      final payload = 'aGVsbG8gd29ybGQ='; // base64("hello world")
      final inlineClient = MockClient((request) async {
        fail('data: URLs must not hit the network');
      });

      final bytes = await MessageAttachmentStore.instance.fetchBytes(
        'data:text/plain;base64,$payload',
        client: inlineClient,
      );

      expect(utf8.decode(bytes), equals('hello world'));
    });

    test('fetchBytes decodes a percent-encoded data URL without a network call', () async {
      final inlineClient = MockClient((request) async {
        fail('data: URLs must not hit the network');
      });

      final bytes = await MessageAttachmentStore.instance.fetchBytes(
        'data:text/plain,hello%20world',
        client: inlineClient,
      );

      expect(utf8.decode(bytes), equals('hello world'));
    });

    test('dataUrlBytes returns null for non-data URLs', () {
      expect(MessageAttachmentStore.dataUrlBytes('http://host/file.png'), isNull);
      expect(MessageAttachmentStore.dataUrlBytes(''), isNull);
    });

    test('dataUrlMime returns the declared MIME type', () {
      expect(
        MessageAttachmentStore.dataUrlMime('data:image/png;base64,AAAA'),
        equals('image/png'),
      );
      expect(
        MessageAttachmentStore.dataUrlMime('data:text/plain;base64,AAAA'),
        equals('text/plain'),
      );
      expect(MessageAttachmentStore.dataUrlMime('http://host/a.png'), isNull);
    });

    test('fetchBytes throws AppException on non-200', () async {
      final client = MockClient((request) async {
        return http.Response('not found', 404);
      });

      expect(
        () => MessageAttachmentStore.instance
            .fetchBytes('http://host/missing.bin', client: client),
        throwsA(isA<AppException>()),
      );
    });

    test('saveFile writes bytes under the attachments directory', () async {
      final path = await store.saveFile(
        fileId: 'msg-1',
        data: Uint8List.fromList([1, 2, 3]),
        fileName: 'report.pdf',
        mime: 'application/pdf',
      );

      expect(path, endsWith('attachments/f_msg-1.pdf'));
      expect(File(path).existsSync(), isTrue);
      expect(await File(path).readAsBytes(), equals([1, 2, 3]));
    });

    test('downloadArtifact fetches, saves, and returns the local path', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), equals('http://host/summary.txt'));
        return http.Response.bytes('hello'.codeUnits, 200);
      });

      final path = await MessageAttachmentStore.instance.downloadArtifact(
        fileId: 'msg-2',
        url: 'http://host/summary.txt',
        fileName: 'summary.txt',
        mime: 'text/plain',
        client: client,
      );

      expect(path, endsWith('attachments/f_msg-2.txt'));
      expect(await File(path).readAsString(), equals('hello'));
    });

    test('downloadArtifact falls back to a URL-derived filename', () async {
      final client = MockClient((request) async {
        return http.Response.bytes([7], 200);
      });

      final path = await MessageAttachmentStore.instance.downloadArtifact(
        fileId: 'msg-3',
        url: 'http://host/report.pdf?token=abc',
        fileName: null,
        client: client,
      );

      expect(path, endsWith('attachments/f_msg-3.pdf'));
    });

    test('downloadArtifact throws AppException when the fetch fails', () async {
      final client = MockClient((request) async {
        return http.Response('gone', 410);
      });

      expect(
        () => MessageAttachmentStore.instance.downloadArtifact(
          fileId: 'msg-4',
          url: 'http://host/nope.bin',
          client: client,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('fileNameFromUrl extracts the last path segment', () {
      expect(
        MessageAttachmentStore.fileNameFromUrl('http://host/dir/file.txt'),
        equals('file.txt'),
      );
      expect(
        MessageAttachmentStore.fileNameFromUrl('http://host/file.txt?token=1'),
        equals('file.txt'),
      );
      expect(
        MessageAttachmentStore.fileNameFromUrl('http://host/nopath'),
        equals('nopath'),
      );
      expect(MessageAttachmentStore.fileNameFromUrl(''), isNull);
    });

    test('fileNameFromUrl returns null for data URLs', () {
      expect(
        MessageAttachmentStore.fileNameFromUrl('data:text/plain;base64,aGVsbG8='),
        isNull,
      );
      expect(
        MessageAttachmentStore.fileNameFromUrl('data:image/png;base64,AAAA'),
        isNull,
      );
    });

    test('saveImage writes bytes under the attachments directory', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = await store.saveImage(
        fileId: 'msg-123',
        data: bytes,
        extension: 'png',
      );

      expect(path, endsWith('attachments/msg-123.png'));
      expect(File(path).existsSync(), isTrue);
      expect(await File(path).readAsBytes(), equals(bytes));
    });

    test('saveImage defaults extension to jpg', () async {
      final path = await store.saveImage(
        fileId: 'no-ext',
        data: Uint8List.fromList([9, 9]),
      );
      expect(path, endsWith('attachments/no-ext.jpg'));
    });

    test('deleteIfExists removes the file', () async {
      final path = await store.saveImage(
        fileId: 'delete-me',
        data: Uint8List.fromList([5]),
        extension: 'jpg',
      );
      expect(File(path).existsSync(), isTrue);

      await store.deleteIfExists(path);
      expect(File(path).existsSync(), isFalse);
    });

    test('deleteIfExists is a no-op for null or missing paths', () async {
      await store.deleteIfExists(null);
      await store.deleteIfExists('');
      await store.deleteIfExists('/tmp/attachments/nonexistent.jpg');
      // Implicit pass — no exception thrown.
    });

    test('mimeTypeFor maps known extensions', () {
      expect(MessageAttachmentStore.mimeTypeFor('jpg'), equals('image/jpeg'));
      expect(MessageAttachmentStore.mimeTypeFor('.jpeg'), equals('image/jpeg'));
      expect(MessageAttachmentStore.mimeTypeFor('PNG'), equals('image/png'));
      expect(MessageAttachmentStore.mimeTypeFor('webp'), equals('image/webp'));
      expect(MessageAttachmentStore.mimeTypeFor('gif'), equals('image/gif'));
    });

    test('mimeTypeFor defaults to image/jpeg for unknown extensions', () {
      expect(MessageAttachmentStore.mimeTypeFor('tiff'), equals('image/jpeg'));
      expect(MessageAttachmentStore.mimeTypeFor(''), equals('image/jpeg'));
      expect(MessageAttachmentStore.mimeTypeFor(null), equals('image/jpeg'));
    });

    test('extensionOf extracts the extension from a path', () {
      expect(MessageAttachmentStore.extensionOf('/tmp/photo.png'), equals('png'));
      expect(MessageAttachmentStore.extensionOf('/tmp/photo.JPEG'), equals('JPEG'));
      expect(MessageAttachmentStore.extensionOf('/tmp/noextension'), equals('jpg'));
    });

    test('extensionForUrl derives the extension from a data URL mime', () {
      expect(
        MessageAttachmentStore.extensionForUrl('data:image/png;base64,aGVsbG8='),
        equals('png'),
      );
      expect(
        MessageAttachmentStore.extensionForUrl('data:image/jpeg;base64,aGVsbG8='),
        equals('jpg'),
      );
      expect(
        MessageAttachmentStore.extensionForUrl('data:image/webp;base64,aGVsbG8='),
        equals('webp'),
      );
      expect(
        MessageAttachmentStore.extensionForUrl('http://host/a.webp'),
        equals('webp'),
      );
    });

    group('mimeTypeFromBytes', () {
      Uint8List from(List<int> bytes) => Uint8List.fromList(bytes);

      test('detects JPEG from the FF D8 FF marker', () {
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(from([0xFF, 0xD8, 0xFF, 0xE0, 0x00])),
          equals('image/jpeg'),
        );
      });

      test('detects PNG from its 8-byte signature', () {
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(
            from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]),
          ),
          equals('image/png'),
        );
      });

      test('detects GIF87a and GIF89a', () {
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(
            from('GIF87a'.codeUnits),
          ),
          equals('image/gif'),
        );
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(
            from('GIF89a'.codeUnits),
          ),
          equals('image/gif'),
        );
      });

      test('detects BMP', () {
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(from('BM'.codeUnits)),
          equals('image/bmp'),
        );
      });

      test('detects WebP from RIFF + WEBP', () {
        final riff = <int>[
          0x52, 0x49, 0x46, 0x46, // "RIFF"
          0, 0, 0, 0,
          0x57, 0x45, 0x42, 0x50, // "WEBP"
        ];
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(from(riff)),
          equals('image/webp'),
        );
      });

      test('detects HEIC and AVIF ISO-BMFF brands', () {
        Uint8List ftyp(String brand) => from([
          0, 0, 0, 24,
          0x66, 0x74, 0x79, 0x70, // "ftyp"
          ...brand.codeUnits,
        ]);

        expect(
          MessageAttachmentStore.mimeTypeFromBytes(ftyp('heic')),
          equals('image/heic'),
        );
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(ftyp('mif1')),
          equals('image/heif'),
        );
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(ftyp('avif')),
          equals('image/avif'),
        );
      });

      test('returns null for unknown or too-short data', () {
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(from([1, 2, 3, 4, 5])),
          isNull,
        );
        expect(MessageAttachmentStore.mimeTypeFromBytes(from([])), isNull);
        expect(
          MessageAttachmentStore.mimeTypeFromBytes(from('plain text'.codeUnits)),
          isNull,
        );
      });
    });
  });
}