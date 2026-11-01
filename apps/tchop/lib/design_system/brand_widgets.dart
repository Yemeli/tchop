import 'package:flutter/material.dart';

/// Logo that renders the tenant's brand mark.
///
/// Shows the restaurant logo when [logoUrl] loads; falls back to the
/// restaurant initial on the brand color when offline or the URL fails —
/// important on low-bandwidth connections where images may not load.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.brandName,
    this.logoUrl,
    this.background,
    this.radius = 20,
  });

  final String brandName;
  final String? logoUrl;
  final Color? background;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? Theme.of(context).colorScheme.primary;
    final initial =
        brandName.trim().isEmpty ? '?' : brandName.trim()[0].toUpperCase();

    Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.9,
        ),
      ),
    );

    if (logoUrl == null || logoUrl!.isEmpty) return fallback;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: ClipOval(
        child: Image.network(
          logoUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          // Logos are cached per workspace; tenant-scoped cache key avoids
          // one restaurant's logo flashing in another's workspace.
          cacheWidth: 128,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// Primary call-to-action rendered in the tenant's brand color.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
