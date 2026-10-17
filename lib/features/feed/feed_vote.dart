import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';

class FeedVote extends StatefulWidget {
  const FeedVote({
    required this.api,
    required this.feedId,
    required this.vote,
    super.key,
  });
  final CoolapkApi api;
  final String feedId;
  final Map<String, dynamic> vote;
  @override
  State<FeedVote> createState() => _FeedVoteState();
}

class _FeedVoteState extends State<FeedVote> {
  late Map<String, dynamic> _vote = Map.of(widget.vote);
  final _selected = <String>{};
  bool _busy = false;
  bool _submitted = false;
  int number(String key, int fallback) =>
      int.tryParse('${_vote[key]}') ?? fallback;
  bool get _voted =>
      _submitted ||
      const ['user_vote', 'userVote', 'is_vote', 'isVote', 'voted'].any((key) {
        final v = _vote[key];
        return v == true ||
            v == 1 ||
            (v is List && v.isNotEmpty) ||
            (v is Map && v.isNotEmpty);
      });
  bool get _expired {
    final end = number('end_time', 0);
    return end > 0 && DateTime.now().millisecondsSinceEpoch ~/ 1000 >= end;
  }

  @override
  void didUpdateWidget(covariant FeedVote old) {
    super.didUpdateWidget(old);
    if (old.feedId != widget.feedId) {
      _vote = Map.of(widget.vote);
      _submitted = false;
      _selected.clear();
    }
  }

  Future<void> _submit() async {
    if (_busy || _voted || _expired) return;
    if (!widget.api.hasCookie) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    if (_selected.length < number('min_select_num', 1)) {
      AppToast.show(context, '请选择至少 ${number('min_select_num', 1)} 项');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.api.submitVote(
        widget.feedId,
        _selected.toList(),
        anonymous: number('anonymous_status', 0) == 1,
      );
      if (!mounted) return;
      final data = result['data'];
      final returned = data is Map ? (data['vote'] ?? data) : null;
      setState(() {
        if (returned is Map) {
          _vote = {..._vote, ...Map<String, dynamic>.from(returned)};
        }
        _submitted = true;
      });
      AppToast.show(context, '投票成功');
    } catch (e) {
      if (mounted) AppToast.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(Map<String, dynamic> option) {
    if (_voted || _expired || _busy) return;
    if (!widget.api.hasCookie) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    final id = '${option['id'] ?? ''}';
    if (id.isEmpty) return;
    final max = number('max_select_num', 1);
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (max == 1) {
        _selected
          ..clear()
          ..add(id);
      } else if (_selected.length < max) {
        _selected.add(id);
      }
    });
    if (max == 1) _submit();
  }

  @override
  Widget build(BuildContext context) {
    final options =
        (_vote['options'] is List ? _vote['options'] as List : const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
    final versus = number('type', 1) == 0 && options.length == 2;
    Widget option(Map<String, dynamic> row, int index) {
      final color = versus
          ? (index == 0 ? const Color(0xFFF44336) : const Color(0xFF2196F3))
          : Theme.of(context).colorScheme.primary;
      final count = row['vote_num'] ?? row['voteNum'] ?? row['count'];
      return InkWell(
        onTap: () => _select(row),
        borderRadius: BorderRadius.circular(versus ? 24 : 6),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: versus ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(versus ? 24 : 6),
            border: versus
                ? null
                : Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
          ),
          child: Row(
            children: [
              if (!versus)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    _selected.contains('${row['id']}')
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: color,
                  ),
                ),
              Expanded(
                child: Text(
                  '${row['title'] ?? ''}',
                  textAlign: versus ? TextAlign.center : TextAlign.start,
                  style: TextStyle(fontSize: 14, color: versus ? color : null),
                ),
              ),
              if ((_voted || _expired) && count != null)
                Text('$count票', style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (versus)
            Row(
              children: [
                Expanded(child: option(options[0], 0)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.blue,
                      fontSize: 24,
                    ),
                  ),
                ),
                Expanded(child: option(options[1], 1)),
              ],
            )
          else
            for (var i = 0; i < options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: option(options[i], i),
              ),
          if (!versus && !_voted && !_expired)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy ? '正在提交' : '投票（最多 ${number('max_select_num', 1)} 项）',
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '${number('total_vote_num', 0)}人投票 · ${number('total_comment_num', 0)}个观点${_expired
                ? ' · 已结束'
                : _voted
                ? ' · 已投票'
                : ''}',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
