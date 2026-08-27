/// A polished default renderer for a single fenced Markdown code block.
///
/// Every consumer of `MarkdownStream.codeBuilder` ends up hand-rolling the
/// same widget: a rounded container with a language label, a copy-to-
/// clipboard button, and a horizontally-scrollable monospaced body. Ship
/// that default here instead.
///
/// ```dart
/// MarkdownStream(
///   stream: llmStream,
///   codeBuilder: CodeBlockView.builder(),
/// )
/// ```
///
/// [CodeBlockView.builder] returns a plain
/// `Widget Function(String code, String language)`, matching the shape of
/// `markdown_stream.dart`'s `CodeBlockBuilder` typedef, so it can be passed
/// directly as `codeBuilder` without this file depending on
/// `markdown_stream.dart` (avoiding an import cycle).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// Builds the rich, syntax-highlighted span tree for a code body.
///
/// Given the raw [code], its [language] tag, and the resolved monospaced
/// [baseStyle], return an [InlineSpan] (typically a `TextSpan` with children)
/// with per-token colours applied. Bring your own tokenizer — e.g.
/// `package:highlight` / `package:flutter_highlight` — so this package stays
/// dependency-free.
typedef CodeHighlightBuilder = InlineSpan Function(
  String code,
  String language,
  TextStyle baseStyle,
);

/// A rounded card that renders a single fenced code block: a top bar with
/// the language label and a copy button, and a monospaced,
/// horizontally-scrollable code body that never overflows.
///
/// All colours and text styles fall back to sensible values derived from
/// the ambient [Theme], so the widget looks right in both light and dark
/// mode out of the box. Every knob can be overridden individually.
///
/// Use [CodeBlockView.builder] to plug this in as a `MarkdownStream`
/// `codeBuilder` in one line:
///
/// ```dart
/// MarkdownStream(stream: llmStream, codeBuilder: CodeBlockView.builder())
/// ```
class CodeBlockView extends StatefulWidget {
  /// Creates a code block view for [code] written in [language].
  const CodeBlockView({
    super.key,
    required this.code,
    this.language = '',
    this.backgroundColor,
    this.textStyle,
    this.codeTextStyle,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.padding = const EdgeInsets.all(12),
    this.showCopyButton = true,
    this.showLanguageLabel = true,
    this.copiedFeedbackDuration = const Duration(milliseconds: 1500),
    this.highlightBuilder,
  });

  /// The raw source code to display and copy.
  final String code;

  /// The fenced code block's language tag (e.g. `'dart'`). When empty (the
  /// default), the language label falls back to the literal text `'code'`.
  final String language;

  /// Background colour of the whole card, including the header bar.
  ///
  /// Defaults to `Theme.of(context).colorScheme.surfaceContainerHighest`,
  /// which automatically adapts to light and dark mode.
  final Color? backgroundColor;

  /// Text style used for the language label and the copy button's label.
  ///
  /// Defaults to `Theme.of(context).textTheme.labelSmall`, tinted with
  /// `colorScheme.onSurfaceVariant`.
  final TextStyle? textStyle;

  /// Text style used for the code body.
  ///
  /// Defaults to `Theme.of(context).textTheme.bodyMedium` with its
  /// `fontFamily` overridden to `'monospace'`.
  final TextStyle? codeTextStyle;

  /// Corner radius of the card. Defaults to a 10-logical-pixel radius.
  final BorderRadiusGeometry borderRadius;

  /// Padding applied around the scrollable code body (not the header bar).
  /// Defaults to `EdgeInsets.all(12)`.
  final EdgeInsetsGeometry padding;

  /// Whether the copy-to-clipboard button is shown. Defaults to `true`.
  final bool showCopyButton;

  /// Whether the language label is shown in the header bar. Defaults to
  /// `true`.
  final bool showLanguageLabel;

  /// How long the "Copied" feedback is shown after a successful copy
  /// before reverting to the idle "Copy" state. Defaults to 1.5 seconds.
  final Duration copiedFeedbackDuration;

  /// Optional syntax highlighter for the code body. When `null` (the default)
  /// the code renders as plain monospaced text. Supply a [CodeHighlightBuilder]
  /// — backed by your preferred tokenizer — to colour tokens; no highlighting
  /// dependency is added to this package.
  final CodeHighlightBuilder? highlightBuilder;

  /// Returns a `Widget Function(String code, String language)` that builds
  /// a [CodeBlockView] with the given theming knobs baked in.
  ///
  /// This matches the shape of `markdown_stream.dart`'s `CodeBlockBuilder`
  /// typedef, so it can be passed straight through:
  ///
  /// ```dart
  /// MarkdownStream(stream: llmStream, codeBuilder: CodeBlockView.builder())
  /// ```
  static Widget Function(String code, String language) builder({
    Color? backgroundColor,
    TextStyle? textStyle,
    TextStyle? codeTextStyle,
    BorderRadiusGeometry borderRadius = const BorderRadius.all(
      Radius.circular(10),
    ),
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    bool showCopyButton = true,
    bool showLanguageLabel = true,
    Duration copiedFeedbackDuration = const Duration(milliseconds: 1500),
    CodeHighlightBuilder? highlightBuilder,
  }) {
    return (String code, String language) => CodeBlockView(
      code: code,
      language: language,
      backgroundColor: backgroundColor,
      textStyle: textStyle,
      codeTextStyle: codeTextStyle,
      borderRadius: borderRadius,
      padding: padding,
      showCopyButton: showCopyButton,
      showLanguageLabel: showLanguageLabel,
      copiedFeedbackDuration: copiedFeedbackDuration,
      highlightBuilder: highlightBuilder,
    );
  }

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(widget.copiedFeedbackDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Widget _buildHeader(
    TextStyle labelStyle,
    Color iconColor,
    Color dividerColor,
  ) {
    final String languageLabel = widget.language.trim().isEmpty
        ? 'code'
        : widget.language.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          if (widget.showLanguageLabel)
            Expanded(
              child: Text(
                languageLabel,
                style: labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          if (widget.showCopyButton)
            _buildCopyButton(labelStyle, iconColor),
        ],
      ),
    );
  }

  Widget _buildCopyButton(TextStyle labelStyle, Color iconColor) {
    final String label = _copied ? 'Copied' : 'Copy';
    // Present the control as a SINGLE labelled button to assistive tech:
    // `excludeSemantics` collapses the descendant Tooltip + Text semantics so
    // a screen reader announces "Copy" once, not three times.
    return Semantics(
      button: true,
      label: label,
      // Keep the button's activation exposed to assistive tech even though we
      // collapse the descendant Tooltip/Text semantics.
      onTap: () => _handleCopy(),
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _handleCopy,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 14,
                    color: iconColor,
                  ),
                  const SizedBox(width: 4),
                  Text(label, style: labelStyle.copyWith(color: iconColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color background =
        widget.backgroundColor ?? scheme.surfaceContainerHighest;
    final TextStyle labelStyle =
        widget.textStyle ??
        theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ) ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        );
    final TextStyle codeStyle =
        widget.codeTextStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          height: 1.4,
        ) ??
        const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4);
    final Color iconColor = labelStyle.color ?? scheme.onSurfaceVariant;
    final Color dividerColor = scheme.outlineVariant.withValues(alpha: 0.4);

    // Fill the available width so the card spans the message column and the
    // copy control sits at the true right edge (a shrink-wrapped card would
    // size to its content and leave the button mid-row).
    return SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: background),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.showLanguageLabel || widget.showCopyButton)
                _buildHeader(labelStyle, iconColor, dividerColor),
              Padding(
                padding: widget.padding,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: widget.highlightBuilder == null
                      ? Text(widget.code, style: codeStyle)
                      : Text.rich(
                          widget.highlightBuilder!(
                            widget.code,
                            widget.language,
                            codeStyle,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
