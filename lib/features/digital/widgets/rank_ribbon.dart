import 'package:flutter/material.dart';

class RibbonClipper extends CustomClipper<Path> {
  const RibbonClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.78)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class RankRibbon extends StatelessWidget {
  const RankRibbon({
    required this.rank,
    this.width = 16,
    this.height = 20,
    super.key,
  });

  final int rank;
  final double width;
  final double height;

  Color get _ribbonColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFF443C); // red
      case 2:
        return const Color(0xFFFF8700); // orange
      case 3:
        return const Color(0xFFFFBD00); // yellow
      case 4:
        return const Color(0xFFC5DF2D); // yellow-green
      default:
        return const Color(0xFF7A7F85); // gray
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const RibbonClipper(),
      child: Container(
        width: width,
        height: height,
        color: _ribbonColor,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 1),
        child: Text(
          '$rank',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
