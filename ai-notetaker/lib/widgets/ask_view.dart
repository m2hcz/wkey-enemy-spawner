import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType, Colors;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../ai_client.dart';
import '../ai_settings.dart';
import '../models.dart';
import '../theme.dart';

const _liveSuggestions = [
  'O que foi dito até agora?',
  'O que eu deveria perguntar agora?',
  'Explique o último assunto',
  'Quais números foram citados?',
];

const _noteSuggestions = [
  'Quais são os próximos passos?',
  'Resuma em 3 tópicos',
  'O que ficou sem resposta?',
  'Escreva um e-mail de follow-up',
];

/// Chat about the transcript ("Ask"), used live and after the recording.
class AskView extends StatefulWidget {
  const AskView({super.key, required this.note, this.live = false, this.onChanged});

  final Note note;
  final bool live;
  final VoidCallback? onChanged;

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  List<ChatMessage> get _chat => widget.note.chat;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _busy) return;
    final settings = SettingsStore.instance.value;
    final history = [..._chat, ChatMessage(role: 'user', text: text)];
    final reply = ChatMessage(role: 'assistant', text: '');
    setState(() {
      _busy = true;
      _chat
        ..add(history.last)
        ..add(reply);
      _input.clear();
    });
    _scrollToEnd();

    final client = AiClient(settings);
    try {
      await for (final chunk in client.chatStream(
        system: Prompts.askSystem(settings, widget.note, live: widget.live),
        messages: history,
      )) {
        setState(() => reply.text += chunk);
        _scrollToEnd();
      }
      if (reply.text.trim().isEmpty) reply.text = '_(resposta vazia)_';
    } catch (e) {
      reply.text = '⚠️ $e';
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.live ? _liveSuggestions : _noteSuggestions;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Expanded(
            child: _chat.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                    children: [
                      const Center(child: AppMark(size: 52)),
                      const SizedBox(height: 14),
                      Text(
                        widget.live ? 'Pergunte durante a conversa' : 'Pergunte sobre esta nota',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.label(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A IA responde com base na transcrição.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.secondary(context)),
                      ),
                      const SizedBox(height: 24),
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SuggestionChip(text: s, onTap: () => _send(s)),
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: _chat.length,
                    itemBuilder: (_, i) => _Bubble(
                      message: _chat[i],
                      typing: _busy && i == _chat.length - 1,
                    ),
                  ),
          ),
          _InputBar(controller: _input, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.sparkles, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 15, color: AppColors.label(context))),
            ),
            Icon(CupertinoIcons.arrow_up_right, size: 15, color: AppColors.tertiary(context)),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.typing});
  final ChatMessage message;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    final child = user
        ? Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 16))
        : message.text.isEmpty && typing
            ? const CupertinoActivityIndicator()
            : MarkdownBody(
                data: message.text,
                styleSheet: markdownStyle(context, fontSize: 15.5),
              );
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.text));
          HapticFeedback.mediumImpact();
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: user ? AppColors.accent : AppColors.card(context),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(user ? 18 : 5),
              bottomRight: Radius.circular(user ? 5 : 18),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.busy, required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + MediaQuery.paddingOf(context).bottom * 0),
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        border: Border(top: BorderSide(color: AppColors.separator(context), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                placeholder: 'Pergunte qualquer coisa…',
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.separator(context), width: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CupertinoButton(
              padding: const EdgeInsets.only(bottom: 2),
              minimumSize: const Size(36, 36),
              onPressed: busy ? null : () => onSend(controller.text),
              child: busy
                  ? const CupertinoActivityIndicator()
                  : const Icon(CupertinoIcons.arrow_up_circle_fill,
                      size: 36, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

MarkdownStyleSheet markdownStyle(BuildContext context, {double fontSize = 16}) {
  final label = AppColors.label(context);
  final base = TextStyle(fontSize: fontSize, height: 1.45, color: label);
  return MarkdownStyleSheet(
    p: base,
    listBullet: base,
    strong: const TextStyle(fontWeight: FontWeight.w700),
    h1: base.copyWith(fontSize: fontSize + 8, fontWeight: FontWeight.w800),
    h2: base.copyWith(fontSize: fontSize + 3, fontWeight: FontWeight.w700),
    h3: base.copyWith(fontSize: fontSize + 1, fontWeight: FontWeight.w700),
    h2Padding: const EdgeInsets.only(top: 14, bottom: 2),
    h3Padding: const EdgeInsets.only(top: 10),
    blockSpacing: 8,
    code: base.copyWith(
      fontFamily: 'monospace',
      fontSize: fontSize - 2,
      backgroundColor: AppColors.fill(context),
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.fill(context),
      borderRadius: BorderRadius.circular(10),
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12),
    a: const TextStyle(color: AppColors.accent),
    checkbox: base.copyWith(color: AppColors.accent),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.separator(context), width: 0.5)),
    ),
  );
}
