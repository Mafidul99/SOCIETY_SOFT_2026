import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../widgets/portal_widgets.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({
    super.key,
    this.apiService,
    this.session,
  });

  final ApiService? apiService;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroColors = isDark
        ? const [Color(0xFF253B8C), Color(0xFF50346F)]
        : [colors.primary, colors.tertiary];
    final contacts = [
      _SupportContact(
        icon: Icons.phone_in_talk_rounded,
        label: 'Call our office',
        value: '+91 9282956845',
        accent: const Color(0xFF078A6A),
        onTap: () => _callOffice(context),
      ),
      _SupportContact(
        icon: Icons.mark_email_read_rounded,
        label: 'Email support',
        value: 'support@ntccsl.in',
        accent: const Color(0xFF3458D4),
        onTap: () => _emailSupport(context),
      ),
      _SupportContact(
        icon: Icons.language_rounded,
        label: 'Visit our website',
        value: 'ntccsl.in',
        accent: const Color(0xFF7B4BC4),
        onTap: () async {
          final uri = Uri.https('ntccsl.in');
          try {
            final launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (!launched && context.mounted) {
              showPortalToast(context, 'Could not open ntccsl.in.',
                  isError: true);
            }
          } catch (error) {
            if (context.mounted) {
              showPortalToast(
                context,
                'Could not open ntccsl.in: $error',
                isError: true,
              );
            }
          }
        },
      ),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('support-whatsapp-button'),
        heroTag: null,
        tooltip: 'Message us on WhatsApp',
        onPressed: () => _openWhatsApp(context),
        backgroundColor: const Color(0xFF128C7E),
        foregroundColor: Colors.white,
        child: TickerMode(
          enabled: !MediaQuery.of(context).disableAnimations,
          child: const _AnimatedWhatsAppIcon(),
        ),
      ),
      body: PortalGradientBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              key: const Key('support-hero'),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: heroColors,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .20),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .24),
                          ),
                        ),
                        child: const Icon(
                          Icons.support_agent_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We are here to help with your account.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'SUPPORT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Personal assistance, when you need it.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Contact our head office for account questions, member assistance, and portal access support.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: .84),
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'Get in touch',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the contact option that works best for you.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < contacts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _ContactCard(contact: contacts[i]),
                        ),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    for (final contact in contacts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ContactCard(contact: contact),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('support-ai-chat-button'),
                onPressed: () => _openSupportChat(context),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Ask AI Support Assistant'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How can we help?',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'For account updates, portal access, or member assistance, contact the head office using the details above.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _emailSupport(BuildContext context) async {
  final uri = Uri(
    scheme: 'mailto',
    path: 'support@ntccsl.in',
    queryParameters: {
      'subject': 'NTCCSL account support',
      'body': 'Hello NTCCSL Support,\n\nI need help with my account.\n',
    },
  );
  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      showPortalToast(
        context,
        'Could not open your email app. Contact support@ntccsl.in.',
        isError: true,
      );
    }
  } catch (error) {
    if (context.mounted) {
      showPortalToast(
        context,
        'Could not open your email app: $error',
        isError: true,
      );
    }
  }
}

Future<void> _callOffice(BuildContext context) async {
  try {
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: '+919282956845'),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      showPortalToast(
        context,
        'Could not start a call. Please dial +91 9282956845.',
        isError: true,
      );
    }
  } catch (error) {
    if (context.mounted) {
      showPortalToast(
        context,
        'Could not start a call: $error',
        isError: true,
      );
    }
  }
}

Future<void> _openSupportChat(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _SupportChatSheet(),
  );
}

Future<void> _openWhatsApp(BuildContext context) async {
  final uri = Uri.https('wa.me', '/919282956845', {
    'text': 'Hello, I need help with my NTCCSL account.',
  });
  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      showPortalToast(
        context,
        'Could not open WhatsApp. Please try calling +91 9282956845.',
        isError: true,
      );
    }
  } catch (error) {
    if (context.mounted) {
      showPortalToast(
        context,
        'Could not open WhatsApp: $error',
        isError: true,
      );
    }
  }
}

String _supportAnswer(String question) {
  final normalized = question.trim().toLowerCase();
  if (normalized.contains('login') ||
      normalized.contains('log in') ||
      normalized.contains('sign in') ||
      normalized.contains('password') ||
      normalized.contains('account access')) {
    return 'Sign in with your registered email, or use your Member ID (account number) and password. If you cannot access your account or forgot your password, contact the office at +91 9282956845 or support@ntccsl.in.';
  }
  if (normalized.contains('loan') ||
      normalized.contains('borrow') ||
      normalized.contains('application')) {
    return 'You can apply from the Personal Loan or Gold Loan page. Applications stay Pending until reviewed. After approval, check your approved loan details in the portal. For account-specific help, contact the office at +91 9282956845.';
  }
  if (normalized.contains('deposit') ||
      normalized.contains('fd') ||
      normalized.contains('rd') ||
      normalized.contains('drd')) {
    return 'Open the Deposit section to view the FD, RD, or DRD accounts available to your account. If an expected account is missing, contact the office at +91 9282956845 or support@ntccsl.in.';
  }
  if (normalized.contains('contact') ||
      normalized.contains('phone') ||
      normalized.contains('email') ||
      normalized.contains('website') ||
      normalized.contains('whatsapp') ||
      normalized.contains('support')) {
    return 'You can call +91 9282956845, email support@ntccsl.in, visit ntccsl.in, or use the WhatsApp button on this Support page.';
  }
  return 'I can help with account access, loans, deposits, and support contacts. Try one of those topics, or contact our office at +91 9282956845 for more help.';
}

class _SupportChatSheet extends StatefulWidget {
  const _SupportChatSheet();

  @override
  State<_SupportChatSheet> createState() => _SupportChatSheetState();
}

class _SupportChatSheetState extends State<_SupportChatSheet> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<(String, bool)> _messages = [
    (
      'Hi! I can help with general questions about account access, loans, deposits, and support contacts.',
      false,
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage([String? suggestedQuestion]) {
    final message = (suggestedQuestion ?? _messageController.text).trim();
    if (message.isEmpty) return;

    setState(() {
      _messages
        ..add((message, true))
        ..add((_supportAnswer(message), false));
      _messageController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = (MediaQuery.sizeOf(context).height * .78)
        .clamp(360.0, 640.0)
        .toDouble();
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Support Assistant',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          'Quick answers from support FAQs',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const Key('support-chat-messages'),
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  for (var index = 0; index < _messages.length; index++)
                    _SupportChatBubble(
                      key: Key('support-chat-message-$index'),
                      message: _messages[index].$1,
                      isUser: _messages[index].$2,
                    ),
                  if (_messages.length == 1)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final question in [
                          'How do I log in?',
                          'How do I apply for a loan?',
                          'How do I view my deposits?',
                          'How can I contact support?',
                        ])
                          ActionChip(
                            label: Text(question),
                            onPressed: () => _sendMessage(question),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('support-chat-input'),
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Ask a support question…',
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _messageController,
                    builder: (context, value, _) {
                      final canSend = value.text.trim().isNotEmpty;
                      return AnimatedContainer(
                        key: const Key('support-chat-send-surface'),
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          gradient: canSend
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: portalHeaderGradient(context),
                                )
                              : null,
                          color:
                              canSend ? null : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: canSend
                              ? [
                                  BoxShadow(
                                    color:
                                        colors.primary.withValues(alpha: .22),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ]
                              : const [],
                        ),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: IconButton(
                            key: const Key('support-chat-send'),
                            tooltip: 'Send message',
                            onPressed: canSend ? _sendMessage : null,
                            color: canSend
                                ? Colors.white
                                : colors.onSurfaceVariant,
                            iconSize: 22,
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportChatBubble extends StatelessWidget {
  const _SupportChatBubble({
    super.key,
    required this.message,
    required this.isUser,
  });

  final String message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bubbleColor =
        isUser ? colors.primaryContainer : colors.surfaceContainerHigh;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 5),
              bottomRight: Radius.circular(isUser ? 5 : 18),
            ),
            border: Border.all(
              color: isUser
                  ? colors.primary.withValues(alpha: .10)
                  : colors.outlineVariant.withValues(alpha: .7),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isUser) ...[
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    isUser ? 'You' : 'Support assistant',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isUser
                              ? colors.onPrimaryContainer.withValues(alpha: .75)
                              : colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          isUser ? colors.onPrimaryContainer : colors.onSurface,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedWhatsAppIcon extends StatefulWidget {
  const _AnimatedWhatsAppIcon();

  @override
  State<_AnimatedWhatsAppIcon> createState() => _AnimatedWhatsAppIconState();
}

class _AnimatedWhatsAppIconState extends State<_AnimatedWhatsAppIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: const FaIcon(FontAwesomeIcons.whatsapp, size: 28),
      builder: (context, child) {
        return Transform.scale(
          key: const Key('support-whatsapp-icon-animation'),
          scale: 1 + (Curves.easeInOut.transform(_controller.value) * .12),
          child: child,
        );
      },
    );
  }
}

class _SupportContact {
  const _SupportContact({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});

  final _SupportContact contact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: contact.onTap,
      borderRadius: BorderRadius.circular(21),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: contact.accent.withValues(alpha: .06),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: contact.accent.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(contact.icon, color: contact.accent, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            if (contact.onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
