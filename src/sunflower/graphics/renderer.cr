module Sunflower
  module Graphics
    class Renderer
      Log = ::Log.for(self)

      VERTEX_SHADER = <<-GLSL
        #version 330 core
        layout(location = 0) in vec2 aPos;
        layout(location = 1) in vec4 aColor;
        layout(location = 2) in vec2 aTexCoord;
        uniform mat4 uProjection;
        out vec4 vColor;
        out vec2 vTexCoord;
        void main() {
          gl_Position = uProjection * vec4(aPos, 0.0, 1.0);
          vColor = aColor;
          vTexCoord = aTexCoord;
        }
      GLSL

      FRAGMENT_SHADER = <<-GLSL
        #version 330 core
        in vec4 vColor;
        in vec2 vTexCoord;
        uniform sampler2D uTexture;
        uniform int uUseTexture;
        out vec4 FragColor;
        void main() {
          if (uUseTexture == 1) {
            FragColor = texture(uTexture, vTexCoord) * vColor;
          } else {
            FragColor = vColor;
          }
        }
      GLSL

      # 8 floats per vertex: x, y, r, g, b, a, u, v
      VERTEX_SIZE  =     8
      MAX_VERTICES = 65536
      BUFFER_SIZE  = MAX_VERTICES * VERTEX_SIZE

      getter program : UInt32 = 0
      getter vao : UInt32 = 0
      getter vbo : UInt32 = 0
      getter projection_loc : Int32 = 0
      getter use_texture_loc : Int32 = 0

      @vertices : Array(Float32) = Array(Float32).new(BUFFER_SIZE)
      @vertex_count : Int32 = 0
      @initialized : Bool = false
      @width : Float32 = 800_f32
      @height : Float32 = 600_f32

      def initialized? : Bool
        @initialized
      end

      def initialize_gl : Nil
        return if @initialized

        @program = Shader.compile(VERTEX_SHADER, FRAGMENT_SHADER)
        @projection_loc = LibGL.glGetUniformLocation(@program, "uProjection")
        @use_texture_loc = LibGL.glGetUniformLocation(@program, "uUseTexture")

        LibGL.glGenVertexArrays(1, out vao_id)
        @vao = vao_id
        LibGL.glBindVertexArray(@vao)

        LibGL.glGenBuffers(1, out vbo_id)
        @vbo = vbo_id
        LibGL.glBindBuffer(LibGL::GL_ARRAY_BUFFER, @vbo)
        LibGL.glBufferData(LibGL::GL_ARRAY_BUFFER, BUFFER_SIZE * 4, nil, LibGL::GL_DYNAMIC_DRAW)

        stride = VERTEX_SIZE * 4

        # Position (location 0)
        LibGL.glEnableVertexAttribArray(0_u32)
        LibGL.glVertexAttribPointer(0_u32, 2, LibGL::GL_FLOAT, LibGL::GL_FALSE, stride, Pointer(Void).null)

        # Color (location 1)
        LibGL.glEnableVertexAttribArray(1_u32)
        LibGL.glVertexAttribPointer(1_u32, 4, LibGL::GL_FLOAT, LibGL::GL_FALSE, stride, Pointer(Void).new(8))

        # TexCoord (location 2)
        LibGL.glEnableVertexAttribArray(2_u32)
        LibGL.glVertexAttribPointer(2_u32, 2, LibGL::GL_FLOAT, LibGL::GL_FALSE, stride, Pointer(Void).new(24))

        @initialized = true
        Log.debug { "GL Renderer initialized (program: #{@program}, vao: #{@vao}, vbo: #{@vbo})" }
      end

      # Standard begin_frame — viewport and projection use the same dimensions.
      def begin_frame(width : Int32, height : Int32) : Nil
        begin_frame(width, height, width, height)
      end

      # HiDPI-aware begin_frame — viewport uses physical pixels, projection uses
      # logical points. This lets draw commands use logical coordinates (e.g. 800x500)
      # while rendering at full Retina resolution.
      def begin_frame(viewport_width : Int32, viewport_height : Int32, projection_width : Int32, projection_height : Int32) : Nil
        @width = projection_width.to_f32
        @height = projection_height.to_f32
        @vertices.clear
        @vertex_count = 0

        LibGL.glViewport(0, 0, viewport_width, viewport_height)
        LibGL.glEnable(LibGL::GL_BLEND)
        LibGL.glBlendFunc(LibGL::GL_SRC_ALPHA, LibGL::GL_ONE_MINUS_SRC_ALPHA)
        LibGL.glUseProgram(@program)

        # Orthographic projection: (0,0) top-left, (width,height) bottom-right
        proj = orthographic(0_f32, @width, @height, 0_f32, -1_f32, 1_f32)
        LibGL.glUniformMatrix4fv(@projection_loc, 1, LibGL::GL_FALSE, proj.to_unsafe)
        LibGL.glUniform1i(@use_texture_loc, 0)
      end

      def end_frame : Nil
        flush
      end

      def clear(r : Float32, g : Float32, b : Float32, a : Float32 = 1.0_f32) : Nil
        LibGL.glClearColor(r, g, b, a)
        LibGL.glClear(LibGL::GL_COLOR_BUFFER_BIT)
      end

      def fill_rect(x : Float64, y : Float64, w : Float64, h : Float64, r : Float64, g : Float64, b : Float64, a : Float64 = 1.0) : Nil
        x1, y1 = x.to_f32, y.to_f32
        x2, y2 = (x + w).to_f32, (y + h).to_f32
        push_vertex(x1, y1, r, g, b, a)
        push_vertex(x2, y1, r, g, b, a)
        push_vertex(x2, y2, r, g, b, a)
        push_vertex(x1, y1, r, g, b, a)
        push_vertex(x2, y2, r, g, b, a)
        push_vertex(x1, y2, r, g, b, a)
      end

      def stroke_rect(x : Float64, y : Float64, w : Float64, h : Float64, r : Float64, g : Float64, b : Float64, a : Float64 = 1.0, line_width : Float64 = 1.0) : Nil
        lw = line_width
        fill_rect(x, y, w, lw, r, g, b, a)          # top
        fill_rect(x, y + h - lw, w, lw, r, g, b, a) # bottom
        fill_rect(x, y, lw, h, r, g, b, a)          # left
        fill_rect(x + w - lw, y, lw, h, r, g, b, a) # right
      end

      def fill_circle(cx : Float64, cy : Float64, radius : Float64, r : Float64, g : Float64, b : Float64, a : Float64 = 1.0, segments : Int32 = 32) : Nil
        segments.times do |i|
          angle1 = (i.to_f64 / segments) * Math::PI * 2
          angle2 = ((i + 1).to_f64 / segments) * Math::PI * 2

          push_vertex(cx.to_f32, cy.to_f32, r, g, b, a)
          push_vertex((cx + Math.cos(angle1) * radius).to_f32, (cy + Math.sin(angle1) * radius).to_f32, r, g, b, a)
          push_vertex((cx + Math.cos(angle2) * radius).to_f32, (cy + Math.sin(angle2) * radius).to_f32, r, g, b, a)
        end
      end

      def stroke_circle(cx : Float64, cy : Float64, radius : Float64, r : Float64, g : Float64, b : Float64, a : Float64 = 1.0, line_width : Float64 = 1.0, segments : Int32 = 32) : Nil
        inner = radius - line_width / 2
        outer = radius + line_width / 2

        segments.times do |i|
          angle1 = (i.to_f64 / segments) * Math::PI * 2
          angle2 = ((i + 1).to_f64 / segments) * Math::PI * 2

          ix1 = (cx + Math.cos(angle1) * inner).to_f32
          iy1 = (cy + Math.sin(angle1) * inner).to_f32
          ox1 = (cx + Math.cos(angle1) * outer).to_f32
          oy1 = (cy + Math.sin(angle1) * outer).to_f32
          ix2 = (cx + Math.cos(angle2) * inner).to_f32
          iy2 = (cy + Math.sin(angle2) * inner).to_f32
          ox2 = (cx + Math.cos(angle2) * outer).to_f32
          oy2 = (cy + Math.sin(angle2) * outer).to_f32

          push_vertex(ix1, iy1, r, g, b, a)
          push_vertex(ox1, oy1, r, g, b, a)
          push_vertex(ox2, oy2, r, g, b, a)
          push_vertex(ix1, iy1, r, g, b, a)
          push_vertex(ox2, oy2, r, g, b, a)
          push_vertex(ix2, iy2, r, g, b, a)
        end
      end

      def draw_line(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, r : Float64, g : Float64, b : Float64, a : Float64 = 1.0, line_width : Float64 = 1.0) : Nil
        dx = x2 - x1
        dy = y2 - y1
        len = Math.sqrt(dx * dx + dy * dy)
        return if len == 0

        nx = (-dy / len) * line_width * 0.5
        ny = (dx / len) * line_width * 0.5

        push_vertex((x1 + nx).to_f32, (y1 + ny).to_f32, r, g, b, a)
        push_vertex((x1 - nx).to_f32, (y1 - ny).to_f32, r, g, b, a)
        push_vertex((x2 - nx).to_f32, (y2 - ny).to_f32, r, g, b, a)
        push_vertex((x1 + nx).to_f32, (y1 + ny).to_f32, r, g, b, a)
        push_vertex((x2 - nx).to_f32, (y2 - ny).to_f32, r, g, b, a)
        push_vertex((x2 + nx).to_f32, (y2 + ny).to_f32, r, g, b, a)
      end

      def fill_triangle(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, x3 : Float64, y3 : Float64, r : Float64, g : Float64, b : Float64, a : Float64 = 1.0) : Nil
        push_vertex(x1.to_f32, y1.to_f32, r, g, b, a)
        push_vertex(x2.to_f32, y2.to_f32, r, g, b, a)
        push_vertex(x3.to_f32, y3.to_f32, r, g, b, a)
      end

      # Draw a textured quad — used for text rendering.
      # The texture contains white text on transparent background.
      # The color (r, g, b, a) tints it via the shader: FragColor = texture * vColor.
      def draw_textured_quad(
        texture_id : UInt32,
        x : Float64, y : Float64,
        w : Float64, h : Float64,
        r : Float64, g : Float64, b : Float64, a : Float64 = 1.0
      ) : Nil
        # Flush any pending non-textured geometry first
        flush

        # Enable texturing
        LibGL.glActiveTexture(LibGL::GL_TEXTURE0)
        LibGL.glBindTexture(LibGL::GL_TEXTURE_2D, texture_id)
        LibGL.glUniform1i(@use_texture_loc, 1)

        x1, y1 = x.to_f32, y.to_f32
        x2, y2 = (x + w).to_f32, (y + h).to_f32

        push_vertex_uv(x1, y1, r, g, b, a, 0_f32, 0_f32)
        push_vertex_uv(x2, y1, r, g, b, a, 1_f32, 0_f32)
        push_vertex_uv(x2, y2, r, g, b, a, 1_f32, 1_f32)
        push_vertex_uv(x1, y1, r, g, b, a, 0_f32, 0_f32)
        push_vertex_uv(x2, y2, r, g, b, a, 1_f32, 1_f32)
        push_vertex_uv(x1, y2, r, g, b, a, 0_f32, 1_f32)

        # Flush the textured quad
        flush

        # Disable texturing for subsequent non-textured geometry
        LibGL.glUniform1i(@use_texture_loc, 0)
      end

      private def push_vertex(x : Float32, y : Float32, r : Float64, g : Float64, b : Float64, a : Float64) : Nil
        push_vertex_uv(x, y, r, g, b, a, 0_f32, 0_f32)
      end

      private def push_vertex_uv(x : Float32, y : Float32, r : Float64, g : Float64, b : Float64, a : Float64, u : Float32, v : Float32) : Nil
        if @vertex_count >= MAX_VERTICES
          flush
        end

        @vertices << x
        @vertices << y
        @vertices << r.to_f32
        @vertices << g.to_f32
        @vertices << b.to_f32
        @vertices << a.to_f32
        @vertices << u
        @vertices << v
        @vertex_count += 1
      end

      private def flush : Nil
        return if @vertex_count == 0

        LibGL.glBindVertexArray(@vao)
        LibGL.glBindBuffer(LibGL::GL_ARRAY_BUFFER, @vbo)
        LibGL.glBufferSubData(LibGL::GL_ARRAY_BUFFER, 0_i64, (@vertex_count * VERTEX_SIZE * 4).to_i64, @vertices.to_unsafe.as(Void*))
        LibGL.glDrawArrays(LibGL::GL_TRIANGLES, 0, @vertex_count)

        @vertices.clear
        @vertex_count = 0
      end

      private def orthographic(left : Float32, right : Float32, bottom : Float32, top : Float32, near : Float32, far : Float32) : StaticArray(Float32, 16)
        StaticArray[
          2_f32 / (right - left), 0_f32, 0_f32, 0_f32,
          0_f32, 2_f32 / (top - bottom), 0_f32, 0_f32,
          0_f32, 0_f32, -2_f32 / (far - near), 0_f32,
          -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1_f32,
        ]
      end

      def cleanup : Nil
        return unless @initialized
        LibGL.glDeleteBuffers(1, pointerof(@vbo))
        LibGL.glDeleteVertexArrays(1, pointerof(@vao))
        LibGL.glDeleteProgram(@program)
        @initialized = false
      end
    end
  end
end
