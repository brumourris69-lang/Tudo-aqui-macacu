import 'package:flutter/foundation.dart';

/// Build-time switches for features intentionally deferred from the store MVP.
class MvpLaunchFeatures {
  MvpLaunchFeatures._();

  /// Store/profile builds default to no public text search. Debug builds retain
  /// it for development; a later release can opt in explicitly at build time.
  static const _compiledPublicSearchEnabled = bool.fromEnvironment(
    'MVP_PUBLIC_SEARCH_ENABLED',
    defaultValue: kDebugMode,
  );

  static const publicSearchEnabled = kDebugMode && _compiledPublicSearchEnabled;

  /// Features deferred from the public 1.0 release stay in the codebase, but
  /// are fail-closed unless a later release explicitly opts them in.
  static const reviewsEnabled =
      kDebugMode &&
      bool.fromEnvironment('MVP_REVIEWS_ENABLED', defaultValue: false);
  static const proposalsEnabled =
      kDebugMode &&
      bool.fromEnvironment('MVP_PROPOSALS_ENABLED', defaultValue: false);
  static const votesEnabled =
      kDebugMode &&
      bool.fromEnvironment('MVP_VOTES_ENABLED', defaultValue: false);
  static const jobsEnabled =
      kDebugMode &&
      bool.fromEnvironment('MVP_JOBS_ENABLED', defaultValue: false);
  static const remotePushEnabled =
      kDebugMode &&
      bool.fromEnvironment('MVP_REMOTE_PUSH_ENABLED', defaultValue: false);

  @visibleForTesting
  static bool deferredFeatureEnabled({
    required bool debugBuild,
    required bool requested,
  }) => debugBuild && requested;

  /// This is a second guard behind UI and route visibility. In particular,
  /// a stale deep link cannot submit an operation for a deferred feature.
  static bool isUserOperationEnabled(String operation) => switch (operation) {
    'contact' || 'favorite' || 'unfavorite' => true,
    'review' => reviewsEnabled,
    'proposal' => proposalsEnabled,
    'vote' => votesEnabled,
    'device' || 'removeDevice' => remotePushEnabled,
    'metric' => true,
    _ => false,
  };

  static bool isPublicHomeCategoryEnabled(String categoryName) =>
      categoryName != 'Empregos' || jobsEnabled;

  static bool isPublicHomeSectionEnabled(String section) =>
      section != 'jobs' || jobsEnabled;

  static bool isPublicUtilityEnabled({
    required String id,
    required String destination,
  }) {
    final idKey = _utilityKey(id);
    final destinationKey = _utilityKey(destination);
    if ({'polls', 'poll', 'enquetes', 'enquete'}.contains(destinationKey) ||
        {'polls', 'poll', 'enquetes', 'enquete'}.contains(idKey)) {
      return votesEnabled;
    }
    if ({
          'businessproposal',
          'proposal',
          'proposals',
          'indiqueumaempresa',
        }.contains(destinationKey) ||
        {
          'businessproposal',
          'proposal',
          'proposals',
          'indiqueumaempresa',
        }.contains(idKey)) {
      return proposalsEnabled;
    }
    return true;
  }

  static String _utilityKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
