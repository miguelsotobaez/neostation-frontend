import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/login_form_selection.dart';

/// Minimal two-field login form, the shape both real login screens have.
class _TestForm extends StatefulWidget {
  const _TestForm();

  @override
  State<_TestForm> createState() => _TestFormState();
}

class _TestFormState extends State<_TestForm>
    with LoginFormSelection<_TestForm> {
  final FocusNode usernameFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  @override
  List<FocusNode?> get selectionSlots => [usernameFocus, passwordFocus, null];

  @override
  void initState() {
    super.initState();
    attachFocusSelectionListeners();
  }

  @override
  void dispose() {
    detachFocusSelectionListeners();
    usernameFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(focusNode: usernameFocus),
        TextField(focusNode: passwordFocus),
        const Text('submit'),
      ],
    );
  }
}

/// Form whose slot list changes with its mode, the shape the NeoSync login has:
/// register carries a username the login state doesn't, the verification step
/// is a pair of buttons with no field at all, and both entry modes end in a run
/// of controls — submit followed by the links that switch mode or start a
/// password reset.
class _ModalForm extends StatefulWidget {
  const _ModalForm();

  @override
  State<_ModalForm> createState() => _ModalFormState();
}

enum _Mode { login, register, verify }

class _ModalFormState extends State<_ModalForm>
    with LoginFormSelection<_ModalForm> {
  final FocusNode usernameFocus = FocusNode();
  final FocusNode emailFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  _Mode mode = _Mode.login;

  @override
  List<FocusNode?> get selectionSlots => switch (mode) {
    // login + "sign up" + "forgot password"
    _Mode.login => [emailFocus, passwordFocus, null, null, null],
    // sign up + "already have an account"
    _Mode.register => [usernameFocus, emailFocus, passwordFocus, null, null],
    _Mode.verify => [null, null],
  };

  @override
  List<FocusNode> get ownedFocusNodes => [
    usernameFocus,
    emailFocus,
    passwordFocus,
  ];

  void switchTo(_Mode next) => setState(() => mode = next);

  @override
  void initState() {
    super.initState();
    attachFocusSelectionListeners();
  }

  @override
  void dispose() {
    detachFocusSelectionListeners();
    usernameFocus.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  // Every node stays mounted regardless of mode; only the slot list changes.
  // A node that is not in the tree cannot take focus, and this test is about
  // which slot focus maps to.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(focusNode: usernameFocus),
        TextField(focusNode: emailFocus),
        TextField(focusNode: passwordFocus),
      ],
    );
  }
}

Future<_TestFormState> _pumpForm(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _TestForm())));
  return tester.state<_TestFormState>(find.byType(_TestForm));
}

Future<_ModalFormState> _pumpModalForm(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: _ModalForm())),
  );
  return tester.state<_ModalFormState>(find.byType(_ModalForm));
}

void main() {
  testWidgets('slot count covers every field plus the submit control', (
    tester,
  ) async {
    final state = await _pumpForm(tester);

    expect(state.slotCount, 3);
    expect(state.submitSlot, 2);
    expect(state.isSelected(0), isTrue);
  });

  testWidgets('the selection wraps in both directions', (tester) async {
    final state = await _pumpForm(tester);

    expect(state.moveSelection(-1), isTrue);
    await tester.pump();
    expect(state.selectedSlot, state.submitSlot);

    expect(state.moveSelection(1), isTrue);
    await tester.pump();
    expect(state.selectedSlot, 0);
  });

  testWidgets('the selection refuses to move while a field is focused', (
    tester,
  ) async {
    final state = await _pumpForm(tester);

    state.usernameFocus.requestFocus();
    await tester.pump();

    expect(state.moveSelection(1), isFalse);
    await tester.pump();
    expect(state.selectedSlot, 0);
  });

  testWidgets('focusing a field by any means moves the selection to it', (
    tester,
  ) async {
    final state = await _pumpForm(tester);

    // Stands in for the IME "next" action and for a direct tap, neither of
    // which goes through moveSelection.
    state.passwordFocus.requestFocus();
    await tester.pump();

    expect(state.selectedSlot, 1);
    expect(state.isSelected(1), isTrue);
  });

  testWidgets('exiting text entry drops focus and frees the D-pad', (
    tester,
  ) async {
    final state = await _pumpForm(tester);

    state.passwordFocus.requestFocus();
    await tester.pump();
    expect(state.isAnyFieldFocused(), isTrue);

    state.exitTextEntry();
    await tester.pump();

    expect(state.isAnyFieldFocused(), isFalse);
    expect(state.moveSelection(1), isTrue);
    await tester.pump();
    expect(state.selectedSlot, state.submitSlot);
  });

  testWidgets('resetting puts the cursor back on the first field', (
    tester,
  ) async {
    final state = await _pumpForm(tester);

    state.moveSelection(1);
    await tester.pump();
    expect(state.selectedSlot, 1);

    state.resetSelection();
    await tester.pump();
    expect(state.selectedSlot, 0);
  });

  testWidgets(
    'focusing a field reports the slot it holds in the current mode',
    (tester) async {
      final state = await _pumpModalForm(tester);

      // Email is slot 0 while logging in and slot 1 once a username appears.
      state.emailFocus.requestFocus();
      await tester.pump();
      expect(state.selectedSlot, 0);

      // A mode switch drops focus first, the way the real forms do.
      state.exitTextEntry();
      await tester.pump();
      state.switchTo(_Mode.register);
      await tester.pump();

      state.emailFocus.requestFocus();
      await tester.pump();
      expect(state.selectedSlot, 1);
    },
  );

  testWidgets('a shorter mode cannot leave the cursor past the last slot', (
    tester,
  ) async {
    final state = await _pumpModalForm(tester);
    state.switchTo(_Mode.register);
    await tester.pump();

    state.moveSelection(-1);
    await tester.pump();
    expect(state.selectedSlot, state.submitSlot);
    expect(state.selectedSlot, 4);

    // Verification drops to two button slots, stranding the index at 4.
    state.switchTo(_Mode.verify);
    await tester.pump();

    expect(state.slotCount, 2);
    expect(state.selectedSlot, 1);
    expect(state.selectedFocusNode, isNull);
  });

  testWidgets('a button slot declines focus so the screen runs its action', (
    tester,
  ) async {
    final state = await _pumpModalForm(tester);

    expect(state.focusSelectedField(), isTrue);
    await tester.pump();
    expect(state.emailFocus.hasFocus, isTrue);

    state.exitTextEntry();
    await tester.pump();
    state.moveSelection(-1);
    await tester.pump();

    expect(state.selectedFocusNode, isNull);
    expect(state.focusSelectedField(), isFalse);
  });

  testWidgets('every control after the submit button is still reachable', (
    tester,
  ) async {
    final state = await _pumpModalForm(tester);

    // Login ends in three controls — submit, then the sign-up and
    // forgot-password links — and the D-pad has to walk all of them rather
    // than stopping at the button in the middle.
    expect(state.slotCount, 5);
    for (final slot in [1, 2, 3, 4]) {
      expect(state.moveSelection(1), isTrue);
      await tester.pump();
      expect(state.selectedSlot, slot);
    }

    expect(state.selectedFocusNode, isNull);
    expect(state.focusSelectedField(), isFalse);
  });

  testWidgets('a mode switch wraps over the new slot count', (tester) async {
    final state = await _pumpModalForm(tester);
    state.switchTo(_Mode.verify);
    await tester.pump();

    expect(state.moveSelection(1), isTrue);
    await tester.pump();
    expect(state.selectedSlot, 1);

    expect(state.moveSelection(1), isTrue);
    await tester.pump();
    expect(state.selectedSlot, 0);
  });
}
