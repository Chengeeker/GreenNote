import 'package:flutter/material.dart';

EdgeInsets editorKeyboardScrollPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    );

// Leave room to reveal the caret without shrinking the editor's fixed viewport.
class EditorKeyboardSpace extends StatelessWidget {
  const EditorKeyboardSpace({super.key});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MediaQuery.viewInsetsOf(context).bottom);
}
