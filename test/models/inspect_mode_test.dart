import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('InspectMode.resolve', () {
    group('without flavors', () {
      test('non-release build returns developer', () {
        expect(
          InspectMode.resolve(isReleaseBuild: false),
          InspectMode.developer,
        );
      });

      test('release build returns production', () {
        expect(
          InspectMode.resolve(isReleaseBuild: true),
          InspectMode.production,
        );
      });
    });

    group('with flavors', () {
      test('prod flavor + release = production (App Store path)', () {
        expect(
          InspectMode.resolve(flavor: 'prod', isReleaseBuild: true),
          InspectMode.production,
        );
      });

      test('prod flavor + non-release = developer (dev poking prod API)', () {
        expect(
          InspectMode.resolve(flavor: 'prod', isReleaseBuild: false),
          InspectMode.developer,
        );
      });

      test('dev flavor + release = developer (TestFlight QA path)', () {
        expect(
          InspectMode.resolve(flavor: 'dev', isReleaseBuild: true),
          InspectMode.developer,
        );
      });

      test('dev flavor + non-release = developer (local dev path)', () {
        expect(
          InspectMode.resolve(flavor: 'dev', isReleaseBuild: false),
          InspectMode.developer,
        );
      });

      test('unknown flavor + release = developer (safe default)', () {
        expect(
          InspectMode.resolve(flavor: 'staging', isReleaseBuild: true),
          InspectMode.developer,
        );
      });

      test('"production" alias matches the default set', () {
        expect(
          InspectMode.resolve(flavor: 'production', isReleaseBuild: true),
          InspectMode.production,
        );
      });
    });

    group('custom productionFlavors set', () {
      test('honours custom production flavor names', () {
        expect(
          InspectMode.resolve(
            flavor: 'live',
            productionFlavors: const {'live'},
            isReleaseBuild: true,
          ),
          InspectMode.production,
        );
      });

      test('excludes "prod" when only "live" is configured', () {
        expect(
          InspectMode.resolve(
            flavor: 'prod',
            productionFlavors: const {'live'},
            isReleaseBuild: true,
          ),
          InspectMode.developer,
        );
      });

      test('empty set forces developer mode for every flavor', () {
        expect(
          InspectMode.resolve(
            flavor: 'prod',
            productionFlavors: const {},
            isReleaseBuild: true,
          ),
          InspectMode.developer,
        );
      });
    });
  });
}
