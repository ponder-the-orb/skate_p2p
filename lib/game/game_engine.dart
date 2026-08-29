enum GamePhase { lobby, setting, defending, gameOver, abandoned }

sealed class GameEvent {
  const GameEvent();
}

class GameStarted extends GameEvent {
  final int firstSetterId;
  final int firstDefenderId;

  const GameStarted(this.firstSetterId, this.firstDefenderId);
}

class TrickSet extends GameEvent {
  final int playerId;
  final String name;

  const TrickSet(this.playerId, this.name);
}

class AttemptResult extends GameEvent {
  final int playerId;
  final bool landed;

  const AttemptResult(this.playerId, this.landed);
}

class RematchVote extends GameEvent {
  final int playerId;

  const RematchVote(this.playerId);
}

class PeerLeft extends GameEvent {
  final int peerId;

  const PeerLeft(this.peerId);
}

class GameState {
  final GamePhase phase;
  final int? setterId;
  final int? defenderId;
  final Map<int, int> letters;
  final String? currentTrickName;
  final Set<int> rematchVotes;
  final int? firstSetterId;
  final int? winnerId;
  final String? lastRejectedReason;
  final bool trickDeclared;

  const GameState({
    required this.phase,
    required this.setterId,
    required this.defenderId,
    required this.letters,
    required this.currentTrickName,
    required this.rematchVotes,
    required this.firstSetterId,
    required this.winnerId,
    required this.trickDeclared,
    this.lastRejectedReason,
  });

  const GameState.initial()
      : phase = GamePhase.lobby,
        setterId = null,
        defenderId = null,
        letters = const {},
        currentTrickName = null,
        rematchVotes = const {},
        firstSetterId = null,
        winnerId = null,
        trickDeclared = false,
        lastRejectedReason = null;

  /// Returns a copy with the given fields replaced.
  ///
  /// `clearTrick: true` is the ONLY way to null out [currentTrickName] and reset [trickDeclared].
  /// Passing `currentTrickName: null` is indistinguishable from omitting the
  /// parameter, so the `??` fallback below would silently keep the old value.
  ///
  /// [lastRejectedReason] is direct-assigned with NO `??` fallback, on
  /// purpose and for the same reason: it must be freshly set or cleared on
  /// every transition. Do not "fix" it to match the other fields.
  GameState _copyWith({
    GamePhase? phase,
    int? setterId,
    int? defenderId,
    Map<int, int>? letters,
    String? currentTrickName,
    bool? trickDeclared,
    bool clearTrick = false,
    Set<int>? rematchVotes,
    int? firstSetterId,
    int? winnerId,
    String? lastRejectedReason,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      setterId: setterId ?? this.setterId,
      defenderId: defenderId ?? this.defenderId,
      letters: letters ?? this.letters,
      currentTrickName:
          clearTrick ? null : (currentTrickName ?? this.currentTrickName),
      trickDeclared: clearTrick ? false : (trickDeclared ?? this.trickDeclared),
      rematchVotes: rematchVotes ?? this.rematchVotes,
      firstSetterId: firstSetterId ?? this.firstSetterId,
      winnerId: winnerId ?? this.winnerId,
      lastRejectedReason: lastRejectedReason,
    );
  }

  GameState apply(GameEvent e) {
    switch (e) {
      case PeerLeft():
        if (phase == GamePhase.abandoned) {
          return this;
        }
        return _copyWith(
          phase: GamePhase.abandoned,
          lastRejectedReason: null,
        );

      case GameStarted():
        if (phase != GamePhase.lobby) {
          return _copyWith(lastRejectedReason: 'Game can only be started from lobby phase');
        }
        if (e.firstSetterId == e.firstDefenderId) {
          return _copyWith(lastRejectedReason: 'Setter and defender must be different players');
        }
        return GameState(
          phase: GamePhase.setting,
          setterId: e.firstSetterId,
          defenderId: e.firstDefenderId,
          letters: Map.unmodifiable({
            e.firstSetterId: 0,
            e.firstDefenderId: 0,
          }),
          currentTrickName: null,
          rematchVotes: const {},
          firstSetterId: e.firstSetterId,
          winnerId: null,
          trickDeclared: false,
          lastRejectedReason: null,
        );

      case TrickSet():
        if (phase != GamePhase.setting) {
          return _copyWith(lastRejectedReason: 'Tricks can only be set during setting phase');
        }
        if (e.playerId != setterId) {
          return _copyWith(lastRejectedReason: 'Only the current setter can set a trick');
        }
        // Removed the empty string rejection check
        return _copyWith(
          currentTrickName: e.name,
          trickDeclared: true,
          lastRejectedReason: null,
        );

      case AttemptResult():
        if (phase == GamePhase.setting) {
          if (e.playerId != setterId) {
            return _copyWith(lastRejectedReason: 'Only the setter can attempt in setting phase');
          }
          // Guard changed to check boolean flag instead of string null/empty
          if (!trickDeclared) {
            return _copyWith(lastRejectedReason: 'Cannot attempt a trick before setting it');
          }
          if (e.landed) {
            return _copyWith(
              phase: GamePhase.defending,
              lastRejectedReason: null,
            );
          } else {
            return _copyWith(
              phase: GamePhase.setting,
              setterId: defenderId,
              defenderId: setterId,
              clearTrick: true,
              lastRejectedReason: null,
            );
          }
        } else if (phase == GamePhase.defending) {
          if (e.playerId != defenderId) {
            return _copyWith(lastRejectedReason: 'Only the defender can attempt in defending phase');
          }
          if (e.landed) {
            return _copyWith(
              phase: GamePhase.setting,
              clearTrick: true,
              lastRejectedReason: null,
            );
          } else {
            final defenderCurrentLetters = letters[defenderId] ?? 0;
            final newLettersCount = defenderCurrentLetters + 1;
            final updatedLetters = Map<int, int>.from(letters);
            updatedLetters[defenderId!] = newLettersCount;

            if (newLettersCount >= 5) {
              return _copyWith(
                phase: GamePhase.gameOver,
                letters: Map.unmodifiable(updatedLetters),
                winnerId: setterId,
                clearTrick: true,
                lastRejectedReason: null,
              );
            } else {
              return _copyWith(
                phase: GamePhase.setting,
                letters: Map.unmodifiable(updatedLetters),
                clearTrick: true,
                lastRejectedReason: null,
              );
            }
          }
        } else {
          return _copyWith(lastRejectedReason: 'Attempts are only valid in setting or defending phases');
        }

      case RematchVote():
        if (phase != GamePhase.gameOver) {
          return _copyWith(lastRejectedReason: 'Rematch votes are only valid in gameOver phase');
        }
        if (letters[e.playerId] == null) {
          return _copyWith(lastRejectedReason: 'Player is not part of the game');
        }
        final updatedVotes = Set<int>.from(rematchVotes)..add(e.playerId);
        if (updatedVotes.length == 2) {
          final lastGameFirstDefenderId = letters.keys.firstWhere((id) => id != firstSetterId);
          final newSetterId = lastGameFirstDefenderId;
          final newDefenderId = firstSetterId!;

          return GameState(
            phase: GamePhase.setting,
            setterId: newSetterId,
            defenderId: newDefenderId,
            letters: Map.unmodifiable({
              newSetterId: 0,
              newDefenderId: 0,
            }),
            currentTrickName: null,
            rematchVotes: const {},
            firstSetterId: newSetterId,
            winnerId: null,
            trickDeclared: false,
            lastRejectedReason: null,
          );
        } else {
          return _copyWith(
            rematchVotes: Set.unmodifiable(updatedVotes),
            lastRejectedReason: null,
          );
        }
    }
  }
}
