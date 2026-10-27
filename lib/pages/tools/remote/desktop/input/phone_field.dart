import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../services/localization/l10n.dart';
import 'keyboard_board.dart';

class PhoneKeyboardField extends StatefulWidget {
  const PhoneKeyboardField({
    super.key,
    required this.kind,
    required this.onInsert,
    required this.onBackspace,
    required this.onSubmit,
    this.autofocus = true,
  });

  final RemoteTextKind kind;
  final void Function(String text) onInsert;
  final void Function(int count) onBackspace;
  final VoidCallback onSubmit;

  final bool autofocus;

  @override
  State<PhoneKeyboardField> createState() => _PhoneKeyboardFieldState();
}

class _PhoneKeyboardFieldState extends State<PhoneKeyboardField> {
  static const _anchor = '\u200b';

  final _controller = TextEditingController(text: _anchor);
  final _focus = FocusNode();
  var _applying = false;
  var _body = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focus.addListener(_onFocusChanged);
    if (widget.autofocus) _requestFocusSoon();
  }

  void _requestFocusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PhoneKeyboardField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _reset();
      if (widget.autofocus) _requestFocusSoon();
    } else if (widget.autofocus && !oldWidget.autofocus) {
      _requestFocusSoon();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reset() {
    _applying = true;
    _body = '';
    _controller.value = const TextEditingValue(
      text: _anchor,
      selection: TextSelection.collapsed(offset: _anchor.length),
    );
    _applying = false;
  }

  void _onChanged() {
    if (_applying) return;
    var text = _controller.text;
    var extraBackspaces = 0;
    if (!text.contains(_anchor)) {
      extraBackspaces = 1;
      text = _anchor + text;
    } else if (!text.startsWith(_anchor)) {
      text = _anchor + text.replaceAll(_anchor, '');
    }
    final body = text.substring(_anchor.length);
    final previous = _body;
    var shared = 0;
    while (shared < previous.length &&
        shared < body.length &&
        previous[shared] == body[shared]) {
      shared++;
    }
    final removed = previous.length - shared;
    final added = body.substring(shared);
    _body = body;
    if (text != _controller.text) {
      _applying = true;
      _controller.value = TextEditingValue(
        text: _anchor + body,
        selection: TextSelection.collapsed(
          offset: _anchor.length + body.length,
        ),
      );
      _applying = false;
    }
    final backspaces = removed + extraBackspaces;
    if (backspaces > 0) widget.onBackspace(backspaces);
    if (added.isNotEmpty) widget.onInsert(added);
  }

  @override
  Widget build(BuildContext context) {
    final hex = widget.kind == RemoteTextKind.byte;
    final number = widget.kind == RemoteTextKind.number;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      keyboardType: number
          ? const TextInputType.numberWithOptions(signed: true)
          : TextInputType.text,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [
        if (hex) FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F\u200b]')),
        if (number) FilteringTextInputFormatter.allow(RegExp(r'[0-9\-\u200b]')),
      ],
      onSubmitted: (_) => widget.onSubmit(),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIcon: const Icon(Icons.keyboard_outlined),
        labelText: context.l10n.remoteKeyboardHint,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: _focus.hasFocus
            ? IconButton(
                tooltip: context.l10n.remoteKeyboardHide,
                icon: const Icon(Icons.keyboard_hide_outlined),
                onPressed: _focus.unfocus,
              )
            : null,
      ),
    );
  }
}
