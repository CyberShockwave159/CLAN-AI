import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/errors/app_exception.dart';

void main() {
  group('ApiHttpClient Error Handling Tests', () {
    late ApiHttpClient client;

    setUp(() {
      client = ApiHttpClient();
    });

    tearDown(() {
      client.close();
    });

    group('ContextLimitExceededException', () {
      test('thrown on 400 with "context" in body', () {
        expect(
          () => client.throwForStatusCode(400, '{"error": {"message": "Context length exceeded"}}', Uri.parse('/test')),
          throwsA(isA<ContextLimitExceededException>()),
        );
      });

      test('thrown on 400 with "exceed" in body', () {
        expect(
          () => client.throwForStatusCode(400, '{"error": {"message": "Tokens exceed maximum"}}', Uri.parse('/test')),
          throwsA(isA<ContextLimitExceededException>()),
        );
      });

      test('thrown on 400 with plain text containing "context"', () {
        expect(
          () => client.throwForStatusCode(400, 'Context window exceeded', Uri.parse('/test')),
          throwsA(isA<ContextLimitExceededException>()),
        );
      });

      test('has correct statusCode', () {
        try {
          client.throwForStatusCode(400, '{"error": {"message": "Context length exceeded"}}', Uri.parse('/test'));
          fail('Should have thrown');
        } on ContextLimitExceededException catch (e) {
          expect(e.statusCode, equals(400));
          expect(e.isRetryable, isFalse);
        }
      });

      test('recoverySuggestion is set', () {
        try {
          client.throwForStatusCode(400, '{"error": {"message": "Context length exceeded"}}', Uri.parse('/test'));
          fail('Should have thrown');
        } on ContextLimitExceededException catch (e) {
          expect(e.recoverySuggestion, isNotNull);
          expect(e.recoverySuggestion, contains('context window'));
        }
      });

      test('not thrown for 400 without context/exceed keywords', () {
        expect(
          () => client.throwForStatusCode(400, '{"error": {"message": "Bad request"}}', Uri.parse('/test')),
          throwsA(isA<AppException>()),
        );
      });
    });

    group('ServerOOMException', () {
      test('thrown on 500 with "memory" in body', () {
        expect(
          () => client.throwForStatusCode(500, '{"error": {"message": "Out of memory"}}', Uri.parse('/test')),
          throwsA(isA<ServerOOMException>()),
        );
      });

      test('thrown on 500 with "slot" in body', () {
        expect(
          () => client.throwForStatusCode(500, '{"error": {"message": "No slots available"}}', Uri.parse('/test')),
          throwsA(isA<ServerOOMException>()),
        );
      });

      test('thrown on 500 with plain text containing "memory"', () {
        expect(
          () => client.throwForStatusCode(500, 'Server out of memory', Uri.parse('/test')),
          throwsA(isA<ServerOOMException>()),
        );
      });

      test('has correct statusCode', () {
        try {
          client.throwForStatusCode(500, '{"error": {"message": "Out of memory"}}', Uri.parse('/test'));
          fail('Should have thrown');
        } on ServerOOMException catch (e) {
          expect(e.statusCode, equals(500));
          expect(e.isRetryable, isTrue);
        }
      });

      test('default message is set for OOM', () {
        try {
          client.throwForStatusCode(500, 'Out of memory', Uri.parse('/test'));
          fail('Should have thrown');
        } on ServerOOMException catch (e) {
          expect(e.message, contains('memory'));
        }
      });

      test('not thrown for 500 without memory/slot keywords', () {
        expect(
          () => client.throwForStatusCode(500, '{"error": {"message": "Internal server error"}}', Uri.parse('/test')),
          throwsA(isA<AppException>()),
        );
      });
    });

    group('AppException (generic)', () {
      test('thrown for 401 status', () {
        expect(
          () => client.throwForStatusCode(401, '{"error": {"message": "Unauthorized"}}', Uri.parse('/test')),
          throwsA(isA<AppException>()),
        );
      });

      test('thrown for 503 status', () {
        expect(
          () => client.throwForStatusCode(503, '{"error": {"message": "Service unavailable"}}', Uri.parse('/test')),
          throwsA(isA<AppException>()),
        );
      });

      test('extracts error message from nested JSON', () {
        try {
          client.throwForStatusCode(403, '{"error": {"message": "API key invalid"}}', Uri.parse('/test'));
          fail('Should have thrown');
        } on AppException catch (e) {
          expect(e.message, contains('API key invalid'));
        }
      });

      test('uses body text when JSON parsing fails', () {
        try {
          client.throwForStatusCode(502, 'Bad Gateway Error', Uri.parse('/test'));
          fail('Should have thrown');
        } on AppException catch (e) {
          expect(e.message, contains('Bad Gateway Error'));
        }
      });
    });

    group('Exception details', () {
      test('ContextLimitExceededException includes endpoint details', () {
        try {
          client.throwForStatusCode(400, '{"error": {"message": "Context length exceeded"}}', Uri.parse('/v1/chat/completions'));
          fail('Should have thrown');
        } on ContextLimitExceededException catch (e) {
          expect(e.details, contains('HTTP 400'));
        }
      });

      test('ServerOOMException includes endpoint details', () {
        try {
          client.throwForStatusCode(500, '{"error": {"message": "Out of memory"}}', Uri.parse('/completion'));
          fail('Should have thrown');
        } on ServerOOMException catch (e) {
          expect(e.details, contains('HTTP 500'));
        }
      });
    });
  });
}
