import 'package:flutter/material.dart';

/// Mixin providing scroll-to-bottom FAB logic shared by chat and roleplay screens.
mixin AutoScrollMixin<T extends StatefulWidget> on State<T> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  ScrollController get scrollController => _scrollController;
  bool get showScrollToBottom => _showScrollToBottom;
  set showScrollToBottom(bool value) => _showScrollToBottom = value;

  void initAutoScroll() {
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final isNearBottom =
          _scrollController.offset >= _scrollController.position.maxScrollExtent - 120;
      if (!isNearBottom && !_showScrollToBottom) {
        setState(() => _showScrollToBottom = true);
      } else if (isNearBottom && _showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
    }
  }

  void scrollToBottom([bool animate = true]) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
