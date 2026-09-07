import 'package:material_ui/material_ui.dart';

class CardBlock extends StatelessWidget {
  const CardBlock({
    super.key,
    required this.title,
    this.margin,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.color,
    this.icon,
    this.action,
    required this.child,
    this.footer,
    this.onTap
  });

  final String title;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Widget? icon;
  final Widget? action;
  final Widget? footer;
  final Widget child;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context) {

    final titleWidget = Row(
      children: [
        Offstage(offstage: icon == null, child: icon),
        Expanded(
          child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: .ellipsis,
          )
        ),
      ],
    );


    return Card(
      margin: margin,
      color: color,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: padding,
          child: Column(
            spacing: 6,
            crossAxisAlignment: .start,
            children: [
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: titleWidget
                  ),
                  Align(
                    alignment: .topRight,
                    child: Offstage(offstage: action == null, child: action),
                  )
                ],
              ),
              const SizedBox(height: 2),
              child,
              Offstage(offstage: footer == null, child: footer)
            ],
          ),
        )
      ),
    );
  }
}
