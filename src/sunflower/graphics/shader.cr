module Sunflower
  module Graphics
    class Shader
      Log = ::Log.for(self)

      def self.compile(vertex_source : String, fragment_source : String) : UInt32
        vs = compile_stage(LibGL::GL_VERTEX_SHADER, vertex_source)
        fs = compile_stage(LibGL::GL_FRAGMENT_SHADER, fragment_source)

        program = LibGL.glCreateProgram
        LibGL.glAttachShader(program, vs)
        LibGL.glAttachShader(program, fs)
        LibGL.glLinkProgram(program)

        status = 0_i32
        LibGL.glGetProgramiv(program, LibGL::GL_LINK_STATUS, pointerof(status))
        if status == 0
          buf = Bytes.new(1024)
          LibGL.glGetProgramInfoLog(program, 1024, nil, buf.to_unsafe)
          Log.error { "Shader link error: #{String.new(buf.to_unsafe)}" }
        end

        LibGL.glDeleteShader(vs)
        LibGL.glDeleteShader(fs)

        program
      end

      private def self.compile_stage(type : UInt32, source : String) : UInt32
        shader = LibGL.glCreateShader(type)
        ptr = source.to_unsafe
        LibGL.glShaderSource(shader, 1, pointerof(ptr), nil)
        LibGL.glCompileShader(shader)

        status = 0_i32
        LibGL.glGetShaderiv(shader, LibGL::GL_COMPILE_STATUS, pointerof(status))
        if status == 0
          buf = Bytes.new(1024)
          LibGL.glGetShaderInfoLog(shader, 1024, nil, buf.to_unsafe)
          stage_name = type == LibGL::GL_VERTEX_SHADER ? "vertex" : "fragment"
          Log.error { "#{stage_name} shader error: #{String.new(buf.to_unsafe)}" }
        end

        shader
      end
    end
  end
end
