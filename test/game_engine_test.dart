import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/game/game_engine.dart';

void main() {
  group('GameEngine Rule tests', () {
    test('setting + setter bails -> roles swap, stay setting, no letter, trick cleared', () {
      // 1. Setup game
      var state = const GameState.initial();
      state = state.apply(const GameStarted(1, 2));

      // Set trick
      state = state.apply(const TrickSet(1, 'Kickflip'));
      expect(state.phase, equals(GamePhase.setting));
      expect(state.setterId, equals(1));
      expect(state.defenderId, equals(2));
      expect(state.currentTrickName, equals('Kickflip'));

      // Setter bails
      state = state.apply(const AttemptResult(1, false));

      // Assertions
      expect(state.phase, equals(GamePhase.setting));
      expect(state.setterId, equals(2)); // Swapped
      expect(state.defenderId, equals(1)); // Swapped
      expect(state.currentTrickName, isNull); // Cleared
      expect(state.letters[1], equals(0));
      expect(state.letters[2], equals(0));
    });

    test('setting + setter lands -> defending, trick locked', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));
      state = state.apply(const TrickSet(1, 'Heelflip'));

      // Setter lands
      state = state.apply(const AttemptResult(1, true));

      expect(state.phase, equals(GamePhase.defending));
      expect(state.setterId, equals(1));
      expect(state.defenderId, equals(2));
      expect(state.currentTrickName, equals('Heelflip')); // Locked in
    });

    test('defending + defender lands -> setting, SAME setter, trick cleared', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));
      state = state.apply(const TrickSet(1, 'Ollie'));
      state = state.apply(const AttemptResult(1, true)); // Lands, enters defending

      // Defender lands
      state = state.apply(const AttemptResult(2, true));

      expect(state.phase, equals(GamePhase.setting));
      expect(state.setterId, equals(1)); // Same setter
      expect(state.defenderId, equals(2));
      expect(state.currentTrickName, isNull); // Trick cleared
    });

    test('defending + defender bails -> that player\'s letters +1; if letters < 5 -> setting, same setter', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));
      state = state.apply(const TrickSet(1, 'Shuvit'));
      state = state.apply(const AttemptResult(1, true)); // Lands, enters defending

      // Defender bails
      state = state.apply(const AttemptResult(2, false));

      expect(state.phase, equals(GamePhase.setting));
      expect(state.setterId, equals(1)); // Same setter
      expect(state.defenderId, equals(2));
      expect(state.currentTrickName, isNull); // Trick cleared
      expect(state.letters[2], equals(1)); // Defender got 1 letter
      expect(state.letters[1], equals(0));
    });

    test('defending + defender bails (reaches 5 letters) -> gameOver (winner = setter)', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));

      // Defender bails 5 times
      for (int i = 0; i < 5; i++) {
        state = state.apply(TrickSet(1, 'Trick $i'));
        state = state.apply(const AttemptResult(1, true));
        state = state.apply(const AttemptResult(2, false));

        if (i < 4) {
          expect(state.phase, equals(GamePhase.setting));
          expect(state.letters[2], equals(i + 1));
        }
      }

      expect(state.phase, equals(GamePhase.gameOver));
      expect(state.letters[2], equals(5));
      expect(state.winnerId, equals(1)); // Setter wins
      expect(state.currentTrickName, isNull); // Trick cleared at game over
    });

    test('gameOver + both RematchVote -> letters reset 0/0, votes cleared, roles flip (last game\'s first defender sets first), phase setting', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));

      // Bring to gameOver
      for (int i = 0; i < 5; i++) {
        state = state.apply(TrickSet(1, 'Trick $i'));
        state = state.apply(const AttemptResult(1, true));
        state = state.apply(const AttemptResult(2, false));
      }
      expect(state.phase, equals(GamePhase.gameOver));

      // Rematch votes
      // One vote does not start game
      state = state.apply(const RematchVote(1));
      expect(state.phase, equals(GamePhase.gameOver));
      expect(state.rematchVotes, equals({1}));

      // Second vote triggers rematch
      state = state.apply(const RematchVote(2));

      expect(state.phase, equals(GamePhase.setting));
      expect(state.letters[1], equals(0));
      expect(state.letters[2], equals(0));
      expect(state.rematchVotes, isEmpty);
      // Last game's first setter was 1, so first defender was 2.
      // Roles must flip: 2 sets first (new setter), 1 defends (new defender).
      expect(state.setterId, equals(2));
      expect(state.defenderId, equals(1));
      expect(state.firstSetterId, equals(2));
    });

    test('any + PeerLeft -> abandoned', () {
      // Test from setting phase
      var state1 = const GameState.initial().apply(const GameStarted(1, 2));
      state1 = state1.apply(const PeerLeft(2));
      expect(state1.phase, equals(GamePhase.abandoned));

      // Test from defending phase
      var state2 = const GameState.initial().apply(const GameStarted(1, 2));
      state2 = state2.apply(const TrickSet(1, 'Ollie'));
      state2 = state2.apply(const AttemptResult(1, true));
      state2 = state2.apply(const PeerLeft(1));
      expect(state2.phase, equals(GamePhase.abandoned));

      // Test from gameOver phase
      var state3 = const GameState.initial().apply(const GameStarted(1, 2));
      for (int i = 0; i < 5; i++) {
        state3 = state3.apply(TrickSet(1, 'Trick $i'));
        state3 = state3.apply(const AttemptResult(1, true));
        state3 = state3.apply(const AttemptResult(2, false));
      }
      expect(state3.phase, equals(GamePhase.gameOver));
      state3 = state3.apply(const PeerLeft(1));
      expect(state3.phase, equals(GamePhase.abandoned));
    });

    test('invalid events leave state untouched', () {
      var state = const GameState.initial();

      // Attempt before game started
      var nextState = state.apply(const AttemptResult(1, true));
      expect(nextState.phase, equals(GamePhase.lobby));
      expect(nextState.lastRejectedReason, isNotNull);

      state = state.apply(const GameStarted(1, 2));

      // TrickSet by defender (not setter)
      nextState = state.apply(const TrickSet(2, 'Kickflip'));
      expect(nextState.currentTrickName, isNull);
      expect(nextState.lastRejectedReason, isNotNull);

      // Attempt without trick set
      nextState = state.apply(const AttemptResult(1, true));
      expect(nextState.phase, equals(GamePhase.setting));
      expect(nextState.lastRejectedReason, isNotNull);

      // TrickSet during defending phase
      state = state.apply(const TrickSet(1, 'Ollie'));
      state = state.apply(const AttemptResult(1, true)); // Enters defending
      expect(state.phase, equals(GamePhase.defending));

      nextState = state.apply(const TrickSet(1, 'Kickflip'));
      expect(nextState.currentTrickName, equals('Ollie')); // Unchanged
      expect(nextState.lastRejectedReason, isNotNull);

      // Rematch vote during setting phase
      nextState = state.apply(const RematchVote(1));
      expect(nextState.phase, equals(GamePhase.defending));
      expect(nextState.lastRejectedReason, isNotNull);
    });

    test('KEY TEST: letters stay with the player across a role swap', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));

      // 1. Player 2 gets a letter
      state = state.apply(const TrickSet(1, 'Kickflip'));
      state = state.apply(const AttemptResult(1, true));
      state = state.apply(const AttemptResult(2, false)); // Player 2 bails, now has 1 letter
      expect(state.letters[2], equals(1));
      expect(state.letters[1], equals(0));

      // 2. Setter (Player 1) bails on setting -> roles swap
      state = state.apply(const TrickSet(1, 'Ollie'));
      state = state.apply(const AttemptResult(1, false)); // Player 1 bails

      // Roles should be swapped
      expect(state.setterId, equals(2));
      expect(state.defenderId, equals(1));

      // Player 2 STILL has 1 letter, Player 1 STILL has 0 letters
      expect(state.letters[2], equals(1));
      expect(state.letters[1], equals(0));
    });

    test('unnamed trick (empty name) is legal per PROTOCOL.md §6', () {
      var state = const GameState.initial().apply(const GameStarted(1, 2));

      // Attempting before declaring ANY trick is still rejected
      final rejected = state.apply(const AttemptResult(1, true));
      expect(rejected.phase, equals(GamePhase.setting));
      expect(rejected.lastRejectedReason, isNotNull);

      // Declaring an unnamed trick is legal
      state = state.apply(const TrickSet(1, ''));
      expect(state.trickDeclared, isTrue);
      expect(state.currentTrickName, equals(''));
      expect(state.lastRejectedReason, isNull);

      // ...and the setter can now attempt it
      state = state.apply(const AttemptResult(1, true));
      expect(state.phase, equals(GamePhase.defending));

      // Declaration resets on the way back to setting
      state = state.apply(const AttemptResult(2, true));
      expect(state.phase, equals(GamePhase.setting));
      expect(state.trickDeclared, isFalse);
      expect(state.currentTrickName, isNull);
    });
 });
}
