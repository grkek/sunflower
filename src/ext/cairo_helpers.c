// Thin wrappers around Cairo C functions that gi-crystal bound
// with incorrect signatures. Compiled into Sunflower's own object.

#include <cairo.h>

cairo_surface_t *sunflower_cairo_image_surface_create(int format, int width, int height) {
    return cairo_image_surface_create((cairo_format_t)format, width, height);
}

cairo_t *sunflower_cairo_create(cairo_surface_t *surface) {
    return cairo_create(surface);
}

void sunflower_cairo_destroy(cairo_t *cr) {
    cairo_destroy(cr);
}

void sunflower_cairo_surface_destroy(cairo_surface_t *surface) {
    cairo_surface_destroy(surface);
}

void sunflower_cairo_surface_flush(cairo_surface_t *surface) {
    cairo_surface_flush(surface);
}

unsigned char *sunflower_cairo_image_surface_get_data(cairo_surface_t *surface) {
    return cairo_image_surface_get_data(surface);
}

int sunflower_cairo_image_surface_get_stride(cairo_surface_t *surface) {
    return cairo_image_surface_get_stride(surface);
}

void sunflower_cairo_set_source_rgba(cairo_t *cr, double r, double g, double b, double a) {
    cairo_set_source_rgba(cr, r, g, b, a);
}

void sunflower_cairo_set_operator(cairo_t *cr, int op) {
    cairo_set_operator(cr, (cairo_operator_t)op);
}

void sunflower_cairo_paint(cairo_t *cr) {
    cairo_paint(cr);
}

void sunflower_cairo_move_to(cairo_t *cr, double x, double y) {
    cairo_move_to(cr, x, y);
}