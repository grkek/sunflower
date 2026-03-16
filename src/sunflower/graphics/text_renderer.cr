# src/sunflower/graphics/text_renderer.cr
#
# Renders text strings into GL textures using Pango + Cairo.
# Uses sunflower_cairo_* wrappers (from src/ext/cairo_helpers.c) to
# avoid conflicting with gi-crystal's broken LibCairo bindings.

# Compile cairo_helpers.c at Crystal compile time
{% begin %}
  {% ext_dir = "#{__DIR__}/../../../src/ext" %}
  {% output = "#{__DIR__}/../../../bin/cairo_helpers.o" %}
  {% cflags = `pkg-config --cflags cairo 2>/dev/null`.strip %}
  {% result = `cc -c #{ext_dir.id}/cairo_helpers.c -o #{output.id} #{cflags.id} 2>&1` %}
  {% if result.includes?("error") %}
    {% raise "Failed to compile cairo_helpers.c:\n#{result}" %}
  {% end %}
{% end %}

@[Link(ldflags: "#{__DIR__}/../../../bin/cairo_helpers.o -lcairo")]
lib LibSunflowerCairo
  fun sunflower_cairo_image_surface_create(format : Int32, width : Int32, height : Int32) : Void*
  fun sunflower_cairo_create(surface : Void*) : Void*
  fun sunflower_cairo_destroy(cr : Void*) : Void
  fun sunflower_cairo_surface_destroy(surface : Void*) : Void
  fun sunflower_cairo_surface_flush(surface : Void*) : Void
  fun sunflower_cairo_image_surface_get_data(surface : Void*) : UInt8*
  fun sunflower_cairo_image_surface_get_stride(surface : Void*) : Int32
  fun sunflower_cairo_set_source_rgba(cr : Void*, r : Float64, g : Float64, b : Float64, a : Float64) : Void
  fun sunflower_cairo_set_operator(cr : Void*, op : Int32) : Void
  fun sunflower_cairo_paint(cr : Void*) : Void
  fun sunflower_cairo_move_to(cr : Void*, x : Float64, y : Float64) : Void
end

lib LibPango
  fun g_object_unref(obj : Void*) : Void
end

module Sunflower
  module Graphics
    class TextRenderer
      Log = ::Log.for(self)

      CAIRO_FORMAT_ARGB32   = 0
      CAIRO_OPERATOR_SOURCE = 1
      CAIRO_OPERATOR_OVER   = 2

      struct CachedText
        getter texture_id : UInt32
        getter width : Int32
        getter height : Int32
        property age : Int32

        def initialize(@texture_id, @width, @height)
          @age = 0
        end
      end

      MAX_CACHE_SIZE = 256
      MAX_CACHE_AGE  = 300

      @cache : Hash(String, CachedText) = {} of String => CachedText

      def initialize
      end

      def setup(widget : Gtk::Widget) : Nil
      end

      def render(
        renderer : Renderer,
        text : String,
        x : Float64, y : Float64,
        r : Float64, g : Float64, b : Float64, a : Float64,
        size : Float64
      ) : Nil
        return if text.empty?

        cache_key = "#{text}:#{size.to_i}"
        cached = @cache[cache_key]?

        unless cached
          cached = rasterize(text, size)
          return unless cached

          if @cache.size >= MAX_CACHE_SIZE
            evict_oldest
          end

          @cache[cache_key] = cached
        end

        cached.age = 0

        renderer.draw_textured_quad(
          cached.texture_id,
          x, y,
          cached.width.to_f64, cached.height.to_f64,
          r, g, b, a
        )
      end

      def tick : Nil
        keys_to_delete = [] of String
        @cache.each do |key, entry|
          entry.age += 1
          if entry.age > MAX_CACHE_AGE
            keys_to_delete << key
          end
        end
        keys_to_delete.each do |key|
          if entry = @cache.delete(key)
            id = entry.texture_id
            LibGL.glDeleteTextures(1, pointerof(id))
          end
        end
      end

      def cleanup : Nil
        @cache.each do |_, entry|
          id = entry.texture_id
          LibGL.glDeleteTextures(1, pointerof(id))
        end
        @cache.clear
      end

      private def rasterize(text : String, size : Float64) : CachedText?
        # Create temp surface to measure text
        tmp_surface = LibSunflowerCairo.sunflower_cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1)
        tmp_cr = LibSunflowerCairo.sunflower_cairo_create(tmp_surface)

        # Create Pango layout via PangoCairo (uses existing gi-crystal binding)
        raw_layout = LibPangoCairo.pango_cairo_create_layout(tmp_cr)

        # Set text and font
        LibPango.pango_layout_set_text(raw_layout, text.to_unsafe, text.bytesize)
        font_desc = Pango::FontDescription.from_string("Helvetica Neue Light #{size.to_i}")
        LibPango.pango_layout_set_font_description(raw_layout, font_desc.to_unsafe)

        # Measure
        width = 0_i32
        height = 0_i32
        LibPango.pango_layout_get_pixel_size(raw_layout, pointerof(width), pointerof(height))

        # Cleanup temp
        LibPango.g_object_unref(raw_layout)
        LibSunflowerCairo.sunflower_cairo_destroy(tmp_cr)
        LibSunflowerCairo.sunflower_cairo_surface_destroy(tmp_surface)

        return nil if width <= 0 || height <= 0

        # Create real surface at measured size
        surface = LibSunflowerCairo.sunflower_cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height)
        cr = LibSunflowerCairo.sunflower_cairo_create(surface)

        # Clear to transparent
        LibSunflowerCairo.sunflower_cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0)
        LibSunflowerCairo.sunflower_cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
        LibSunflowerCairo.sunflower_cairo_paint(cr)

        # Draw text in white — color tinting happens in the GL shader
        LibSunflowerCairo.sunflower_cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
        LibSunflowerCairo.sunflower_cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0)
        LibSunflowerCairo.sunflower_cairo_move_to(cr, 0.0, 0.0)

        # Create layout for real surface and render
        real_layout = LibPangoCairo.pango_cairo_create_layout(cr)
        LibPango.pango_layout_set_text(real_layout, text.to_unsafe, text.bytesize)
        LibPango.pango_layout_set_font_description(real_layout, font_desc.to_unsafe)
        LibPangoCairo.pango_cairo_show_layout(cr, real_layout)

        LibSunflowerCairo.sunflower_cairo_surface_flush(surface)

        # Get pixel data
        data_ptr = LibSunflowerCairo.sunflower_cairo_image_surface_get_data(surface)
        stride = LibSunflowerCairo.sunflower_cairo_image_surface_get_stride(surface)

        if data_ptr.null?
          LibPango.g_object_unref(real_layout)
          LibSunflowerCairo.sunflower_cairo_destroy(cr)
          LibSunflowerCairo.sunflower_cairo_surface_destroy(surface)
          return nil
        end

        texture_id = upload_texture(data_ptr, width, height, stride)

        # Cleanup
        LibPango.g_object_unref(real_layout)
        LibSunflowerCairo.sunflower_cairo_destroy(cr)
        LibSunflowerCairo.sunflower_cairo_surface_destroy(surface)

        CachedText.new(texture_id, width, height)
      end

      private def upload_texture(data : UInt8*, width : Int32, height : Int32, stride : Int32) : UInt32
        LibGL.glGenTextures(1, out tex_id)
        LibGL.glBindTexture(LibGL::GL_TEXTURE_2D, tex_id)
        LibGL.glTexParameteri(LibGL::GL_TEXTURE_2D, LibGL::GL_TEXTURE_MIN_FILTER, LibGL::GL_LINEAR.to_i32)
        LibGL.glTexParameteri(LibGL::GL_TEXTURE_2D, LibGL::GL_TEXTURE_MAG_FILTER, LibGL::GL_LINEAR.to_i32)

        # Cairo ARGB32 is BGRA on little-endian — swap to RGBA for GL
        pixels = Bytes.new(width * height * 4)
        height.times do |row|
          row_ptr = data + row * stride
          width.times do |col|
            src = col * 4
            dst = (row * width + col) * 4
            pixels[dst]     = row_ptr[src + 2] # R
            pixels[dst + 1] = row_ptr[src + 1] # G
            pixels[dst + 2] = row_ptr[src]     # B
            pixels[dst + 3] = row_ptr[src + 3] # A
          end
        end

        LibGL.glTexImage2D(
          LibGL::GL_TEXTURE_2D, 0,
          LibGL::GL_RGBA.to_i32,
          width, height, 0,
          LibGL::GL_RGBA, LibGL::GL_UNSIGNED_BYTE,
          pixels.to_unsafe.as(Void*)
        )

        tex_id
      end

      private def evict_oldest : Nil
        oldest_key = nil
        oldest_age = -1
        @cache.each do |key, entry|
          if entry.age > oldest_age
            oldest_age = entry.age
            oldest_key = key
          end
        end
        if key = oldest_key
          if entry = @cache.delete(key)
            id = entry.texture_id
            LibGL.glDeleteTextures(1, pointerof(id))
          end
        end
      end
    end
  end
end
