import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

Exercise _exercise({
  List<ExerciseMedia> mediaItems = const [],
  String? gifPath,
  String? imagePath,
  String? videoPath,
  String? videoUrl,
}) {
  return Exercise(
    id: 'ex',
    name: 'Ćwiczenie',
    category: 'Inne',
    muscles: const ['całe ciało'],
    equipment: 'masa ciała',
    level: 'Początkujący',
    illustrationType: 'generic',
    description: '',
    tips: const [],
    commonMistakes: const [],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: 0,
    met: 4,
    gifPath: gifPath,
    imagePath: imagePath,
    videoPath: videoPath,
    videoUrl: videoUrl,
    mediaItems: mediaItems,
  );
}

ExerciseMedia _media(MediaType type, {String? local, String? remote, String? thumb, bool primary = false}) {
  return ExerciseMedia(
    id: 'm',
    exerciseId: 'ex',
    type: type,
    localPath: local,
    remoteUrl: remote,
    thumbnailPath: thumb,
    isPrimary: primary,
  );
}

void main() {
  group('ExerciseMedia fallbacks', () {
    test('empty paths expose no content and no thumbnail', () {
      const media = ExerciseMedia(id: 'm', exerciseId: 'ex', type: MediaType.image, localPath: '   ', remoteUrl: '');
      expect(media.hasContent, isFalse);
      expect(media.effectivePath, isNull);
      expect(media.thumbnail, isNull);
      expect(media.isRemote, isFalse);
    });

    test('local image resolves path and is not remote', () {
      final media = _media(MediaType.image, local: 'assets/exercises/x.png');
      expect(media.hasContent, isTrue);
      expect(media.effectivePath, 'assets/exercises/x.png');
      expect(media.isRemote, isFalse);
      expect(media.thumbnail, 'assets/exercises/x.png');
    });

    test('remote url is flagged as remote', () {
      final media = _media(MediaType.image, remote: 'https://example.com/x.png');
      expect(media.isRemote, isTrue);
      expect(media.effectivePath, 'https://example.com/x.png');
    });

    test('video without thumbnail does not expose the video file as a thumbnail', () {
      final media = _media(MediaType.video, local: '/data/clip.mp4');
      expect(media.effectivePath, '/data/clip.mp4');
      expect(media.thumbnail, isNull);
    });

    test('video with explicit thumbnail returns the thumbnail', () {
      final media = _media(MediaType.video, local: '/data/clip.mp4', thumb: 'assets/poster.png');
      expect(media.thumbnail, 'assets/poster.png');
    });
  });

  group('MediaType parsing is crash-safe', () {
    test('fromKey handles known, alias and unknown values', () {
      expect(MediaType.fromKey('gif'), MediaType.gif);
      expect(MediaType.fromKey('GIF'), MediaType.gif);
      expect(MediaType.fromKey('photo'), MediaType.image);
      expect(MediaType.fromKey('youtube'), MediaType.url);
      expect(MediaType.fromKey(null), MediaType.none);
      expect(MediaType.fromKey('zzz'), MediaType.none);
    });

    test('guessFromPath infers type from extension and scheme', () {
      expect(MediaType.guessFromPath(''), MediaType.none);
      expect(MediaType.guessFromPath('a.gif'), MediaType.gif);
      expect(MediaType.guessFromPath('clip.mp4'), MediaType.video);
      expect(MediaType.guessFromPath('http://x/clip.mp4'), MediaType.video);
      expect(MediaType.guessFromPath('pic.png'), MediaType.asset);
      expect(MediaType.guessFromPath('http://x/pic.png'), MediaType.image);
      expect(MediaType.guessFromPath('http://x/page'), MediaType.url);
      expect(MediaType.guessFromPath('file.xyz'), MediaType.asset);
    });
  });

  group('Exercise media getters', () {
    test('no media exposes nothing and never throws', () {
      final exercise = _exercise();
      expect(exercise.hasMedia, isFalse);
      expect(exercise.hasVideo, isFalse);
      expect(exercise.animatedMediaPath, isNull);
      expect(exercise.staticMediaPath, isNull);
      expect(exercise.thumbnailMediaPath, isNull);
      expect(exercise.videoMediaPath, isNull);
    });

    test('video-only media: hasVideo but no image paths and no broken thumbnail', () {
      final exercise = _exercise(mediaItems: [
        _media(MediaType.video, local: '/data/clip.mp4', primary: true),
      ]);
      expect(exercise.hasVideo, isTrue);
      expect(exercise.hasMedia, isFalse);
      expect(exercise.animatedMediaPath, isNull);
      expect(exercise.staticMediaPath, isNull);
      expect(exercise.videoMediaPath, '/data/clip.mp4');
      expect(exercise.thumbnailMediaPath, isNull);
    });

    test('image media makes hasMedia true', () {
      final exercise = _exercise(mediaItems: [
        _media(MediaType.image, local: 'assets/x.png', primary: true),
      ]);
      expect(exercise.hasMedia, isTrue);
      expect(exercise.staticMediaPath, 'assets/x.png');
      expect(exercise.thumbnailMediaPath, 'assets/x.png');
    });
  });

  group('WorkoutPlan day logic edge cases', () {
    test('empty plan has zero progress and is not completed', () {
      const plan = WorkoutPlan(id: 'p', name: 'P', note: '', days: []);
      expect(plan.progress, 0);
      expect(plan.completedCount, 0);
      expect(plan.isProgramCompleted, isFalse);
      expect(plan.statusForDay(0), WorkoutDayStatus.locked);
    });

    test('out-of-range and invalid completed indexes are safe', () {
      const item = PlanItem(exerciseId: 'pushup', sets: 3, reps: 10, durationSec: 0, note: '');
      const plan = WorkoutPlan(
        id: 'p',
        name: 'P',
        note: '',
        completedDays: {0, 99}, // 99 nie istnieje
        days: [
          WorkoutDay(weekday: 1, title: 'D1', items: [item]),
          WorkoutDay(weekday: 2, title: 'D2', items: [item]),
        ],
      );
      expect(plan.completedCount, 1); // tylko poprawny indeks 0
      expect(plan.statusForDay(5), WorkoutDayStatus.locked);
      expect(plan.statusForDay(-1), WorkoutDayStatus.locked);
    });

    test('allow-any-day mode unlocks all but keeps rest distinct', () {
      const item = PlanItem(exerciseId: 'pushup', sets: 3, reps: 10, durationSec: 0, note: '');
      const plan = WorkoutPlan(
        id: 'p',
        name: 'P',
        note: '',
        allowAnyDay: true,
        days: [
          WorkoutDay(weekday: 1, title: 'D1', items: [item]),
          WorkoutDay(weekday: 2, title: 'Dzień odpoczynku', items: []),
          WorkoutDay(weekday: 3, title: 'D3', items: [item]),
        ],
      );
      expect(plan.statusForDay(0), WorkoutDayStatus.available);
      expect(plan.statusForDay(1), WorkoutDayStatus.rest);
      expect(plan.statusForDay(2), WorkoutDayStatus.available);
    });
  });
}
