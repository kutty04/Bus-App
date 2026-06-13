import 'package:flutter/material.dart';
import '../data/mtc_data.dart';

// ─────────────────────────────────────────────
//  ROUTE SELECTOR
//  Search + autocomplete from kMtcRoutes
//  Calls onSelect(routeNo) when user picks a route
// ─────────────────────────────────────────────
class RouteSelector extends StatefulWidget {
  final String busRoute;
  final void Function(String route) onSelect;

  const RouteSelector({
    super.key,
    required this.busRoute,
    required this.onSelect,
  });

  @override
  State<RouteSelector> createState() => _RouteSelectorState();
}

class _RouteSelectorState extends State<RouteSelector> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<MtcRoute> _suggestions = [];
  bool _showDropdown = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.busRoute;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _showDropdown = false;
      });
      return;
    }

    final results = kMtcRoutes
        .where((r) =>
            r.routeNo.toLowerCase().startsWith(query) ||
            r.routeNo.toLowerCase().contains(query) ||
            r.source.toLowerCase().contains(query) ||
            r.destination.toLowerCase().contains(query))
        .take(8)
        .toList();

    setState(() {
      _suggestions = results;
      _showDropdown = results.isNotEmpty;
    });
  }

  void _selectRoute(MtcRoute route) {
    _controller.text = route.routeNo;
    _focusNode.unfocus();
    setState(() {
      _suggestions = [];
      _showDropdown = false;
    });
    widget.onSelect(route.routeNo);
  }

  void _confirmManualEntry() {
    final val = _controller.text.trim();
    if (val.isNotEmpty) {
      _focusNode.unfocus();
      setState(() {
        _suggestions = [];
        _showDropdown = false;
      });
      widget.onSelect(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search field ──────────────────────
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            onSubmitted: (_) => _confirmManualEntry(),
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'Enter bus number (e.g. 19, 21C)',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontWeight: FontWeight.normal,
                fontSize: 14,
              ),
              prefixIcon: const Icon(Icons.directions_bus_rounded, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _suggestions = [];
                          _showDropdown = false;
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),

        // ── Dropdown suggestions ──────────────
        if (_showDropdown) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2433),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              itemBuilder: (context, i) {
                final route = _suggestions[i];
                return InkWell(
                  onTap: () => _selectRoute(route),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        // Route number badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            route.routeNo,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // From → To
                        Expanded(
                          child: Text(
                            '${route.source} → ${route.destination}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 16, color: Colors.white30),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // ── Current selection display ─────────
        if (widget.busRoute.isNotEmpty && !_showDropdown) ...[
          const SizedBox(height: 8),
          _buildSelectedRoute(context),
        ],
      ],
    );
  }

  Widget _buildSelectedRoute(BuildContext context) {
    // Try to find the route info from kMtcRoutes
    final match = kMtcRoutes
        .where((r) => r.routeNo == widget.busRoute)
        .toList();

    if (match.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: Colors.white38),
            const SizedBox(width: 6),
            Text(
              'Bus ${widget.busRoute} — custom / community route',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final r = match.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${r.source} → ${r.destination}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}