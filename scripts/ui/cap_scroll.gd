class_name CapScroll
extends ScrollContainer

## A ScrollContainer that does NOT report its child's size as its minimum
## size (Jeremy 2026-10-11, war-spare modal clipping audit).
##
## Standard ScrollContainer always reports its child's full size, which
## makes it impossible to cap a dialog's height: the dialog grows to fit
## the content and pushes its buttons off-screen (Jeremy's P0
## menu-clipping pattern). CapScroll reports only its explicit custom
## minimum size, so a fixed-height dialog can host it: it takes whatever
## the layout gives it and scrolls internally. The child keeps its full
## size, so scrolling works normally.
func _get_minimum_size() -> Vector2:
	return custom_minimum_size
